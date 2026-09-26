import ArgumentParser
import CoreGraphics
import Foundation
import OpenDeviceHubEngine

struct AppSwitcher: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app-switcher",
        abstract: "Swipe up from the bottom edge and settle, which opens the recent apps switcher."
    )

    @Argument(help: "The UDID of the simulator.")
    var udid: String

    @Option(help: "Milliseconds between each point of the swipe.")
    var stepMilliseconds: Int = 10

    /// The guest reads a contact that is still moving at the lift as a flick, which takes it home
    /// instead, so the settle is what separates the two gestures.
    @Option(help: "Milliseconds to settle at the top of the swipe before lifting.")
    var settleMilliseconds: Int = 600

    func validate() throws {
        guard stepMilliseconds >= 0 else {
            throw ValidationError("--step-milliseconds cannot be negative.")
        }
        guard settleMilliseconds > 0 else {
            throw ValidationError("--settle-milliseconds must be positive, or this goes home.")
        }
    }

    func run() async throws {
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        let session = try adapter.openInput(udid)
        defer { session.close() }

        try await SystemGesture.appSwitcher(on: session, stepMilliseconds: stepMilliseconds)
        print("opened the app switcher")
    }
}
