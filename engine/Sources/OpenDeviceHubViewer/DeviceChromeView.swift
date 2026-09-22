import AppKit
import OpenDeviceHubEngine

/// Draws the device's body around the screen and puts its buttons where the chrome says they go.
/// With no chrome the screen is shown on its own. Either way the device keeps its shape and is
/// centred, so full screen leaves a black margin rather than stretching anything.
public final class DeviceChromeView: NSView {
    public var onButton: ((HardwareButton, ButtonPhase) -> Void)?

    private let screenView: NSView
    private var chrome: DeviceChrome?
    private var composite: NSImage?
    private var slices: [String: NSImage] = [:]
    private var buttonImages: [String: NSImage] = [:]
    private var pressed: ChromeButton?
    private var screenSize: CGSize = .zero
    private var orientation: DeviceOrientation = .portrait
    private var hovered: ChromeButton?
    private var tracking: NSTrackingArea?

    public init(screenView: NSView) {
        self.screenView = screenView
        super.init(frame: .zero)
        addSubview(screenView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    public override var isFlipped: Bool { false }

    /// Nil takes the body away and gives the screen the whole view back.
    /// The device's upright screen size, which the body is sized against.
    public func setScreenSize(_ size: CGSize) {
        screenSize = size
        needsLayout = true
        needsDisplay = true
    }

    public func setOrientation(_ orientation: DeviceOrientation) {
        self.orientation = orientation
        needsLayout = true
        needsDisplay = true
    }

    public func setChrome(_ chrome: DeviceChrome?) {
        self.chrome = chrome
        composite = nil
        slices = [:]
        buttonImages = [:]
        if let chrome {
            if let url = chrome.compositeURL { composite = NSImage(contentsOf: url) }
            if let parts = chrome.slices {
                for name in [
                    parts.topLeft, parts.top, parts.topRight, parts.left,
                    parts.right, parts.bottomLeft, parts.bottom, parts.bottomRight,
                ] {
                    slices[name] = NSImage(contentsOf: chrome.resource(name))
                }
            }
            for button in chrome.buttons {
                buttonImages[button.image] = NSImage(contentsOf: chrome.resource(button.image))
                buttonImages[button.imageDown] = NSImage(contentsOf: chrome.resource(button.imageDown))
            }
        }
        needsLayout = true
        needsDisplay = true
    }

    public var hasChrome: Bool {
        guard chrome != nil else { return false }
        return composite != nil || !slices.isEmpty
    }

    /// The screen's area inside this view, which is everything when there is no body.
    public var screenRect: CGRect {
        guard screenSize.width > 0, screenSize.height > 0 else { return bounds }
        guard let chrome, hasChrome else {
            // No body to fit, so the screen itself is what gets centred.
            return CoordinateMapper.fittedRect(
                viewSize: bounds.size,
                pixelSize: orientation.displayedSize(portraitNative: screenSize)
            )
        }
        return ChromeGeometry.screenRect(
            viewSize: bounds.size, screen: screenSize, chrome: chrome, orientation: orientation
        )
    }

    /// Everything the device occupies, which is the body when there is one and the bare screen
    /// otherwise. Anything outside it is margin.
    private var occupiedRect: CGRect {
        guard let chrome, hasChrome, screenSize.width > 0 else { return screenRect }
        return ChromeGeometry.deviceRect(
            viewSize: bounds.size, screen: screenSize, chrome: chrome, orientation: orientation
        )
    }

    private var deviceTransform: CGAffineTransform {
        guard let chrome, hasChrome, screenSize.width > 0 else { return .identity }
        return ChromeGeometry.deviceTransform(
            viewSize: bounds.size, screen: screenSize, chrome: chrome, orientation: orientation
        )
    }

    private var uprightSize: CGSize {
        guard let chrome else { return bounds.size }
        return ChromeGeometry.contentSize(screen: screenSize, chrome: chrome)
    }

    public override func layout() {
        super.layout()
        screenView.frame = screenRect
        overlay?.frame = screenRect
    }

    /// Covers the device's screen, and only the screen, so the body still frames whatever the
    /// overlay is saying.
    public var overlay: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let overlay {
                overlay.frame = screenRect
                addSubview(overlay, positioned: .above, relativeTo: screenView)
            }
            needsLayout = true
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        // A window the size of the device has no margin, so this paints nothing until full screen
        // or a resize leaves room around it.
        fillMargin(around: occupiedRect)

        guard let chrome, hasChrome, screenSize.width > 0 else { return }
        guard let context = NSGraphicsContext.current else { return }

        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        // Everything below is in the device's own upright space, so it turns with the device.
        context.cgContext.concatenate(deviceTransform)

        let body = ChromeGeometry.bodyRect(content: uprightSize, chrome: chrome)

        // A side button sits under the body, so only the sliver standing proud of it shows. Drawing
        // it over the body instead leaves a slab stuck to the surface.
        drawButtons(chrome, onTop: false)

        if let composite {
            composite.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
        } else if let parts = chrome.slices {
            // The home button phones and the tablets ship the pieces rather than one body, so the
            // edges are stretched between fixed corners.
            NSDrawNinePartImage(
                body,
                slices[parts.topLeft], slices[parts.top], slices[parts.topRight],
                slices[parts.left], nil, slices[parts.right],
                slices[parts.bottomLeft], slices[parts.bottom], slices[parts.bottomRight],
                .sourceOver, 1, false
            )
        }

        drawButtons(chrome, onTop: true)
    }

    private func fillMargin(around rect: CGRect) {
        NSColor.black.setFill()
        for margin in ChromeGeometry.margins(around: rect, in: bounds) {
            margin.fill()
        }
    }

    private func drawButtons(_ chrome: DeviceChrome, onTop: Bool) {
        for button in chrome.buttons where button.onTop == onTop {
            let name = pressed == button ? button.imageDown : button.image
            guard let image = buttonImages[name] ?? buttonImages[button.image] else { continue }
            let rect = ChromeGeometry.buttonRect(
                button,
                imageSize: buttonImages[button.image]?.size ?? image.size,
                content: uprightSize,
                chrome: chrome,
                hovered: hovered == button || pressed == button
            )
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private var imageSizes: [String: CGSize] {
        buttonImages.compactMapValues { $0.size }
    }

    private func button(at point: CGPoint) -> ChromeButton? {
        guard let chrome, hasChrome, screenSize.width > 0 else { return nil }
        let inDevice = point.applying(deviceTransform.inverted())
        return ChromeGeometry.button(
            at: inDevice, sizes: imageSizes, content: uprightSize, chrome: chrome
        )
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    public override func mouseMoved(with event: NSEvent) {
        setHovered(button(at: convert(event.locationInWindow, from: nil)))
    }

    public override func mouseExited(with event: NSEvent) {
        setHovered(nil)
    }

    private func setHovered(_ button: ChromeButton?) {
        guard hovered != button else { return }
        hovered = button
        needsDisplay = true
    }

    /// A press on a body button should work even when the window was not already focused, which is
    /// how the screen already behaves.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        // The screen keeps its own clicks; only the body's buttons are ours.
        let local = convert(point, from: superview)
        if button(at: local) != nil { return self }
        // A swipe up from the bottom of the device starts on the chin below the glass as often as
        // on it, the way a thumb does on a real phone. Without this the body swallows the contact
        // and the system gesture never begins.
        if isOnChin(local) { return screenView }
        return super.hitTest(point)
    }

    private func isOnChin(_ local: CGPoint) -> Bool {
        let screen = screenRect
        guard bounds.contains(local), !screen.contains(local) else { return false }
        return local.y < screen.minY && local.x >= screen.minX && local.x <= screen.maxX
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let button = button(at: point), let hardware = button.hardwareButton else { return }
        pressed = button
        needsDisplay = true
        onButton?(hardware, .down)
    }

    public override func mouseUp(with event: NSEvent) {
        guard let button = pressed, let hardware = button.hardwareButton else { return }
        pressed = nil
        needsDisplay = true
        onButton?(hardware, .up)
    }
}
