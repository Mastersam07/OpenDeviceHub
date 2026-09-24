import Foundation
import OpenDeviceHubEngine

/// Remembers the simulator that was shown last, so opening the app again brings back what you were
/// working on.
public struct RecentDeviceStore: Sendable {
    private let storage: any PreferenceStorage
    private let key: String

    public init(
        storage: any PreferenceStorage = UserDefaultsPreferenceStorage(),
        key: String = "\(Brand.identifierPrefix).recentDevice"
    ) {
        self.storage = storage
        self.key = key
    }

    public var udid: String? { storage.text(forKey: key) }

    public func remember(_ udid: String) { storage.setText(udid, forKey: key) }
}

/// Which simulators to show when the app is opened with no arguments, which is what a click on the
/// icon in the Dock or the Finder does.
public enum StartupDevices {
    public struct Plan: Equatable, Sendable {
        public let udids: [String]
        /// True when the plan names a simulator that is not running, so showing it means starting it.
        public let boot: Bool

        public init(udids: [String], boot: Bool) {
            self.udids = udids
            self.boot = boot
        }
    }

    public static func plan(
        devices: [DeviceInfo],
        remembered: String?,
        bootsMostRecent: Bool = true
    ) -> Plan {
        let booted = devices.filter { $0.state == .booted }.map(\.udid)
        if !booted.isEmpty {
            return Plan(udids: booted, boot: false)
        }
        // Whatever is already running is always shown. This only governs starting one that is not.
        guard bootsMostRecent else { return Plan(udids: [], boot: false) }

        let usable = devices.filter(\.isAvailable)
        if let remembered,
           let match = usable.first(where: { $0.udid.caseInsensitiveCompare(remembered) == .orderedSame }) {
            return Plan(udids: [match.udid], boot: true)
        }

        guard let first = ranked(usable).first else { return Plan(udids: [], boot: false) }
        return Plan(udids: [first.udid], boot: true)
    }

    /// Best first, where best means the newest plain iPhone on the newest runtime. That is the shape
    /// of the default the simulator this replaces opens on a machine with no history of its own.
    static func ranked(_ devices: [DeviceInfo]) -> [DeviceInfo] {
        devices.sorted(by: isBetter)
    }

    private static func isBetter(_ left: DeviceInfo, _ right: DeviceInfo) -> Bool {
        let runtime = left.runtimeName.compare(right.runtimeName, options: .numeric)
        if runtime != .orderedSame { return runtime == .orderedDescending }
        if isPhone(left) != isPhone(right) { return isPhone(left) }
        let leftModel = modelNumber(left.name)
        let rightModel = modelNumber(right.name)
        if leftModel != rightModel { return (leftModel ?? -1) > (rightModel ?? -1) }
        // Shorter wins, so the plain iPhone 17 comes before the Pro and before a device someone
        // named themselves.
        if left.name.count != right.name.count { return left.name.count < right.name.count }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }

    private static func isPhone(_ device: DeviceInfo) -> Bool {
        device.deviceTypeIdentifier.localizedCaseInsensitiveContains("iPhone")
    }

    private static func modelNumber(_ name: String) -> Int? {
        name.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
    }
}
