import ArgumentParser
import Foundation
import OpenDeviceHubEngine

struct Button: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "button",
        abstract: "Press a hardware button on a booted simulator."
    )

    enum Name: String, CaseIterable, ExpressibleByArgument {
        case home, lock, volumeUp = "volume-up", volumeDown = "volume-down", siri

        var hardware: HardwareButton {
            switch self {
            case .home: .home
            case .lock: .lock
            case .volumeUp: .volumeUp
            case .volumeDown: .volumeDown
            case .siri: .siri
            }
        }
    }

    @Argument(help: "The UDID of the simulator.")
    var udid: String

    @Argument(help: "Which button: home, lock, volume-up, volume-down or siri.")
    var button: Name

    @Option(help: "Milliseconds to hold the button down.")
    var holdMilliseconds: Int = 15

    func run() async throws {
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        let session = try adapter.openInput(udid)
        defer { session.close() }

        try await session.button(button.hardware, phase: .down)
        try await Task.sleep(for: .milliseconds(holdMilliseconds))
        try await session.button(button.hardware, phase: .up)
        print("pressed \(button.rawValue)")
    }
}

struct Rotate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rotate",
        abstract: "Turn a booted simulator to an orientation."
    )

    @Argument(help: "The UDID of the simulator.")
    var udid: String

    @Argument(help: "portrait, portraitUpsideDown, landscapeLeft or landscapeRight.")
    var orientation: String

    func run() throws {
        guard let value = DeviceOrientation(rawValue: orientation) else {
            throw ValidationError("Unknown orientation. Use one of: \(DeviceOrientation.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        try adapter.setOrientation(value, udid: udid)
        print("rotated to \(value.rawValue)")
    }
}
