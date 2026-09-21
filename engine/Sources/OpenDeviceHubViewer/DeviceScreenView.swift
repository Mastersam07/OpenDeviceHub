import AppKit
import MetalKit

/// Draws only when a frame arrives, so the measured rate is the simulator's output rate rather
/// than a fixed animation timer.
public final class DeviceScreenView: MTKView {
    public enum ContactPhase: Sendable {
        case began
        case moved
        case ended
    }

    /// Reports a click in the view's own coordinates, whose origin is the bottom left.
    public var onContact: ((CGPoint, ContactPhase) -> Void)?

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

    /// A click should tap the device even when the window was not already focused, which is how
    /// the classic Simulator behaves. Without this AppKit swallows the activating click.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public override func mouseDown(with event: NSEvent) {
        onContact?(convert(event.locationInWindow, from: nil), .began)
    }

    public override func mouseDragged(with event: NSEvent) {
        onContact?(convert(event.locationInWindow, from: nil), .moved)
    }

    public override func mouseUp(with event: NSEvent) {
        onContact?(convert(event.locationInWindow, from: nil), .ended)
    }
}
