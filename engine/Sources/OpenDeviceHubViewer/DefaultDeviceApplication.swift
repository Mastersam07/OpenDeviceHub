import AppKit
import OpenDeviceHubEngine

/// Who handles `devices://` links, and changing it.
///
/// Device Hub owns the scheme out of the box, but it is not the only app that can claim it: any
/// simulator viewer may, and more than one may be installed. So taking it over remembers who held
/// it, and giving it back means giving it back to *them*, not to whoever this app assumes was there.
@MainActor
public final class DefaultDeviceApplication: ObservableObject {
    public static let scheme = "devices"
    static let deviceHubBundleID = "com.apple.dt.Devices"

    @Published public private(set) var handlerName: String?
    @Published public private(set) var isOurs = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var failure: String?
    /// What the button offers to hand back to: whoever held the scheme before, by name.
    @Published public private(set) var previousHandlerName: String?

    private let storage: any PreferenceStorage
    private let key: String

    public init(
        storage: any PreferenceStorage = UserDefaultsPreferenceStorage(),
        key: String = "\(Brand.identifierPrefix).previousLinkHandler"
    ) {
        self.storage = storage
        self.key = key
        refresh()
    }

    public func refresh() {
        guard let url = URL(string: "\(Self.scheme)://"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            handlerName = nil
            isOurs = false
            previousHandlerName = nil
            return
        }
        handlerName = Self.name(of: handler)
        isOurs = Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
        previousHandlerName = handBackTarget().map(Self.name(of:))
    }

    public func takeOver() {
        // Recorded before the change, and only when it is somebody else's, so taking over twice
        // cannot overwrite the memory with ourselves.
        if let current = currentHandler(),
           Bundle(url: current)?.bundleIdentifier != Bundle.main.bundleIdentifier,
           let identifier = Bundle(url: current)?.bundleIdentifier {
            storage.setText(identifier, forKey: key)
        }
        setHandler(Bundle.main.bundleURL)
    }

    /// Back to whoever had it, or to Device Hub when that app is gone or was never recorded. Device
    /// Hub is the floor rather than the assumption: it ships with Xcode, so it is the one handler
    /// that can be relied on to exist.
    public func handBack() {
        guard let target = handBackTarget() else {
            failure = "Device Hub was not found on this Mac."
            return
        }
        setHandler(target)
    }

    private func handBackTarget() -> URL? {
        let wanted = Self.handBackIdentifier(
            remembered: storage.text(forKey: key),
            ours: Bundle.main.bundleIdentifier
        )
        if let wanted, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: wanted) {
            return url
        }
        // The remembered app has been deleted since. Device Hub ships with Xcode, so it is the one
        // handler that can be relied on to still be there.
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.deviceHubBundleID)
    }

    /// Who the scheme should go back to. Separated from the lookup so the decision can be tested
    /// without a machine that happens to have the right apps installed.
    static func handBackIdentifier(remembered: String?, ours: String?) -> String? {
        guard let remembered, !remembered.isEmpty, remembered != ours else {
            return deviceHubBundleID
        }
        return remembered
    }

    private func currentHandler() -> URL? {
        URL(string: "\(Self.scheme)://").flatMap(NSWorkspace.shared.urlForApplication(toOpen:))
    }

    private static func name(of application: URL) -> String {
        FileManager.default.displayName(atPath: application.path(percentEncoded: false))
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
