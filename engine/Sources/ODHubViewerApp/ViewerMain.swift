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
        abstract: "Show a simulator's screen in a window.",
        version: Brand.version
    )

    @Argument(help: "The UDID of the simulator to show.")
    var udid: String

    @Flag(help: "Boot the simulator first if it is not already booted.")
    var boot = false

    @Flag(help: "Print the delivered frame rate once a second.")
    var fps = false

    func run() throws {
        setvbuf(stdout, nil, _IONBF, 0)

        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
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
        }

        let session = try adapter.openDisplay(device.udid)
        let input: (any InputSession)?
        do {
            input = try adapter.openInput(device.udid)
        } catch {
            input = nil
            print("Clicking will not send taps: \(error.localizedDescription)")
        }
        print("\(device.name)  \(Int(session.pixelSize.width))x\(Int(session.pixelSize.height)) at \(session.pointScale)x")

        // Valid because a synchronous `run()` executes on the process's main thread.
        try MainActor.assumeIsolated {
            try present(device: device, session: session, input: input)
        }
    }

    @MainActor
    private func present(
        device: DeviceInfo,
        session: any DisplaySession,
        input: (any InputSession)?
    ) throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)

        let controller = try DeviceWindowController(
            title: "\(device.name) (\(device.runtimeName))",
            session: session,
            input: input,
            reportFPS: fps
        )
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)

        let delegate = ViewerAppDelegate { controller.stop() }
        // NSApplication holds its delegate weakly, and nothing else refers to either object once
        // the run loop starts, so without this ARC releases them and the display session dies with
        // them: the window stays up and never draws again.
        application.delegate = delegate
        withExtendedLifetime((controller, delegate)) {
            application.run()
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
