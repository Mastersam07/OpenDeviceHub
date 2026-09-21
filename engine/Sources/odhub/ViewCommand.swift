import ArgumentParser
import Foundation
import OpenDeviceHubEngine

struct View: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "Open a window showing each simulator's screen."
    )

    @Argument(help: "The UDIDs of the simulators to show, one window each.")
    var udids: [String]

    @Flag(help: "Boot the simulator first if it is not already booted.")
    var boot = false

    @Flag(help: "Print the delivered frame rate once a second.")
    var fps = false

    @Flag(help: "Return as soon as the window opens instead of waiting for it to close.")
    var detach = false

    func validate() throws {
        guard !udids.isEmpty else {
            throw ValidationError("Pass at least one simulator UDID.")
        }
    }

    func run() async throws {
        guard let running = ExecutableLocator.runningExecutableURL() else {
            throw ViewLaunchError.couldNotLocateSelf
        }
        let viewer = ExecutableLocator.siblingURL(of: running, named: Brand.viewerExecutableName)
        guard FileManager.default.isExecutableFile(atPath: viewer.path(percentEncoded: false)) else {
            throw ViewLaunchError.viewerMissing(path: viewer.path(percentEncoded: false))
        }

        var arguments = udids
        if boot { arguments.append("--boot") }
        if fps { arguments.append("--fps") }

        let process = Process()
        process.executableURL = viewer
        process.arguments = arguments
        try process.run()

        guard !detach else {
            print("Viewer started (pid \(process.processIdentifier)).")
            return
        }

        // The viewer owns a window, so it runs until the window closes.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
        guard process.terminationStatus == 0 else {
            throw ExitCode(process.terminationStatus)
        }
    }
}

enum ViewLaunchError: Error, LocalizedError {
    case couldNotLocateSelf
    case viewerMissing(path: String)

    var errorDescription: String? {
        switch self {
        case .couldNotLocateSelf:
            "Could not work out where this executable lives, so the viewer could not be found."
        case .viewerMissing(let path):
            "\(Brand.viewerExecutableName) was not found at \(path)."
        }
    }
}
