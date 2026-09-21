import ArgumentParser
import CoreGraphics
import Foundation
import OpenDeviceHubEngine

struct Pinch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pinch",
        abstract: "Pinch two contacts together or apart on a booted simulator."
    )

    @Argument(help: "The UDID of the simulator to pinch on.")
    var udid: String

    @Option(help: "Centre of the gesture, horizontally, 0 to 1.")
    var x: Double = 0.5

    @Option(help: "Centre of the gesture, vertically, 0 to 1.")
    var y: Double = 0.5

    @Option(help: "Distance between the contacts at the start, 0 to 1.")
    var from: Double = 0.2

    @Option(help: "Distance between the contacts at the end, 0 to 1.")
    var to: Double = 0.7

    @Option(help: "Angle of the line through the contacts, in degrees.")
    var angle: Double = 0

    @Option(help: "How many intermediate steps to send.")
    var steps: Int = 20

    func validate() throws {
        for value in [x, y, from, to] where !(0...1).contains(value) {
            throw ValidationError("Coordinates and spreads are normalized and must be between 0 and 1.")
        }
        guard steps >= 1 else { throw ValidationError("--steps must be at least 1.") }
    }

    func run() async throws {
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        let session = try adapter.openInput(udid)
        defer { session.close() }

        let centre = CGPoint(x: x, y: y)
        let radians = angle * .pi / 180
        let spreads = TouchPath.points(
            from: CGPoint(x: from, y: 0),
            to: CGPoint(x: to, y: 0),
            steps: steps
        ).map(\.x)

        var phase = TouchEvent.Phase.began
        for spread in spreads {
            let contacts = TwoFingerGesture.contacts(centre: centre, spread: spread, angle: radians)
            try await session.touch(TouchEvent(phase: phase, points: contacts))
            phase = .moved
            try await Task.sleep(for: .milliseconds(12))
        }
        let last = TwoFingerGesture.contacts(centre: centre, spread: to, angle: radians)
        try await session.touch(TouchEvent(phase: .ended, points: last))
        print("pinched \(from) to \(to) around \(x),\(y)")
    }
}
