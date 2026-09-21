import Foundation
import IOSurface
import Metal
import MetalKit
import OpenDeviceHubEngine

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut odhVertex(uint id [[vertex_id]], constant uint &quarterTurns [[buffer(0)]]) {
    const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    const float2 uvs[4] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    VertexOut out;
    out.position = float4(corners[id], 0, 1);
    // The framebuffer stays portrait native whichever way the device is turned, so the image is
    // rotated here by reading the texture through turned coordinates.
    float2 uv = uvs[id];
    for (uint turn = 0; turn < quarterTurns; turn++) {
        uv = float2(uv.y, 1.0 - uv.x);
    }
    out.uv = uv;
    return out;
}

fragment float4 odhFragment(VertexOut in [[stage_in]], texture2d<float> screen [[texture(0)]]) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    return screen.sample(linearSampler, in.uv);
}
"""

/// Renders the simulator's framebuffer into an `MTKView`. Textures are created directly from the
/// `IOSurface`, so a frame is never copied through the CPU.
public final class FrameRenderer: NSObject, MTKViewDelegate {
    public var onFrameDrawn: (() -> Void)?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let lock = NSLock()
    private var texture: MTLTexture?
    private var quarterTurns: UInt32 = 0
    private var lastSurface: IOSurfaceRef?

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw ViewerError.metalUnavailable("could not create a command queue")
        }
        commandQueue = queue

        let library = try device.makeLibrary(source: shaderSource, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "odhVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "odhFragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
    }

    /// The surface behind the most recent frame, for screenshots.
    public var currentSurface: IOSurfaceRef? {
        lock.lock()
        defer { lock.unlock() }
        return lastSurface
    }

    /// How far to turn the portrait native image so it matches the device's orientation.
    public func setOrientation(_ orientation: DeviceOrientation) {
        lock.lock()
        defer { lock.unlock() }
        quarterTurns = UInt32(orientation.degrees / 90)
    }

    public func accept(_ frame: DisplayFrame) {
        lock.lock()
        defer { lock.unlock() }

        // The simulator usually keeps one surface and redraws into it, so the texture is rebuilt
        // only when the surface itself is replaced. The surface is recorded either way, since a
        // screenshot needs the current one even when the texture is unchanged.
        let previous = lastSurface
        lastSurface = frame.surface
        if let previous, CFEqual(previous, frame.surface) { return }

        let width = IOSurfaceGetWidth(frame.surface)
        let height = IOSurfaceGetHeight(frame.surface)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared

        texture = device.makeTexture(descriptor: descriptor, iosurface: frame.surface, plane: 0)
    }

    public func draw(in view: MTKView) {
        lock.lock()
        let current = texture
        var turns = quarterTurns
        lock.unlock()

        guard let current,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }

        // Letterbox rather than stretch. The window normally locks the device's aspect ratio, but
        // it does not in full screen or in Fit, and input already assumes a letterboxed image, so
        // stretching here would put clicks and pixels out of step.
        // A quarter turn swaps which way round the image is, so the fit is computed against the
        // size actually being drawn.
        let drawnSize = turns % 2 == 0
            ? CGSize(width: current.width, height: current.height)
            : CGSize(width: current.height, height: current.width)
        let fitted = CoordinateMapper.fittedRect(viewSize: view.drawableSize, pixelSize: drawnSize)
        if fitted.width > 0, fitted.height > 0 {
            encoder.setViewport(MTLViewport(
                originX: Double(fitted.minX),
                originY: Double(fitted.minY),
                width: Double(fitted.width),
                height: Double(fitted.height),
                znear: 0,
                zfar: 1
            ))
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&turns, length: MemoryLayout<UInt32>.size, index: 0)
        encoder.setFragmentTexture(current, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()

        onFrameDrawn?()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

public enum ViewerError: Error, LocalizedError {
    case metalUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .metalUnavailable(let detail): "Metal is unavailable: \(detail)"
        }
    }
}
