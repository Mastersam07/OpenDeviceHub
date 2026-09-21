import CoreGraphics
import Foundation
import IOSurface
import OpenDeviceHubPrivate

final class SimulatorDisplaySession: DisplaySession, @unchecked Sendable {
    let frames: AsyncStream<DisplayFrame>
    let pixelSize: CGSize
    let pointScale: CGFloat

    private let renderable: any ODHSimDisplayRenderable
    private let surfaceRenderable: any ODHSimDisplayIOSurfaceRenderable
    private let token = UUID()
    private let continuation: AsyncStream<DisplayFrame>.Continuation
    private let lock = NSLock()
    private var surface: IOSurfaceRef?
    private var isClosed = false

    init(descriptor: AnyObject, pointScale: CGFloat) throws {
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

        var escapingContinuation: AsyncStream<DisplayFrame>.Continuation!
        frames = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { escapingContinuation = $0 }
        continuation = escapingContinuation

        surface = Self.surface(from: surfaceRenderable.framebufferSurface)

        surfaceRenderable.registerCallback(with: token) { [weak self] changed in
            guard let self else { return }
            lock.lock()
            self.surface = Self.surface(from: changed) ?? Self.surface(from: self.surfaceRenderable.framebufferSurface)
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
        let current = surface
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
