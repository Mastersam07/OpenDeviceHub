import AppKit

/// The window's content: the floating bar, and the device below it. Everything this view does not
/// cover is left clear, so the window's shadow follows the bar and the device rather than a
/// rectangle around them both.
@MainActor
public final class DevicePresentationView: NSView {
    public let bar: DeviceControlBar
    public let chrome: DeviceChromeView
    /// Only a foldable has one, so every other window lays out exactly as it did.
    public let foldBar: FoldControlBar?

    private var isFullScreen = false

    public init(bar: DeviceControlBar, chrome: DeviceChromeView, foldBar: FoldControlBar? = nil) {
        self.bar = bar
        self.chrome = chrome
        self.foldBar = foldBar
        super.init(frame: .zero)
        addSubview(chrome)
        addSubview(bar)
        if let foldBar { addSubview(foldBar) }
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
        PresentationLayout(
            contentSize: bounds.size,
            isFullScreen: isFullScreen,
            hasFoldBar: foldBar != nil
        )
    }

    /// The content covers the whole window, including the few points AppKit keeps at the edges for
    /// resizing, so the border has to be handed back or an edge drag never reaches the window.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let border = PresentationLayout.resizeBorder
        let inside = bounds.insetBy(dx: border, dy: border)
        if !inside.contains(local), !bar.frame.contains(local),
           !(foldBar?.frame.contains(local) ?? false) { return nil }
        return super.hitTest(point)
    }

    /// Which corner of the device, if any, is under this point. The device is easier to grab than
    /// the window's edges, and it is the thing being sized.
    public func resizeCorner(at point: CGPoint) -> DeviceResizeCorner? {
        let device = deviceBodyRect
        guard !device.isEmpty else { return nil }
        return DeviceResizeCorner.allCases.first {
            $0.hitRect(in: device, cornerRadius: chrome.bodyCornerRadius).contains(point)
        }
    }

    /// Where the device is actually drawn, which is inside the chrome's frame once the body has
    /// been fitted and centred.
    public var deviceBodyRect: CGRect {
        chrome.convert(chrome.bodyRect, to: self)
    }

    public override func layout() {
        super.layout()
        let layout = currentLayout
        bar.frame = layout.bar
        bar.cornerRadius = layout.cornerRadius
        bar.isFullScreen = isFullScreen
        chrome.fillsMargin = isFullScreen
        chrome.frame = layout.device
        foldBar?.frame = layout.foldBar
    }
}
