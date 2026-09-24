import AppKit
import OpenDeviceHubEngine

/// What Settings can act on. Passed in rather than reached for, so the window has no opinion about
/// where updates or window frames live.
@MainActor
public struct SettingsActions {
    public var automaticUpdates: (() -> Bool)?
    public var setAutomaticUpdates: ((Bool) -> Void)?
    public var checkForUpdates: (() -> Void)?
    public var forgetWindowPositions: () -> Void

    public init(
        automaticUpdates: (() -> Bool)? = nil,
        setAutomaticUpdates: ((Bool) -> Void)? = nil,
        checkForUpdates: (() -> Void)? = nil,
        forgetWindowPositions: @escaping () -> Void
    ) {
        self.automaticUpdates = automaticUpdates
        self.setAutomaticUpdates = setAutomaticUpdates
        self.checkForUpdates = checkForUpdates
        self.forgetWindowPositions = forgetWindowPositions
    }
}

@MainActor
public enum SettingsWindow {
    private static var controller: SettingsWindowController?

    public static func show(settings: ViewerSettings, actions: SettingsActions) {
        let existing = controller ?? SettingsWindowController(settings: settings, actions: actions)
        controller = existing
        NSApplication.shared.activate(ignoringOtherApps: true)
        existing.showWindow(nil)
        existing.window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: ViewerSettings
    private let actions: SettingsActions

    init(settings: ViewerSettings, actions: SettingsActions) {
        self.settings = settings
        self.actions = actions

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let stack = NSStackView(views: [
            Self.header("Simulators"),
            checkbox(
                "Shut a simulator down when its window closes",
                on: settings.shutsDownOnWindowClose,
                action: #selector(toggleShutdownOnClose(_:))
            ),
            checkbox(
                "Start the last simulator used when nothing is running",
                on: settings.bootsMostRecentOnStart,
                action: #selector(toggleBootMostRecent(_:))
            ),
            Self.header("Screenshots and recordings"),
            captureRow(),
            Self.header("Windows"),
            button("Forget Remembered Positions", #selector(forgetPositions)),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        if actions.automaticUpdates != nil {
            stack.addArrangedSubview(Self.header("Updates"))
            stack.addArrangedSubview(checkbox(
                "Check for updates automatically",
                on: actions.automaticUpdates?() ?? false,
                action: #selector(toggleAutomaticUpdates(_:))
            ))
        }

        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    private static func header(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    private func checkbox(_ title: String, on: Bool, action: Selector) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: self, action: action)
        box.state = on ? .on : .off
        return box
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    /// The chosen folder is shown rather than just a button, because "where do my screenshots go"
    /// is the question this setting exists to answer.
    private func captureRow() -> NSStackView {
        let row = NSStackView(views: [captureLabel, button("Choose\u{2026}", #selector(chooseCaptureDirectory))])
        row.orientation = .horizontal
        row.spacing = 12
        return row
    }

    private lazy var captureLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    override func showWindow(_ sender: Any?) {
        updateCaptureLabel()
        super.showWindow(sender)
    }

    private func updateCaptureLabel() {
        captureLabel.stringValue = settings.captureDirectory?.path(percentEncoded: false) ?? "Desktop"
    }

    @objc private func toggleShutdownOnClose(_ sender: NSButton) {
        settings.shutsDownOnWindowClose = sender.state == .on
    }

    @objc private func toggleBootMostRecent(_ sender: NSButton) {
        settings.bootsMostRecentOnStart = sender.state == .on
    }

    @objc private func toggleAutomaticUpdates(_ sender: NSButton) {
        actions.setAutomaticUpdates?(sender.state == .on)
    }

    @objc private func forgetPositions() {
        actions.forgetWindowPositions()
    }

    @objc private func chooseCaptureDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = settings.captureDirectory
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        settings.captureDirectory = chosen
        updateCaptureLabel()
    }
}
