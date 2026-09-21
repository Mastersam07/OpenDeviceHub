import Foundation

public struct SimctlService: Sendable {
    public init() {}

    static func listDevicesArguments() -> [String] {
        ["simctl", "list", "devices", "-j"]
    }

    static func listRuntimesArguments() -> [String] {
        ["simctl", "list", "runtimes", "-j"]
    }

    public func listRuntimes() throws -> [SimctlRuntime] {
        try SimctlModels.parseRuntimes(run(Self.listRuntimesArguments()))
    }

    public func listDevices() throws -> [DeviceInfo] {
        let byRuntime = try SimctlModels.parseDevices(run(Self.listDevicesArguments()))
        let names = Dictionary(
            (try? listRuntimes())?.map { ($0.identifier, $0.name) } ?? [],
            uniquingKeysWith: { first, _ in first }
        )

        return byRuntime.flatMap { identifier, devices in
            devices.map { device in
                DeviceInfo(
                    udid: device.udid,
                    name: device.name,
                    deviceTypeIdentifier: device.deviceTypeIdentifier,
                    runtimeIdentifier: identifier,
                    runtimeName: SimctlModels.runtimeName(forIdentifier: identifier, runtimes: names),
                    state: DeviceState.from(stateString: device.state),
                    isAvailable: device.isAvailable
                )
            }
        }
    }

    private func run(_ arguments: [String]) throws -> Data {
        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments)
        guard result.status == 0 else {
            throw EngineError.simctl(
                args: Array(arguments.dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
        return Data(result.standardOutput.utf8)
    }
}
