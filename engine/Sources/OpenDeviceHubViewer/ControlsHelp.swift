import AppKit
import OpenDeviceHubEngine

public struct ControlsEntry: Equatable, Sendable {
    public let keys: String
    public let what: String

    public init(_ keys: String, _ what: String) {
        self.keys = keys
        self.what = what
    }
}

public struct ControlsSection: Equatable, Sendable {
    public let title: String
    public let entries: [ControlsEntry]

    public init(_ title: String, _ entries: [ControlsEntry]) {
        self.title = title
        self.entries = entries
    }
}

/// What the Help menu shows. There is no help book: writing one for two screens of shortcuts is a
/// lot of ceremony around a table. The content is data rather than a block of text so the columns
/// can be laid out and lined up, which is the whole reason a window beats an alert here.
@MainActor
public enum ControlsHelp {
    public static let title = "\(Brand.productName) Controls"

    /// Grouped by what your hands are doing rather than by which menu the command lives in, because
    /// that is how someone looks for the answer.
    public static let sections: [ControlsSection] = [
        ControlsSection("Pointer", [
            ControlsEntry("Drag", "Touch and swipe"),
            ControlsEntry("\u{2325} Drag", "Two fingers moving apart and together, which pinches"),
            ControlsEntry("\u{2325}\u{21E7} Drag", "Two fingers moving together"),
            ControlsEntry("Trackpad pinch", "Pinch on the device"),
            ControlsEntry("Trackpad rotate", "Two finger rotation"),
            ControlsEntry("Drag a corner", "Resize the window, keeping the device's shape"),
        ]),
        ControlsSection("Keyboard and clipboard", [
            ControlsEntry("Type", "Goes to the device"),
            ControlsEntry("\u{2318}V", "Paste the Mac's clipboard into the device"),
            ControlsEntry("\u{2303}\u{2318}C", "Copy the device's screen to the Mac"),
        ]),
        ControlsSection("Device", [
            ControlsEntry("\u{21E7}\u{2318}H", "Home"),
            ControlsEntry("\u{2318}L", "Lock"),
            ControlsEntry("\u{2325}\u{21E7}\u{2318}H", "Siri"),
            ControlsEntry("\u{2303}\u{21E7}\u{2318}H", "App Switcher"),
            ControlsEntry("\u{2303}\u{2318}Z", "Shake"),
            ControlsEntry("\u{2318}\u{2190}   \u{2318}\u{2192}", "Rotate left, rotate right"),
            ControlsEntry("\u{21E7}\u{2318}A", "Light and dark appearance"),
            ControlsEntry("\u{2318}\u{2191}   \u{2318}\u{2193}", "Volume up, volume down"),
        ]),
        ControlsSection("Capture", [
            ControlsEntry("\u{2318}S", "Save a screenshot to the Desktop"),
            ControlsEntry("\u{2318}R", "Record the screen, File > Stop Recording to finish"),
            ControlsEntry("\u{2318} Drag", "Drag a finished recording out of the window"),
            ControlsEntry("Drop a file", "Opens it on the device"),
        ]),
        ControlsSection("Window", [
            ControlsEntry("\u{2318}1  \u{2318}2  \u{2318}3  \u{2318}4", "Physical Size, Point Accurate, Pixel Accurate, Fit Screen"),
            ControlsEntry("\u{2318}B", "Show or hide the device body"),
            ControlsEntry("\u{2318}T", "Keep the window above other apps"),
            ControlsEntry("\u{2303}\u{2318}F", "Full screen"),
        ]),
        ControlsSection("Debug", [
            ControlsEntry("\u{2318}/", "Open the system log"),
            ControlsEntry("\u{21E7}\u{2318}M", "Simulate a memory warning"),
            ControlsEntry("\u{21E7}\u{2318}L", "Show click to frame latency"),
        ]),
    ]

    public static let footnote =
        "Simulators come from Xcode. Use File > Open Simulator, or the Dock icon, to start one."

    private static var controller: ControlsHelpWindowController?

    public static func show() {
        let existing = controller ?? ControlsHelpWindowController()
        controller = existing
        NSApplication.shared.activate(ignoringOtherApps: true)
        existing.showWindow(nil)
        existing.window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class ControlsHelpWindowController: NSWindowController {
    init() {
        let content = ControlsHelp.sections.reduce(into: NSStackView()) { stack, section in
            stack.addArrangedSubview(ControlsHelpWindowController.header(section.title))
            stack.addArrangedSubview(ControlsHelpWindowController.grid(section.entries))
        }
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        let note = NSTextField(wrappingLabelWithString: ControlsHelp.footnote)
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 420
        content.setCustomSpacing(18, after: content.arrangedSubviews[content.arrangedSubviews.count - 1])
        content.addArrangedSubview(note)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = content
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ControlsHelp.title
        window.contentView = scroll
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    private static func header(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    /// A grid rather than padded text: the key column only lines up if something measures it, and a
    /// proportional font makes spaces useless for that.
    private static func grid(_ entries: [ControlsEntry]) -> NSGridView {
        let rows = entries.map { entry -> [NSView] in
            let keys = NSTextField(labelWithString: entry.keys)
            keys.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            let what = NSTextField(labelWithString: entry.what)
            what.textColor = .secondaryLabelColor
            return [keys, what]
        }
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 16
        grid.rowSpacing = 6
        grid.column(at: 0).xPlacement = .trailing
        return grid
    }
}
