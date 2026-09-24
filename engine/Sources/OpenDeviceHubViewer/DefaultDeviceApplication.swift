import AppKit
import OpenDeviceHubEngine

/// Who handles `devices://` links, and changing it.
///
/// Device Hub owns the scheme out of the box. Taking it over is a choice a person makes in Settings
/// and can undo there, never something the app does to them on launch.
@MainActor
public final class DefaultDeviceApplication: ObservableObject {
    public static let scheme = "devices"
    private static let deviceHubBundleID = "com.apple.dt.Devices"

    @Published public private(set) var handlerName: String?
    @Published public private(set) var isOurs = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var failure: String?

    public init() {
        refresh()
    }

    public func refresh() {
        guard let url = URL(string: "\(Self.scheme)://"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            handlerName = nil
            isOurs = false
            return
        }
        handlerName = FileManager.default.displayName(atPath: handler.path(percentEncoded: false))
        isOurs = Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// Device Hub is found by bundle identifier rather than by asking who handles the scheme,
    /// because once this app owns it that question answers with this app.
    public func handBackToDeviceHub() {
        guard let deviceHub = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.deviceHubBundleID
        ) else {
            failure = "Device Hub was not found on this Mac."
            return
        }
        setHandler(deviceHub)
    }

    public func takeOver() {
        setHandler(Bundle.main.bundleURL)
    }

    private func setHandler(_ application: URL) {
        isBusy = true
        failure = nil
        Task {
            do {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: application,
                    toOpenURLsWithScheme: Self.scheme
                )
            } catch {
                failure = error.localizedDescription
            }
            isBusy = false
            refresh()
        }
    }
}
