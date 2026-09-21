import ArgumentParser
import OpenDeviceHubEngine

@main
struct ODHub: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: Brand.commandName,
        abstract: "Inspect, view and drive iOS simulators from the active Xcode.",
        version: Brand.version,
        subcommands: [Doctor.self, List.self]
    )
}
