import Foundation
import OpenDeviceHubEngine

/// The handful of choices worth remembering between launches.
///
/// Stored through the same seam as the window frames, so tests never leave a plist behind. Each
/// default is the behaviour the app already had, except `shutdownOnWindowClose`, which deliberately
/// changed it to match the simulator this replaces.
public struct ViewerSettings: Sendable {
    private let storage: any PreferenceStorage
    private let prefix: String

    public init(
        storage: any PreferenceStorage = UserDefaultsPreferenceStorage(),
        prefix: String = "\(Brand.identifierPrefix).settings."
    ) {
        self.storage = storage
        self.prefix = prefix
    }

    /// Closing a window shuts the device down, which is what Simulator.app and the prior art both
    /// do. Turn it off to leave simulators running.
    public var shutsDownOnWindowClose: Bool {
        get { flag("shutdownOnWindowClose", default: true) }
        nonmutating set { setFlag("shutdownOnWindowClose", newValue) }
    }

    /// With nothing booted, opening the app starts the simulator you had last. Turn it off and a
    /// launch with nothing running opens no window.
    public var bootsMostRecentOnStart: Bool {
        get { flag("bootMostRecentOnStart", default: true) }
        nonmutating set { setFlag("bootMostRecentOnStart", newValue) }
    }

    /// Where screenshots and recordings are written. Empty means the Desktop, which is where they
    /// went before this was a choice.
    public var captureDirectory: URL? {
        get {
            guard let path = storage.text(forKey: prefix + "captureDirectory"), !path.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        nonmutating set {
            guard let newValue else {
                storage.removeText(forKey: prefix + "captureDirectory")
                return
            }
            // Without the trailing slash a directory URL carries, so what is read back is the same
            // string that was written and the stored value is the one a person would recognise.
            var path = newValue.standardizedFileURL.path(percentEncoded: false)
            while path.count > 1, path.hasSuffix("/") { path.removeLast() }
            storage.setText(path, forKey: prefix + "captureDirectory")
        }
    }

    private func flag(_ name: String, default fallback: Bool) -> Bool {
        switch storage.text(forKey: prefix + name) {
        case "true": true
        case "false": false
        default: fallback
        }
    }

    private func setFlag(_ name: String, _ value: Bool) {
        storage.setText(value ? "true" : "false", forKey: prefix + name)
    }
}
