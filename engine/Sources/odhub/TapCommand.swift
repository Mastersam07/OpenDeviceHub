import ArgumentParser
import CoreGraphics
import Foundation
import OpenDeviceHubEngine

struct Tap: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tap",
        abstract: "Send a single tap to a booted simulator at a normalized coordinate."
    )

    @Argument(help: "The UDID of the simulator to tap.")
    var udid: String

    @Option(help: "Horizontal position, 0 at the left edge and 1 at the right.")
    var x: Double

    @Option(help: "Vertical position, 0 at the top edge and 1 at the bottom.")
    var y: Double

    @Option(help: "Milliseconds to hold the contact down.")
    var holdMilliseconds: Int = 90

    func validate() throws {
        guard (0...1).contains(x), (0...1).contains(y) else {
            throw ValidationError("--x and --y are normalized and must be between 0 and 1.")
        }
        guard holdMilliseconds >= 0 else {
            throw ValidationError("--hold-milliseconds cannot be negative.")
        }
    }

    func run() async throws {
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        let session = try adapter.openInput(udid)
        defer { session.close() }

        let point = CGPoint(x: x, y: y)
        try await session.touch(TouchEvent(phase: .began, points: [point]))
        try await Task.sleep(for: .milliseconds(holdMilliseconds))
        try await session.touch(TouchEvent(phase: .ended, points: [point]))
        print("tapped \(x), \(y)")
    }
}
