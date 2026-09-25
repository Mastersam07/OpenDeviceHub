import Foundation

/// Finds the device body artwork the machine already has. Apple keeps it in two places: the
/// simulator's device type bundle names a chrome identifier, and DeviceKit holds the bundle that
/// identifier refers to.
public enum ChromeLocator {
    public static let deviceTypesDirectory = "/Library/Developer/CoreSimulator/Profiles/DeviceTypes"
    public static let chromeDirectory = "/Library/Developer/DeviceKit/Chrome"

    /// The `.simdevicetype` bundle whose `CFBundleIdentifier` matches, which is the same string
    /// `SimDeviceType.identifier` reports, so no private call is needed to find it.
    public static func deviceTypeBundle(
        identifier: String,
        in directory: String = deviceTypesDirectory,
        fileManager: FileManager = .default
    ) -> URL? {
        let root = URL(fileURLWithPath: directory)
        let entries = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.pathExtension == "simdevicetype" {
            let info = entry.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: info),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dictionary = plist as? [String: Any],
                  dictionary["CFBundleIdentifier"] as? String == identifier else { continue }
            return entry
        }
        return nil
    }

    /// The chrome identifier a device type asks for, such as
    /// `com.apple.dt.devicekit.chrome.phone11`.
    public static func chromeIdentifier(deviceTypeBundle: URL) -> String? {
        let profile = deviceTypeBundle.appendingPathComponent("Contents/Resources/profile.plist")
        guard let data = try? Data(contentsOf: profile),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return dictionary["chromeIdentifier"] as? String
    }

    /// The `.devicechrome` bundle declaring this identifier. Matched on the identifier inside each
    /// bundle rather than on its file name, since the two only happen to agree.
    public static func chromeBundle(
        identifier: String,
        in directory: String = chromeDirectory,
        fileManager: FileManager = .default
    ) -> URL? {
        let root = URL(fileURLWithPath: directory)
        let entries = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.pathExtension == "devicechrome" {
            let info = entry.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: info),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dictionary = plist as? [String: Any],
                  dictionary["CFBundleIdentifier"] as? String == identifier else { continue }
            return entry
        }
        return nil
    }

    /// The whole path, from a device type identifier to parsed chrome. Nil whenever any step is
    /// missing, so a device with no artwork simply keeps the masked screen.
    public static func chrome(forDeviceType identifier: String) -> DeviceChrome? {
        guard let deviceType = deviceTypeBundle(identifier: identifier),
              let chromeIdentifier = chromeIdentifier(deviceTypeBundle: deviceType) else { return nil }
        return chrome(identifier: chromeIdentifier)
    }

    /// Chrome named directly, which a foldable needs: its two panels declare different bodies, and
    /// the device type names only one of them.
    public static func chrome(identifier: String) -> DeviceChrome? {
        guard let bundle = chromeBundle(identifier: identifier) else { return nil }
        let description = bundle.appendingPathComponent("Contents/Resources/chrome.json")
        guard let data = try? Data(contentsOf: description) else { return nil }
        return try? DeviceChrome.parse(json: data, bundle: bundle)
    }
}
