import AppKit
import OpenDeviceHubEngine

/// The pose artwork Xcode ships, in the plug in Device Hub draws a foldable with. Nothing is copied
/// out of it: it is read from the installed Xcode, and where that is missing a system symbol stands
/// in.
@MainActor
enum DeviceKitIcons {
    private static let bundle: Bundle? = {
        guard let install = try? XcodeLocator.locate() else { return nil }
        return Bundle(url: install.appRoot.appending(
            path: "Contents/SharedFrameworks/DeviceKit.framework/Versions/A/PlugIns/CoreDevicePopDeviceKitExtension.devicekitplugin"
        ))
    }()

    static func image(named name: String) -> NSImage? {
        bundle?.image(forResource: NSImage.Name(name))
    }
}


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
    /// Only a foldable has one: the three positions it can be in, centred in the bar.
    private var foldModes: NSSegmentedControl?
    /// Reports the position chosen, so the window can fold the device.
    public var onFoldMode: ((FoldMode) -> Void)?
    /// Clear of the window's close, minimise and zoom buttons, the last of which ends at 80.
    private let titleLeading: CGFloat = 96
    /// What AppKit's own action group takes on the right, which nothing may be laid out under.
    private static let actionGroupWidth: CGFloat = 150

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

    /// The positions a foldable can be put in, matching the names the guest's own tooling uses.
    public enum FoldMode: Int, CaseIterable {
        case cover, partiallyOpen, fullyOpen

        public var label: String {
            switch self {
            case .cover: "Cover"
            case .partiallyOpen: "Partially Open"
            case .fullyOpen: "Fully Open"
            }
        }

        /// Drawn rather than written: the three names together are wider than the bar has to spare,
        /// and the shapes say which is which at a glance. Xcode ships artwork for exactly these
        /// three poses, so it is used where it is installed.
        var assetName: String {
            switch self {
            case .cover: "v68.closed"
            case .partiallyOpen: "v68.bent"
            case .fullyOpen: "v68.flat"
            }
        }

        var symbol: String {
            switch self {
            case .cover: "rectangle.portrait"
            case .partiallyOpen: "book"
            case .fullyOpen: "rectangle"
            }
        }

        @MainActor var image: NSImage? {
            if let artwork = DeviceKitIcons.image(named: assetName) {
                artwork.accessibilityDescription = label
                return artwork
            }
            return NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        }

        /// Which pose an angle counts as. Anything at or below the handoff is closed, and only a
        /// hinge all the way over is fully open.
        public static func mode(forHingeAngle angle: Double) -> FoldMode {
            if angle <= 15 { return .cover }
            if angle >= 179.5 { return .fullyOpen }
            return .partiallyOpen
        }

        public var angle: Double {
            switch self {
            case .cover: 0
            case .partiallyOpen: 120
            case .fullyOpen: 180
            }
        }

    }

    /// Adds the fold positions. Called only for a device that has a hinge, so every other window
    /// keeps a bar with nothing extra in it.
    public func addFoldModes() {
        guard foldModes == nil else { return }
        let control = NSSegmentedControl(
            images: FoldMode.allCases.map { $0.image ?? NSImage() },
            trackingMode: .selectOne,
            target: self,
            action: #selector(foldModeChanged)
        )
        control.segmentStyle = .rounded
        control.controlSize = .large
        control.selectedSegment = 0
        for (index, mode) in FoldMode.allCases.enumerated() {
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
            control.setToolTip(mode.label, forSegment: index)
            control.setWidth(40, forSegment: index)
        }
        control.setFrameSize(control.intrinsicContentSize)
        addSubview(control)
        foldModes = control
        needsLayout = true
    }

    /// Moves the selection without reporting it, for an angle that came from a pinch or elsewhere.
    public func showFoldAngle(_ degrees: Double) {
        foldModes?.selectedSegment = FoldMode.mode(forHingeAngle: degrees).rawValue
    }

    @objc private func foldModeChanged(_ sender: NSSegmentedControl) {
        guard let mode = FoldMode(rawValue: sender.selectedSegment) else { return }
        onFoldMode?(mode)
    }

    public var cornerRadius: CGFloat = 0 {
        didSet { layer?.cornerRadius = cornerRadius }
    }

    /// Full screen takes the window's buttons away, so the title has no reason to stand clear of
    /// them any more.
    public var isFullScreen = false {
        didSet { needsLayout = true }
    }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        let leading = isFullScreen ? 12 : titleLeading
        let width = max(bounds.width - leading - 12, 0)
        let top = (bounds.height - 30) / 2
        // Centred in the bar, but never under the action group AppKit lays out on the right, and
        // never over the title: the title gives way to it instead.
        var titleWidth = width
        if let foldModes {
            foldModes.sizeToFit()
            let size = foldModes.fittingSize
            let centred = ((bounds.width - size.width) / 2).rounded()
            let rightmost = bounds.width - Self.actionGroupWidth - size.width
            foldModes.frame = CGRect(
                x: max(leading, min(centred, rightmost)),
                y: ((bounds.height - size.height) / 2).rounded(),
                width: size.width,
                height: size.height
            )
            titleWidth = max(foldModes.frame.minX - leading - 12, 0)
        }
        name.frame = CGRect(x: leading, y: top, width: titleWidth, height: 16)
        runtime.frame = CGRect(x: leading, y: top + 15, width: titleWidth, height: 14)
    }

    /// A drag anywhere on the bar moves the window, the way a title bar does, since the window it
    /// belongs to has no visible one of its own.
    public override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
