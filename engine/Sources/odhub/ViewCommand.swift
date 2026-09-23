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

    @Option(help: "Window sizing: fit, point-accurate, pixel-accurate or physical-size.")
    var scale: String?

    @Flag(name: .long, inversion: .prefixedNo, help: "Draw the device bezel, its rounded corners and any cutout.")
    var bezel = true

    @Flag(help: "Keep the device windows above other applications.")
    var keepOnTop = false

    @Flag(help: "Forget the remembered window position for each device given.")
    var resetWindowPosition = false

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
        let candidates = [Brand.bundledViewerExecutableName, Brand.viewerExecutableName]
            .map { ExecutableLocator.siblingURL(of: running, named: $0) }
        guard let viewer = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false))
        }) else {
            throw ViewLaunchError.viewerMissing(
                path: candidates[0].deletingLastPathComponent().path(percentEncoded: false)
            )
        }

        var arguments = udids
        if boot { arguments.append("--boot") }
        if fps { arguments.append("--fps") }
        if let scale { arguments.append(contentsOf: ["--scale", scale]) }
        if !bezel { arguments.append("--no-bezel") }
        if keepOnTop { arguments.append("--keep-on-top") }
        if resetWindowPosition { arguments.append("--reset-window-position") }

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
            "The viewer was not found in \(path)."
        }
    }
}
