import Foundation

/// What a device type's capabilities file says about its screens; IO ports only give their size.
public enum DeviceTypeProfile {
    public struct Display: Sendable, Hashable {
        /// What a touch is addressed to. Zero means the device's default screen.
        public let screenID: Int
        public let width: Int
        public let height: Int
        /// How far the panel is turned in its housing; a foldable's unfolded panel reports 270.
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

    /// Nothing in a device type's bundle records a camera control, so this is Apple's list of the
    /// models that have one.
    static let cameraControlModels: Set<String> = [
        "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4",
        "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4",
        "iPhone19,2", "iPhone19,3", "iPhone19,4",
    ]

    public static func hasCameraControl(deviceType identifier: String) -> Bool {
        guard let model = modelIdentifier(forDeviceType: identifier) else { return false }
        return cameraControlModels.contains(model)
    }

    public static func modelIdentifier(forDeviceType identifier: String) -> String? {
        guard let bundle = bundlesByIdentifier[identifier] else { return nil }
        let file = bundle
            .appending(path: "Contents")
            .appending(path: "Resources")
            .appending(path: "profile.plist")
        guard let data = try? Data(contentsOf: file),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any] else { return nil }
        return plist["modelIdentifier"] as? String
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
