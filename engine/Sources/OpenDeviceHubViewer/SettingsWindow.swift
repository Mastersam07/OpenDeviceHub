import AppKit
import OpenDeviceHubEngine
import SwiftUI

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
    init(settings: ViewerSettings, actions: SettingsActions) {
        let view = SettingsView(settings: settings, actions: actions)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
}

/// A grouped form with switches, which is what a Mac settings window looks like now. Built in
/// SwiftUI for exactly that reason: the same thing in AppKit is a stack of checkboxes that does not
/// resemble any other settings window on the system.
@MainActor
private struct SettingsView: View {
    private let settings: ViewerSettings
    private let actions: SettingsActions

    @State private var shutsDownOnWindowClose: Bool
    @State private var bootsMostRecentOnStart: Bool
    @State private var automaticUpdates: Bool
    @State private var captureDirectory: URL?

    init(settings: ViewerSettings, actions: SettingsActions) {
        self.settings = settings
        self.actions = actions
        _shutsDownOnWindowClose = State(initialValue: settings.shutsDownOnWindowClose)
        _bootsMostRecentOnStart = State(initialValue: settings.bootsMostRecentOnStart)
        _automaticUpdates = State(initialValue: actions.automaticUpdates?() ?? false)
        _captureDirectory = State(initialValue: settings.captureDirectory)
    }

    var body: some View {
        Form {
            Section("Simulators") {
                Toggle("Shut a simulator down when its window closes", isOn: Binding(
                    get: { shutsDownOnWindowClose },
                    set: { value in
                        settings.shutsDownOnWindowClose = value
                        shutsDownOnWindowClose = value
                    }
                ))
                .help("Off leaves simulators running after you close their windows.")

                Toggle("Start the last simulator used when nothing is running", isOn: Binding(
                    get: { bootsMostRecentOnStart },
                    set: { value in
                        settings.bootsMostRecentOnStart = value
                        bootsMostRecentOnStart = value
                    }
                ))
                .help("Simulators that are already running are always shown, either way.")
            }

            Section("Screenshots and recordings") {
                LabeledContent {
                    HStack(spacing: 8) {
                        if captureDirectory != nil {
                            Button("Use Desktop") {
                                settings.captureDirectory = nil
                                captureDirectory = nil
                            }
                        }
                        Button("Choose\u{2026}", action: chooseCaptureDirectory)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save to")
                        Text(captureDirectory?.path(percentEncoded: false) ?? "Desktop")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Section("Windows") {
                LabeledContent {
                    Button("Forget", action: actions.forgetWindowPositions)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remembered positions")
                        Text("Each device's window reopens where you last put it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let setAutomaticUpdates = actions.setAutomaticUpdates {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { automaticUpdates },
                        set: { value in
                            setAutomaticUpdates(value)
                            automaticUpdates = value
                        }
                    ))
                }
            }

            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Brand.productName).font(.headline)
                        Text(version).font(.subheadline).foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let checkForUpdates = actions.checkForUpdates {
                        Button("Check for Updates\u{2026}", action: checkForUpdates)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollDisabled(true)
        .frame(width: 520, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var version: String {
        Brand.isDevelopmentBuild
            ? "Built from source"
            : "Version \(Brand.version) (\(Brand.buildNumber))"
    }

    private func chooseCaptureDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = captureDirectory
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        settings.captureDirectory = chosen
        captureDirectory = chosen
    }
}
