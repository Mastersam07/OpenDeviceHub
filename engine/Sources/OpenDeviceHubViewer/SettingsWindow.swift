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
    public var setPasteboardSync: ((Bool) -> Void)?
    public var forgetWindowPositions: () -> Void
    public var rememberedWindowCount: () -> Int
    public var openLinks: DefaultDeviceApplication?

    public init(
        automaticUpdates: (() -> Bool)? = nil,
        setAutomaticUpdates: ((Bool) -> Void)? = nil,
        checkForUpdates: (() -> Void)? = nil,
        setPasteboardSync: ((Bool) -> Void)? = nil,
        forgetWindowPositions: @escaping () -> Void,
        rememberedWindowCount: @escaping () -> Int,
        openLinks: DefaultDeviceApplication? = nil
    ) {
        self.automaticUpdates = automaticUpdates
        self.setAutomaticUpdates = setAutomaticUpdates
        self.checkForUpdates = checkForUpdates
        self.setPasteboardSync = setPasteboardSync
        self.forgetWindowPositions = forgetWindowPositions
        self.rememberedWindowCount = rememberedWindowCount
        self.openLinks = openLinks
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
        window.styleMask = [.titled, .closable, .resizable]
        window.minSize = NSSize(width: 420, height: 360)
        window.setContentSize(NSSize(width: 520, height: 620))
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
    @State private var syncsPasteboard: Bool
    @State private var savesScreenshotsToClipboard: Bool
    @State private var automaticUpdates: Bool
    @State private var screenshotDirectory: URL?
    @State private var recordingDirectory: URL?
    @State private var rememberedWindows: Int
    @State private var favorites: [LocationFavorite]
    @ObservedObject private var links: DefaultDeviceApplication

    init(settings: ViewerSettings, actions: SettingsActions) {
        self.settings = settings
        self.actions = actions
        _shutsDownOnWindowClose = State(initialValue: settings.shutsDownOnWindowClose)
        _bootsMostRecentOnStart = State(initialValue: settings.bootsMostRecentOnStart)
        _syncsPasteboard = State(initialValue: settings.syncsPasteboard)
        _savesScreenshotsToClipboard = State(initialValue: settings.savesScreenshotsToClipboard)
        _automaticUpdates = State(initialValue: actions.automaticUpdates?() ?? false)
        _screenshotDirectory = State(initialValue: settings.screenshotDirectory)
        _recordingDirectory = State(initialValue: settings.recordingDirectory)
        _rememberedWindows = State(initialValue: actions.rememberedWindowCount())
        _favorites = State(initialValue: settings.locationFavorites)
        links = actions.openLinks ?? DefaultDeviceApplication()
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

            Section("Screenshots") {
                Toggle("Save screenshots to the clipboard instead of files", isOn: Binding(
                    get: { savesScreenshotsToClipboard },
                    set: { value in
                        settings.savesScreenshotsToClipboard = value
                        savesScreenshotsToClipboard = value
                    }
                ))
                .help("Save Screen places the captured image on the Mac clipboard and does not create a file.")

                LabeledContent {
                    HStack(spacing: 8) {
                        if screenshotDirectory != nil {
                            Button("Use Desktop") {
                                settings.screenshotDirectory = nil
                                screenshotDirectory = nil
                            }
                        }
                        Button("Choose\u{2026}", action: chooseScreenshotDirectory)
                    }
                    .disabled(savesScreenshotsToClipboard)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save to")
                        Text(screenshotDirectory?.path(percentEncoded: false) ?? "Desktop")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Section("Recordings") {
                LabeledContent {
                    HStack(spacing: 8) {
                        if recordingDirectory != nil {
                            Button("Use Desktop") {
                                settings.recordingDirectory = nil
                                recordingDirectory = nil
                            }
                        }
                        Button("Choose\u{2026}", action: chooseRecordingDirectory)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save to")
                        Text(recordingDirectory?.path(percentEncoded: false) ?? "Desktop")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Section("Pasteboard") {
                Toggle("Automatically sync the Mac and device pasteboards", isOn: Binding(
                    get: { syncsPasteboard },
                    set: { value in
                        settings.syncsPasteboard = value
                        actions.setPasteboardSync?(value)
                        syncsPasteboard = value
                    }
                ))
                .help("Copies made on either side are sent to the other side automatically.")
                // Edit, Automatically Sync Pasteboard changes the same setting while this is open.
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                    syncsPasteboard = settings.syncsPasteboard
                }
            }

            Section("Windows") {
                LabeledContent {
                    Button("Forget") {
                        actions.forgetWindowPositions()
                        rememberedWindows = actions.rememberedWindowCount()
                    }
                    .disabled(rememberedWindows == 0)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remembered positions")
                        // The count is the feedback. Pressing Forget takes it to none and greys the
                        // button, so nothing has to announce that it worked.
                        Text(rememberedDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Location favorites") {
                ForEach(favorites) { favorite in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(favorite.name)
                            Text(String(format: "%.5f, %.5f", favorite.latitude, favorite.longitude))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) { removeFavorite(favorite) }
                    }
                }
                Button("Add Favorite…", action: addFavorite)
            }

            if actions.openLinks != nil {
                Section("Links") {
                    LabeledContent {
                        Button(links.isOurs
                            ? "Use \(links.previousHandlerName ?? "Device Hub")"
                            : "Use \(Brand.productName)") {
                            if links.isOurs { links.handBack() } else { links.takeOver() }
                        }
                        .disabled(links.isBusy)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open devices:// links with")
                            Text(links.failure ?? links.handlerName ?? "Nothing handles these links.")
                                .font(.footnote)
                                .foregroundStyle(links.failure == nil ? .secondary : Color.red)
                        }
                    }
                }
            }

            if let setAutomaticUpdates = actions.setAutomaticUpdates {
                Section("Updates") {
                    Toggle("Install updates automatically", isOn: Binding(
                        get: { automaticUpdates },
                        set: { value in
                            setAutomaticUpdates(value)
                            automaticUpdates = value
                        }
                    ))
                    .help("Checks and downloads in the background. Installing still waits for you.")
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

                    VStack(alignment: .trailing, spacing: 8) {
                        if let checkForUpdates = actions.checkForUpdates {
                            Button("Check for Updates\u{2026}", action: checkForUpdates)
                        }
                        if let repository = URL(string: "https://github.com/Mastersam07/OpenDeviceHub") {
                            Link("GitHub", destination: repository)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        // Form supplies the native scroll view. Keep the window resizable and let the form occupy
        // the available height instead of growing the window indefinitely as settings are added.
        .scrollDisabled(false)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 360, idealHeight: 620,
               alignment: .topLeading)
    }

    private var rememberedDescription: String {
        switch rememberedWindows {
        case 0: "No window positions are remembered."
        case 1: "One device's window reopens where you left it."
        default: "\(rememberedWindows) devices' windows reopen where you left them."
        }
    }

    private var version: String {
        Brand.isDevelopmentBuild
            ? "Built from source"
            : "Version \(Brand.version) (\(Brand.buildNumber))"
    }

    private func addFavorite() {
        guard let favorite = LocationFavoritePrompt.ask() else { return }
        favorites.append(favorite)
        settings.locationFavorites = favorites
    }

    private func removeFavorite(_ favorite: LocationFavorite) {
        favorites.removeAll { $0.id == favorite.id }
        settings.locationFavorites = favorites
    }

    private func chooseScreenshotDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = screenshotDirectory
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        settings.screenshotDirectory = chosen
        screenshotDirectory = chosen
    }

    private func chooseRecordingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = recordingDirectory
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        settings.recordingDirectory = chosen
        recordingDirectory = chosen
    }
}

@MainActor
private enum LocationFavoritePrompt {
    static func ask() -> LocationFavorite? {
        let alert = NSAlert(); alert.messageText = "Add Location Favorite"
        alert.informativeText = "Enter a name and latitude, longitude."
        // NSTextField() and NSStackView() start with a zero-sized frame on AppKit. If they are
        // installed directly as an alert accessory, the alert collapses them to a tiny capsule
        // (especially on compact/macOS alert styles). Give the accessory and its fields an explicit
        // width and height so both inputs remain visible and keyboard-friendly.
        let width: CGFloat = 320
        let fieldHeight: CGFloat = 24
        let name = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: fieldHeight))
        name.placeholderString = "Name"
        let coordinate = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: fieldHeight))
        coordinate.placeholderString = "Latitude, longitude (e.g. 37.3349, -122.0090)"
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: width, height: fieldHeight * 2 + 8))
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.addArrangedSubview(name)
        stack.addArrangedSubview(coordinate)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
              !name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let point = Coordinate(parsing: coordinate.stringValue) else { return nil }
        return LocationFavorite(name: name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), latitude: point.latitude, longitude: point.longitude)
    }
}
