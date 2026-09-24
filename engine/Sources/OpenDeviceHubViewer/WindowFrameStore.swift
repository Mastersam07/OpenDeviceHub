import CoreGraphics
import Foundation
import OpenDeviceHubEngine

enum WindowFrameCodec {
    static func encode(_ frame: CGRect) -> String {
        "\(frame.origin.x),\(frame.origin.y),\(frame.size.width),\(frame.size.height)"
    }

    static func decode(_ text: String) -> CGRect? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let numbers = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }
}

/// Where the viewer's remembered settings are kept. The seam exists so tests never touch the user's
/// preferences, which otherwise leave a plist behind for every run.
public protocol PreferenceStorage: Sendable {
    func text(forKey key: String) -> String?
    func setText(_ text: String, forKey key: String)
    func removeText(forKey key: String)
    /// Needed to count and clear remembered frames without being told which devices to look for. A
    /// device deleted since its window was placed still has a key, and only enumeration finds it.
    func keys(withPrefix prefix: String) -> [String]
}

/// `UserDefaults` is thread safe but not marked `Sendable`, hence the unchecked conformance.
public struct UserDefaultsPreferenceStorage: PreferenceStorage, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func text(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func setText(_ text: String, forKey key: String) {
        defaults.set(text, forKey: key)
    }

    public func removeText(forKey key: String) {
        defaults.removeObject(forKey: key)
    }

    public func keys(withPrefix prefix: String) -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
    }
}

/// Remembers where each device's window was, keyed by UDID, so reopening a device puts it back.
public struct WindowFrameStore: Sendable {
    private let storage: any PreferenceStorage
    private let prefix: String

    public init(
        storage: any PreferenceStorage = UserDefaultsPreferenceStorage(),
        prefix: String = "\(Brand.identifierPrefix).window."
    ) {
        self.storage = storage
        self.prefix = prefix
    }

    public func frame(for udid: String) -> CGRect? {
        storage.text(forKey: prefix + udid).flatMap(WindowFrameCodec.decode)
    }

    public func save(_ frame: CGRect, for udid: String) {
        storage.setText(WindowFrameCodec.encode(frame), forKey: prefix + udid)
    }

    public func forget(_ udid: String) {
        storage.removeText(forKey: prefix + udid)
    }

    /// How many windows would reopen where they were left.
    public var rememberedCount: Int {
        storage.keys(withPrefix: prefix).count
    }

    public func forgetAll() {
        for key in storage.keys(withPrefix: prefix) {
            storage.removeText(forKey: key)
        }
    }
}
