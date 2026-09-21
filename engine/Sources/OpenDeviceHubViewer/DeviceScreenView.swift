import MetalKit

/// Draws only when a frame arrives, so the measured rate is the simulator's output rate rather
/// than a fixed animation timer.
public final class DeviceScreenView: MTKView {
    public init(device: MTLDevice) {
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("not supported")
    }
}
