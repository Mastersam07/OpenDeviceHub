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

    /// Copies made on the Mac reach the device on their own, and a copy made in the device comes
    /// back when you switch away from the app. On by default, as in Simulator.app.
    public var syncsPasteboard: Bool {
        get { flag("syncsPasteboard", default: true) }
        nonmutating set { setFlag("syncsPasteboard", newValue) }
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

    /// What Previous fills the New Simulator panel with.
    public var lastCreatedSimulator: LastCreatedSimulator? {
        get {
            guard let stored = storage.text(forKey: prefix + "lastCreatedSimulator") else { return nil }
            return LastCreatedSimulator(stored: stored)
        }
        nonmutating set {
            guard let newValue else {
                storage.removeText(forKey: prefix + "lastCreatedSimulator")
                return
            }
            storage.setText(newValue.stored, forKey: prefix + "lastCreatedSimulator")
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


/// The last simulator created here, so the panel can offer it again.
///
/// Stored as one tab separated line rather than JSON, because the storage seam is strings and a
/// name cannot contain a tab.
public struct LastCreatedSimulator: Equatable, Sendable {
    public let name: String
    public let deviceType: String
    public let runtime: String

    public init(name: String, deviceType: String, runtime: String) {
        self.name = name
        self.deviceType = deviceType
        self.runtime = runtime
    }

    init?(stored: String) {
        let parts = stored.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts.allSatisfy(\.isEmpty) else { return nil }
        self.init(name: String(parts[0]), deviceType: String(parts[1]), runtime: String(parts[2]))
    }

    var stored: String { [name, deviceType, runtime].joined(separator: "\t") }
}
