import AppKit
import ArgumentParser
import OpenDeviceHubEngine
import OpenDeviceHubViewer

/// A separate executable so that AppKit owns the process's main thread from launch. Running a
/// window from inside the command line tool meant `NSApplication.run()` executed as a main actor
/// job, which starved every other main actor task.
@main
struct ODHubViewer: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: Brand.viewerExecutableName,
        abstract: "Show one or more simulator screens in windows.",
        version: Brand.version
    )

    @Argument(help: "The UDIDs of the simulators to show.")
    var udids: [String]

    @Flag(help: "Boot a simulator first if it is not already booted.")
    var boot = false

    @Flag(help: "Print the delivered frame rate once a second.")
    var fps = false

    @Option(help: "Window sizing: fit, point-accurate, pixel-accurate or physical-size.")
    var scale: ScaleMode = .pointAccurate

    func validate() throws {
        guard !udids.isEmpty else {
            throw ValidationError("Pass at least one simulator UDID.")
        }
        guard Set(udids.map { $0.lowercased() }).count == udids.count else {
            throw ValidationError("The same UDID was passed more than once.")
        }
    }

    func run() throws {
        setvbuf(stdout, nil, _IONBF, 0)

        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        let devices = try adapter.devices()

        // Valid because a synchronous `run()` executes on the process's main thread.
        try MainActor.assumeIsolated {
            let application = NSApplication.shared
            application.setActivationPolicy(.regular)

            let manager = DeviceWindowManager()
            var failures: [String] = []

            for udid in udids {
                do {
                    try open(udid: udid, from: devices, adapter: adapter, manager: manager)
                } catch {
                    failures.append("\(udid): \(error.localizedDescription)")
                }
            }

            guard manager.openCount > 0 else {
                throw ViewerStartupError.nothingOpened(reasons: failures)
            }
            for failure in failures {
                print("Skipped \(failure)")
            }

            application.activate(ignoringOtherApps: true)
            let delegate = ViewerAppDelegate { manager.closeAll() }
            // NSApplication holds its delegate weakly, and nothing else refers to these objects
            // once the run loop starts, so without this ARC releases them and the display sessions
            // die with them: the windows stay up and never draw again.
            application.delegate = delegate
            withExtendedLifetime((manager, delegate)) {
                application.run()
            }
        }
    }

    @MainActor
    private func open(
        udid: String,
        from devices: [DeviceInfo],
        adapter: any SimulatorAdapter,
        manager: DeviceWindowManager
    ) throws {
        guard var device = devices.first(where: {
            $0.udid.caseInsensitiveCompare(udid) == .orderedSame
        }) else {
            throw EngineError.deviceNotFound(udid: udid)
        }

        if device.state != .booted {
            guard boot else { throw EngineError.deviceNotBooted(udid: device.udid) }
            let simctl = SimctlService()
            print("Booting \(device.name)...")
            try simctl.boot(udid: device.udid)
            try simctl.waitForBoot(udid: device.udid)
            device = try adapter.devices().first { $0.udid == device.udid } ?? device
        }

        let session = try adapter.openDisplay(device.udid)
        let input: (any InputSession)?
        do {
            input = try adapter.openInput(device.udid)
        } catch {
            input = nil
            print("\(device.name): clicking will not send taps, \(error.localizedDescription)")
        }

        let controller = try manager.open(
            device: device,
            session: session,
            input: input,
            scaleMode: scale,
            showFPS: fps
        )
        if case .largerThanScreen(let size) = controller.applyScaleMode(scale) {
            print("\(device.name): \(scale.displayName) needs \(Int(size.width))x\(Int(size.height)) points, which is larger than this display.")
        }
        let density = session.pixelsPerInch.map { " \(Int($0)) ppi" } ?? ""
        print("\(device.name)  \(Int(session.pixelSize.width))x\(Int(session.pixelSize.height)) at \(session.pointScale)x\(density)  [\(scale.displayName)]")
    }
}

enum ViewerStartupError: Error, LocalizedError {
    case nothingOpened(reasons: [String])

    var errorDescription: String? {
        switch self {
        case .nothingOpened(let reasons):
            "No device window could be opened.\n" + reasons.map { "  \($0)" }.joined(separator: "\n")
        }
    }
}

private final class ViewerAppDelegate: NSObject, NSApplicationDelegate {
    private let onTerminate: () -> Void

    init(onTerminate: @escaping () -> Void) {
        self.onTerminate = onTerminate
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate()
    }
}
