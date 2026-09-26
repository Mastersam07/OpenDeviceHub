import Foundation

/// What a device type's own profile says about its built in screens.
///
/// The IO ports say how big each panel is and nothing else. Everything else a foldable needs, which
/// screen a touch should go to and which way round the panel is built, is in the device type's
/// capabilities file next to the runtime.
public enum DeviceTypeProfile {
    public struct Display: Sendable, Hashable {
        /// What a touch is addressed to. Zero means the device's default screen.
        public let screenID: Int
        public let width: Int
        public let height: Int
        /// How far the panel is turned in its own housing. The unfolded panel of a foldable is built
        /// sideways, so its native rotation is 270 and its picture is landscape.
        public let nativeRotation: Int
        public let chromeIdentifier: String?
    }

    private static let root = "/Library/Developer/CoreSimulator/Profiles/DeviceTypes"

    /// Reading 130 bundles to find one is not worth doing twice.
    private static let bundlesByIdentifier: [String: URL] = {
        let directory = URL(fileURLWithPath: root)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        var found: [String: URL] = [:]
        for bundle in contents where bundle.pathExtension == "simdevicetype" {
            let info = bundle.appending(path: "Contents").appending(path: "Info.plist")
            guard let data = try? Data(contentsOf: info),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: data, options: [], format: nil
                  ) as? [String: Any],
                  let identifier = plist["CFBundleIdentifier"] as? String else { continue }
            found[identifier] = bundle
        }
        return found
    }()

    /// The built in screens the device type declares, in the order the profile lists them.
    public static func displays(forDeviceType identifier: String) -> [Display] {
        guard let bundle = bundlesByIdentifier[identifier] else { return [] }
        let file = bundle
            .appending(path: "Contents")
            .appending(path: "Resources")
            .appending(path: "capabilities.plist")
        guard let data = try? Data(contentsOf: file),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any] else { return [] }

        let capabilities = plist["capabilities"] as? [String: Any] ?? plist
        let displays = capabilities["displays"] as? [[String: Any]] ?? []
        return displays
            .filter { ($0["displayType"] as? String) == "integrated" }
            .compactMap { entry in
                guard let width = (entry["width"] as? NSNumber)?.intValue,
                      let height = (entry["height"] as? NSNumber)?.intValue else { return nil }
                return Display(
                    screenID: (entry["screenID"] as? NSNumber)?.intValue ?? 0,
                    width: width,
                    height: height,
                    nativeRotation: (entry["nativeRotation"] as? NSNumber)?.intValue ?? 0,
                    chromeIdentifier: entry["chromeIdentifier"] as? String
                )
            }
    }

    /// Matched on size, because that is the only thing an IO port and a profile entry both state.
    public static func display(
        forDeviceType identifier: String,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> Display? {
        displays(forDeviceType: identifier).first {
            $0.width == pixelWidth && $0.height == pixelHeight
        }
    }
}
