import ArgumentParser
import CoreGraphics
import Foundation
import OpenDeviceHubEngine

struct Swipe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swipe",
        abstract: "Drag one finger across a booted simulator between normalized coordinates."
    )

    @Argument(help: "The UDID of the simulator to swipe on.")
    var udid: String

    @Option(help: "Where the drag starts, horizontally, 0 to 1.")
    var fromX: Double

    @Option(help: "Where the drag starts, vertically, 0 to 1.")
    var fromY: Double

    @Option(help: "Where the drag ends, horizontally, 0 to 1.")
    var toX: Double

    @Option(help: "Where the drag ends, vertically, 0 to 1.")
    var toY: Double

    @Option(help: "How many intermediate points to send.")
    var steps: Int = 16

    @Option(help: "Milliseconds between each point.")
    var stepMilliseconds: Int = 12

    func validate() throws {
        for value in [fromX, fromY, toX, toY] where !(0...1).contains(value) {
            throw ValidationError("Coordinates are normalized and must be between 0 and 1.")
        }
        guard steps >= 1 else { throw ValidationError("--steps must be at least 1.") }
        guard stepMilliseconds >= 0 else { throw ValidationError("--step-milliseconds cannot be negative.") }
    }

    func run() async throws {
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        let session = try adapter.openInput(udid)
        defer { session.close() }

        let path = TouchPath.points(
            from: CGPoint(x: fromX, y: fromY),
            to: CGPoint(x: toX, y: toY),
            steps: steps
        )
        try await session.touch(TouchEvent(phase: .began, points: [path[0]]))
        for point in path.dropFirst() {
            try await Task.sleep(for: .milliseconds(stepMilliseconds))
            try await session.touch(TouchEvent(phase: .moved, points: [point]))
        }
        try await session.touch(TouchEvent(phase: .ended, points: [path[path.count - 1]]))
        print("swiped \(fromX),\(fromY) to \(toX),\(toY) in \(path.count) points")
    }
}
