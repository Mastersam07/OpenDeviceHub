import Foundation

/// A device type a simulator can be created as.
public struct SimctlDeviceType: Sendable, Hashable, Codable {
    public let identifier: String
    public let name: String

    public init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }
}

/// What a runtime can run. `simctl` reports this per runtime, and it matters: a newly released
/// runtime can support a single device type while an older one supports sixty.
public struct SimctlRuntimeSupport: Sendable, Hashable {
    public let runtime: SimctlRuntime
    public let deviceTypeIdentifiers: Set<String>

    public init(runtime: SimctlRuntime, deviceTypeIdentifiers: Set<String>) {
        self.runtime = runtime
        self.deviceTypeIdentifiers = deviceTypeIdentifiers
    }
}

/// Which device types and runtimes go together, and what to call a new simulator.
///
/// Pure, because the pairing is the part that is easy to get wrong and impossible to notice: an
/// unsupported pair is refused by `simctl` with a message about the runtime, long after the person
/// chose the device.
public enum SimulatorCreation {
    /// iOS only. The other platforms are out of scope for this app, and offering a watchOS device
    /// that it cannot then show would be a promise it does not keep.
    public static func isSupported(_ type: SimctlDeviceType) -> Bool {
        type.identifier.contains(".iPhone-") || type.identifier.contains(".iPad")
    }

    public static func runtimes(
        for type: SimctlDeviceType,
        in support: [SimctlRuntimeSupport]
    ) -> [SimctlRuntime] {
        support
            .filter { $0.runtime.isAvailable && $0.deviceTypeIdentifiers.contains(type.identifier) }
            .map(\.runtime)
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    public static func deviceTypes(
        in support: [SimctlRuntimeSupport],
        from types: [SimctlDeviceType]
    ) -> [SimctlDeviceType] {
        let runnable = support
            .filter(\.runtime.isAvailable)
            .reduce(into: Set<String>()) { $0.formUnion($1.deviceTypeIdentifiers) }
        return types
            .filter { isSupported($0) && runnable.contains($0.identifier) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The name a person would have typed, so the field is never empty. A name already taken gets a
    /// number, because `simctl` allows duplicates and two identical rows in the chooser help nobody.
    public static func suggestedName(
        for type: SimctlDeviceType,
        existing: [String]
    ) -> String {
        guard existing.contains(type.name) else { return type.name }
        for suffix in 2...99 where !existing.contains("\(type.name) \(suffix)") {
            return "\(type.name) \(suffix)"
        }
        return type.name
    }
}
