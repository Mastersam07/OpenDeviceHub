import ArgumentParser
import Foundation
import OpenDeviceHubEngine

struct Type: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text on a booted simulator using its hardware keyboard."
    )

    @Argument(help: "The UDID of the simulator to type on.")
    var udid: String

    @Argument(help: "The text to type.")
    var text: String

    @Option(help: "Milliseconds between key presses.")
    var keyMilliseconds: Int = 25

    func run() async throws {
        guard let usages = KeyboardMap.usages(forTyping: text) else {
            throw ValidationError("That text contains a character with no unshifted key.")
        }
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        let session = try adapter.openInput(udid)
        defer { session.close() }

        for usage in usages {
            try await session.key(KeyEvent(phase: .down, usage: usage))
            try await Task.sleep(for: .milliseconds(keyMilliseconds))
            try await session.key(KeyEvent(phase: .up, usage: usage))
            try await Task.sleep(for: .milliseconds(keyMilliseconds))
        }
        print("typed \(usages.count) keys")
    }
}
