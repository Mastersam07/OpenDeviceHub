import Foundation

public struct SimctlDevice: Sendable, Hashable, Codable {
    public let udid: String
    public let name: String
    public let deviceTypeIdentifier: String
    public let state: String
    public let isAvailable: Bool
    public let availabilityError: String?
}

public struct SimctlRuntime: Sendable, Hashable, Codable {
    public let identifier: String
    public let name: String
    public let version: String
    public let buildversion: String
    public let isAvailable: Bool
}

enum SimctlModels {
    struct DeviceList: Decodable {
        let devices: [String: [SimctlDevice]]
    }

    struct RuntimeList: Decodable {
        let runtimes: [SimctlRuntime]
    }

    static func parseDevices(_ data: Data) throws -> [String: [SimctlDevice]] {
        try JSONDecoder().decode(DeviceList.self, from: data).devices
    }

    static func parseRuntimes(_ data: Data) throws -> [SimctlRuntime] {
        try JSONDecoder().decode(RuntimeList.self, from: data).runtimes
    }

    /// `simctl list runtimes` only reports runtimes that are installed and available, yet
    /// `simctl list devices` still lists devices belonging to runtimes that are not. Those fall
    /// back to a readable form of the identifier.
    static func runtimeName(
        forIdentifier identifier: String,
        runtimes: [String: String]
    ) -> String {
        runtimes[identifier] ?? RuntimeIdentifier.readableName(for: identifier)
    }
}
