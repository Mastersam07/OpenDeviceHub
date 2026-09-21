import ArgumentParser
import Foundation
import OpenDeviceHubEngine

struct HomeSwipe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "home-swipe",
        abstract: "Swipe up from the bottom edge to go home, for devices without a Home button."
    )

    @Argument(help: "The UDID of the simulator.")
    var udid: String

    @Option(help: "Milliseconds between each point of the swipe.")
    var stepMilliseconds: Int = 10

    func run() async throws {
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        let session = try adapter.openInput(udid)
        defer { session.close() }

        let path = HomeGesture.swipePath()
        try await session.touch(TouchEvent(phase: .began, points: [path[0]], edge: .bottom))
        for point in path.dropFirst() {
            try await Task.sleep(for: .milliseconds(stepMilliseconds))
            try await session.touch(TouchEvent(phase: .moved, points: [point], edge: .bottom))
        }
        try await session.touch(TouchEvent(phase: .ended, points: [path[path.count - 1]], edge: .bottom))
        print("swiped up from the bottom edge")
    }
}
