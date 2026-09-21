import AppKit
import MetalKit
import OpenDeviceHubEngine

/// Draws only when a frame arrives, so the measured rate is the simulator's output rate rather
/// than a fixed animation timer.
public final class DeviceScreenView: MTKView {
    public enum ContactPhase: Sendable {
        case began
        case moved
        case ended
    }

    public enum ContactStyle: Sendable {
        case single
        /// Option held: the pointer is one finger and its mirror through the centre is the other.
        case mirrored
        /// Option and Shift held: two fingers travelling together.
        case parallel
    }

    /// Reports a click in the view's own coordinates, whose origin is the bottom left.
    public var onContact: ((CGPoint, ContactPhase, ContactStyle) -> Void)?
    /// Reports a trackpad pinch or rotate, as a spread in view points and an angle in radians.
    public var onGesture: ((ContactPhase, CGFloat, CGFloat) -> Void)?
    /// Reports a hardware key, already translated to a USB HID usage.
    public var onKey: ((UInt32, Bool) -> Void)?

    private var gestureSpread: CGFloat = 0
    private var gestureAngle: CGFloat = 0
    private var isGestureActive = false

    private func style(for event: NSEvent) -> ContactStyle {
        guard event.modifierFlags.contains(.option) else { return .single }
        return event.modifierFlags.contains(.shift) ? .parallel : .mirrored
    }

    public init(device: MTLDevice) {
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        registerForDrops()
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

    public override var acceptsFirstResponder: Bool { true }

    /// Reports files and URLs dropped on the device.
    public var onDrop: (([URL], String?) -> Bool)?

    private func registerForDrops() {
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDrop == nil ? [] : .copy
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let onDrop else { return false }
        let pasteboard = sender.draggingPasteboard

        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL]) ?? []
        if !urls.isEmpty {
            return onDrop(urls, nil)
        }

        // A web or custom scheme URL, which opens on the device rather than being installed.
        if let text = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string),
           let scheme = URLComponents(string: text)?.scheme, !scheme.isEmpty {
            return onDrop([], text)
        }
        return false
    }

    public override func keyDown(with event: NSEvent) {
        guard let usage = KeyboardMap.usage(forVirtualKeyCode: event.keyCode) else {
            super.keyDown(with: event)
            return
        }
        onKey?(usage, true)
    }

    public override func keyUp(with event: NSEvent) {
        guard let usage = KeyboardMap.usage(forVirtualKeyCode: event.keyCode) else {
            super.keyUp(with: event)
            return
        }
        onKey?(usage, false)
    }

    public override func mouseDown(with event: NSEvent) {
        onContact?(convert(event.locationInWindow, from: nil), .began, style(for: event))
    }

    public override func mouseDragged(with event: NSEvent) {
        onContact?(convert(event.locationInWindow, from: nil), .moved, style(for: event))
    }

    public override func mouseUp(with event: NSEvent) {
        onContact?(convert(event.locationInWindow, from: nil), .ended, style(for: event))
    }

    public override func magnify(with event: NSEvent) {
        // A trackpad pinch reports a relative change, so it is accumulated into a spread measured
        // in view points, starting from a quarter of the shorter edge.
        updateGesture(phase: event.phase, spreadDelta: event.magnification * min(bounds.width, bounds.height), angleDelta: 0)
    }

    public override func rotate(with event: NSEvent) {
        updateGesture(phase: event.phase, spreadDelta: 0, angleDelta: CGFloat(-event.rotation) * .pi / 180)
    }

    private func updateGesture(phase: NSEvent.Phase, spreadDelta: CGFloat, angleDelta: CGFloat) {
        switch phase {
        case .began:
            gestureSpread = min(bounds.width, bounds.height) / 4
            gestureAngle = 0
            isGestureActive = true
            onGesture?(.began, gestureSpread, gestureAngle)
        case .changed:
            guard isGestureActive else { return }
            gestureSpread = max(gestureSpread + spreadDelta, 1)
            gestureAngle += angleDelta
            onGesture?(.moved, gestureSpread, gestureAngle)
        case .ended, .cancelled:
            guard isGestureActive else { return }
            isGestureActive = false
            onGesture?(.ended, gestureSpread, gestureAngle)
        default:
            break
        }
    }
}
