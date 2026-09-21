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

vertex VertexOut odhVertex(uint id [[vertex_id]]) {
    const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    const float2 uvs[4] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    VertexOut out;
    out.position = float4(corners[id], 0, 1);
    out.uv = uvs[id];
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

    public func accept(_ frame: DisplayFrame) {
        lock.lock()
        defer { lock.unlock() }

        // The simulator usually keeps one surface and redraws into it, so the texture is rebuilt
        // only when the surface itself is replaced.
        if let lastSurface, CFEqual(lastSurface, frame.surface) { return }

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
        lastSurface = frame.surface
    }

    public func draw(in view: MTKView) {
        lock.lock()
        let current = texture
        lock.unlock()

        guard let current,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }

        // Letterbox rather than stretch. The window normally locks the device's aspect ratio, but
        // it does not in full screen or in Fit, and input already assumes a letterboxed image, so
        // stretching here would put clicks and pixels out of step.
        let fitted = CoordinateMapper.fittedRect(
            viewSize: view.drawableSize,
            pixelSize: CGSize(width: current.width, height: current.height)
        )
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
