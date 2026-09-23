import AppKit

/// The floating bar above a device: the window's own buttons, the device's name over its runtime,
/// and the native toolbar items, all on one piece of titlebar material.
///
/// The bar draws the material and the title only. The actions stay AppKit's own toolbar items,
/// laid out by AppKit in the titlebar band this bar is sized to match, so they keep the grouped
/// background and the hover and pressed states that come with being in its shared action group.
@MainActor
public final class DeviceControlBar: NSVisualEffectView {
    private let name = NSTextField(labelWithString: "")
    private let runtime = NSTextField(labelWithString: "")
    /// Clear of the window's close, minimise and zoom buttons, the last of which ends at 80.
    private let titleLeading: CGFloat = 96

    public init(deviceName: String, runtimeName: String) {
        super.init(frame: .zero)
        material = .titlebar
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous

        name.stringValue = deviceName
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingTail
        runtime.stringValue = runtimeName
        runtime.font = .systemFont(ofSize: 11)
        runtime.textColor = .secondaryLabelColor
        runtime.lineBreakMode = .byTruncatingTail
        addSubview(name)
        addSubview(runtime)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    public var cornerRadius: CGFloat = 0 {
        didSet { layer?.cornerRadius = cornerRadius }
    }

    /// Two rows stack the title above the actions, so the title starts at the window's edge rather
    /// than beside the buttons.
    public var isCompact = false {
        didSet { needsLayout = true }
    }

    /// Full screen takes the window's buttons away, so the title has no reason to stand clear of
    /// them any more.
    public var isFullScreen = false {
        didSet { needsLayout = true }
    }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        let leading = isCompact || isFullScreen ? 12 : titleLeading
        let width = max(bounds.width - leading - 12, 0)
        let top = isCompact ? 8.0 : (bounds.height - 30) / 2
        name.frame = CGRect(x: leading, y: top, width: width, height: 16)
        runtime.frame = CGRect(x: leading, y: top + 15, width: width, height: 14)
    }

    /// A drag anywhere on the bar moves the window, the way a title bar does, since the window it
    /// belongs to has no visible one of its own.
    public override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
