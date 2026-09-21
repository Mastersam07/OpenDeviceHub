import CoreGraphics
import Foundation
import IOSurface
import OpenDeviceHubPrivate

final class SimulatorDisplaySession: DisplaySession, @unchecked Sendable {
    let frames: AsyncStream<DisplayFrame>
    let pixelSize: CGSize
    let pointScale: CGFloat
    let pixelsPerInch: CGFloat?

    private let renderable: any ODHSimDisplayRenderable
    private let surfaceRenderable: any ODHSimDisplayIOSurfaceRenderable
    private let token = UUID()
    private let continuation: AsyncStream<DisplayFrame>.Continuation
    private let lock = NSLock()
    private var surface: IOSurfaceRef?
    private var maskedSurface: IOSurfaceRef?
    private var bezelEnabled: Bool
    private var isClosed = false

    var supportsBezel: Bool {
        lock.lock()
        defer { lock.unlock() }
        return maskedSurface != nil
    }

    func setBezelEnabled(_ enabled: Bool) {
        lock.lock()
        let changed = bezelEnabled != enabled && maskedSurface != nil
        if changed { bezelEnabled = enabled }
        lock.unlock()
        // The device only redraws when something on screen changes, so without an immediate frame
        // the window would keep showing the old shape until the next damage callback.
        if changed { emitCurrentFrame() }
    }

    init(descriptor: AnyObject, pointScale: CGFloat, bezelEnabled: Bool) throws {
        self.bezelEnabled = bezelEnabled
        let registerDamage = NSSelectorFromString("registerCallbackWithUUID:damageRectanglesCallback:")
        let registerSurfaces = NSSelectorFromString("registerCallbackWithUUID:ioSurfacesChangeCallback:")
        guard descriptor.responds(to: registerDamage), descriptor.responds(to: registerSurfaces) else {
            throw EngineError.symbolNotFound(
                name: "registerCallbackWithUUID: display callbacks",
                framework: "CoreSimDeviceIO"
            )
        }

        renderable = unsafeBitCast(descriptor, to: (any ODHSimDisplayRenderable).self)
        surfaceRenderable = unsafeBitCast(descriptor, to: (any ODHSimDisplayIOSurfaceRenderable).self)
        pixelSize = renderable.displaySize
        self.pointScale = pointScale
        // Named "pitch" but it reports pixels per inch: 460 on an iPhone 17 Pro and 326 on an
        // iPad mini, which reproduce both devices' advertised diagonals. Verified on 17F42.
        let pitch = renderable.displayPitch
        pixelsPerInch = pitch > 0 ? CGFloat(pitch) : nil

        var escapingContinuation: AsyncStream<DisplayFrame>.Continuation!
        frames = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { escapingContinuation = $0 }
        continuation = escapingContinuation

        surface = Self.surface(from: surfaceRenderable.framebufferSurface)
        maskedSurface = Self.surface(from: surfaceRenderable.maskedFramebufferSurface)

        surfaceRenderable.registerCallback(with: token) { [weak self] _ in
            guard let self else { return }
            lock.lock()
            self.surface = Self.surface(from: self.surfaceRenderable.framebufferSurface)
            self.maskedSurface = Self.surface(from: self.surfaceRenderable.maskedFramebufferSurface)
            lock.unlock()
            emitCurrentFrame()
        }
        renderable.registerCallback(with: token) { [weak self] _ in
            self?.emitCurrentFrame()
        }

        emitCurrentFrame()
    }

    func close() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        lock.unlock()

        renderable.unregisterDamageRectanglesCallback(with: token)
        surfaceRenderable.unregisterIOSurfacesChangeCallback(with: token)
        continuation.finish()
    }

    private func emitCurrentFrame() {
        lock.lock()
        let current = (bezelEnabled ? maskedSurface : nil) ?? surface
        let closed = isClosed
        lock.unlock()

        guard !closed, let current else { return }
        continuation.yield(DisplayFrame(surface: current, timestamp: mach_absolute_time()))
    }

    /// The callback hands back an `IOSurface` object, or sometimes nothing at all. `IOSurface` and
    /// `IOSurfaceRef` are toll free bridged, so the object is reinterpreted rather than converted.
    private static func surface(from value: Any?) -> IOSurfaceRef? {
        guard let value, CFGetTypeID(value as AnyObject) == IOSurfaceGetTypeID() else { return nil }
        return unsafeBitCast(value as AnyObject, to: IOSurfaceRef.self)
    }
}
