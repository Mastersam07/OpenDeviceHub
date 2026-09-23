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
