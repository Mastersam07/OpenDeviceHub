import AppKit
import ArgumentParser
import Foundation
import OpenDeviceHubEngine
import OpenDeviceHubViewer

struct View: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "Open a window showing a booted simulator's screen."
    )

    @Argument(help: "The UDID of the simulator to show.")
    var udid: String

    @Flag(help: "Boot the simulator first if it is not already booted.")
    var boot = false

    @Flag(help: "Print the delivered frame rate once a second.")
    var fps = false

    func run() throws {
        // This command never returns, so a piped stdout would hold the frame rate in its buffer.
        setvbuf(stdout, nil, _IONBF, 0)
        let install = try XcodeLocator.locate()
        let adapter = try AdapterFactory.make(for: install)

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

        // The command runs on the process's main thread, which is where AppKit has to live.
        try MainActor.assumeIsolated {
            try present(device: device, session: session, input: input)
        }
    }

    /// AppKit has to own the main thread. `NSApplication.run()` never returns, so the task that
    /// awaits this never resumes and the process belongs to the window from here on.
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
