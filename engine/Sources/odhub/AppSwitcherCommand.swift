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

        let path = HomeGesture.appSwitcherPath()
        try await session.touch(TouchEvent(phase: .began, points: [path[0]], edge: .bottom))
        for point in path.dropFirst() {
            try await Task.sleep(for: .milliseconds(stepMilliseconds))
            try await session.touch(TouchEvent(phase: .moved, points: [point], edge: .bottom))
        }

        let interval = 40
        let settle = HomeGesture.settlePath(
            around: path[path.count - 1],
            steps: max(1, settleMilliseconds / interval)
        )
        for point in settle {
            try await Task.sleep(for: .milliseconds(interval))
            try await session.touch(TouchEvent(phase: .moved, points: [point], edge: .bottom))
        }

        try await session.touch(TouchEvent(phase: .ended, points: [settle[settle.count - 1]], edge: .bottom))
        print("opened the app switcher")
    }
}
