import AppKit
import OpenDeviceHubEngine

/// Draws the device's body around the screen and puts its buttons where the chrome says they go.
/// With no chrome the screen simply fills the view, which is how a device with no artwork behaves.
public final class DeviceChromeView: NSView {
    public var onButton: ((HardwareButton, ButtonPhase) -> Void)?

    private let screenView: NSView
    private var chrome: DeviceChrome?
    private var composite: NSImage?
    private var slices: [String: NSImage] = [:]
    private var buttonImages: [String: NSImage] = [:]
    private var pressed: ChromeButton?

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
        guard let chrome, hasChrome else { return bounds }
        return ChromeGeometry.screenRect(content: bounds.size, chrome: chrome)
    }

    public override func layout() {
        super.layout()
        screenView.frame = screenRect
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let chrome, hasChrome else { return }
        let body = ChromeGeometry.bodyRect(content: bounds.size, chrome: chrome)
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

        for button in chrome.buttons {
            let name = pressed == button ? button.imageDown : button.image
            guard let image = buttonImages[name] ?? buttonImages[button.image] else { continue }
            let rect = ChromeGeometry.buttonRect(
                button,
                imageSize: buttonImages[button.image]?.size ?? image.size,
                content: bounds.size,
                chrome: chrome
            )
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private var imageSizes: [String: CGSize] {
        buttonImages.compactMapValues { $0.size }
    }

    private func button(at point: CGPoint) -> ChromeButton? {
        guard let chrome, hasChrome else { return nil }
        return ChromeGeometry.button(
            at: point, sizes: imageSizes, content: bounds.size, chrome: chrome
        )
    }

    /// A press on a body button should work even when the window was not already focused, which is
    /// how the screen already behaves.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        // The screen keeps its own clicks; only the body's buttons are ours.
        let local = convert(point, from: superview)
        if button(at: local) != nil { return self }
        return super.hitTest(point)
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
