import ArgumentParser
import Foundation
import OpenDeviceHubEngine

struct List: ParsableCommand {
    enum Source: String, CaseIterable, ExpressibleByArgument {
        case adapter
        case simctl
    }

    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the simulators the active Xcode knows about."
    )

    @Option(help: "Where to read devices from: the private adapter or simctl.")
    var source: Source = .adapter

    @Flag(help: "Include devices whose runtime is not installed.")
    var all = false

    func run() throws {
        let devices = try read()
            .filter { all || $0.isAvailable }
            .sorted { ($0.runtimeName, $0.name) < ($1.runtimeName, $1.name) }

        guard !devices.isEmpty else {
            print("No simulators.\(all ? "" : " Pass --all to include unavailable runtimes.")")
            return
        }

        let nameWidth = devices.map(\.name.count).max() ?? 0
        let runtimeWidth = devices.map(\.runtimeName.count).max() ?? 0
        let stateWidth = devices.map(\.state.rawValue.count).max() ?? 0

        for device in devices {
            let name = device.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            let runtime = device.runtimeName.padding(toLength: runtimeWidth, withPad: " ", startingAt: 0)
            let state = device.state.rawValue.padding(toLength: stateWidth, withPad: " ", startingAt: 0)
            let unavailable = device.isAvailable ? "" : "  (unavailable)"
            print("\(name)  \(runtime)  \(state)  \(device.udid)\(unavailable)")
        }
        print("")
        print("\(devices.count) device\(devices.count == 1 ? "" : "s") via \(source.rawValue)")
    }

    private func read() throws -> [DeviceInfo] {
        switch source {
        case .adapter:
            return try AdapterFactory.make(for: XcodeLocator.locate()).devices()
        case .simctl:
            return try SimctlService().listDevices()
        }
    }
}
