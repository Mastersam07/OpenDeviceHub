import AppKit

/// The window's content: the floating bar, and the device below it. Everything this view does not
/// cover is left clear, so the window's shadow follows the bar and the device rather than a
/// rectangle around them both.
@MainActor
public final class DevicePresentationView: NSView {
    public let bar: DeviceControlBar
    public let chrome: DeviceChromeView

    private var isFullScreen = false

    public init(bar: DeviceControlBar, chrome: DeviceChromeView) {
        self.bar = bar
        self.chrome = chrome
        super.init(frame: .zero)
        addSubview(chrome)
        addSubview(bar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    public override var isFlipped: Bool { false }

    public func setFullScreen(_ fullScreen: Bool) {
        isFullScreen = fullScreen
        needsLayout = true
    }

    public var currentLayout: PresentationLayout {
        PresentationLayout(contentSize: bounds.size, isFullScreen: isFullScreen)
    }

    /// The content covers the whole window, including the few points AppKit keeps at the edges for
    /// resizing, so the border has to be handed back or the window can only be resized from its
    /// corners by the window server. Nothing of ours lives out there: the device is inset well
    /// inside it.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let border = PresentationLayout.resizeBorder
        let inside = bounds.insetBy(dx: border, dy: border)
        if !inside.contains(local), !bar.frame.contains(local) { return nil }
        return super.hitTest(point)
    }

    public override func layout() {
        super.layout()
        let layout = currentLayout
        bar.frame = layout.bar
        bar.cornerRadius = layout.cornerRadius
        bar.isFullScreen = isFullScreen
        chrome.fillsMargin = isFullScreen
        chrome.frame = layout.device
    }
}
