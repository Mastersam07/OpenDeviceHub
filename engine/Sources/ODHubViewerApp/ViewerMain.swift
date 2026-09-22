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

    @Flag(name: .long, inversion: .prefixedNo, help: "Draw the device bezel, its rounded corners and any cutout.")
    var bezel = true

    @Flag(help: "Keep the device windows above other applications.")
    var keepOnTop = false

    @Flag(help: "Forget the remembered window position for each device given.")
    var resetWindowPosition = false

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

            var slowAnimations = false
            let store = WindowFrameStore()
            if resetWindowPosition {
                udids.forEach(store.forget)
            }
            let manager = DeviceWindowManager(frameStore: store)
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

            let menuTarget = ViewerMenu.install(into: application, actions: ViewerMenu.Actions(
                setScaleMode: { manager.applyScaleMode($0) },
                toggleBezel: { manager.toggleBezel() },
                toggleKeepOnTop: { manager.toggleKeepOnTop() },
                pasteToDevice: {
                    guard let text = NSPasteboard.general.string(forType: .string) else { return }
                    let simctl = SimctlService()
                    for udid in manager.openUDIDs {
                        try? simctl.pasteboardCopy(text, udid: udid)
                    }
                },
                setAppearance: { appearance in
                    let simctl = SimctlService()
                    for udid in manager.openUDIDs {
                        try? simctl.setAppearance(appearance, udid: udid)
                    }
                },
                saveScreenshot: {
                    let directory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                        ?? URL(fileURLWithPath: NSTemporaryDirectory())
                    for url in manager.saveScreenshots(into: directory) {
                        print("saved \(url.path(percentEncoded: false))")
                    }
                },
                copyScreenshot: {
                    print(manager.copyScreenshotToClipboard() ? "screenshot copied" : "nothing to copy")
                },
                toggleRecording: {
                    let directory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                        ?? URL(fileURLWithPath: NSTemporaryDirectory())
                    let finished = manager.toggleRecording(into: directory)
                    if finished.isEmpty {
                        print("recording started")
                    } else {
                        for url in finished { print("recorded \(url.path(percentEncoded: false))") }
                        // Showing the file is the closest thing to dragging it out of the window,
                        // which needs a drag source and is not built yet.
                        NSWorkspace.shared.activateFileViewerSelecting(finished)
                    }
                },
                simulateMemoryWarning: {
                    for udid in manager.openUDIDs {
                        do {
                            try adapter.simulateMemoryWarning(udid)
                            print("sent a memory warning to \(udid)")
                        } catch {
                            print("memory warning failed: \(error.localizedDescription)")
                        }
                    }
                },
                openSystemLog: {
                    for udid in manager.openUDIDs {
                        NSWorkspace.shared.open(SimctlService.systemLogDirectory(udid: udid))
                    }
                },
                openAppData: {
                    for udid in manager.openUDIDs {
                        NSWorkspace.shared.open(SimctlService.deviceDataDirectory(udid: udid))
                    }
                },
                shake: {
                    let simctl = SimctlService()
                    for udid in manager.openUDIDs {
                        do { try simctl.shake(udid: udid) } catch {
                            print("shake failed: \(error.localizedDescription)")
                        }
                    }
                },
                toggleSlowAnimations: {
                    slowAnimations.toggle()
                    let simctl = SimctlService()
                    for udid in manager.openUDIDs {
                        try? simctl.setSlowAnimations(slowAnimations, udid: udid)
                    }
                    print("slow animations \(slowAnimations ? "on" : "off")")
                },
                toggleLatencyOverlay: { manager.toggleLatencyOverlay() },
                pressButton: { button in
                    for udid in manager.openUDIDs {
                        Task {
                            do {
                                let session = try adapter.openInput(udid)
                                defer { session.close() }
                                try await session.button(button, phase: .down)
                                try await Task.sleep(for: .milliseconds(15))
                                try await session.button(button, phase: .up)
                            } catch {
                                print("\(button) failed: \(error.localizedDescription)")
                            }
                        }
                    }
                },
                rotate: { left in
                    for udid in manager.openUDIDs {
                        guard let controller = manager.controller(for: udid) else { continue }
                        let next = left
                            ? controller.currentOrientation.rotatedLeft
                            : controller.currentOrientation.rotatedRight
                        do {
                            try adapter.setOrientation(next, udid: udid)
                            controller.setOrientation(next)
                        } catch {
                            print("rotate failed: \(error.localizedDescription)")
                        }
                    }
                }
            ), capabilities: adapter.capabilities)

            installToolbars(manager: manager, adapter: adapter)

            do {
                let notifier = try adapter.watchDeviceStates()
                manager.follow(
                    notifier,
                    attach: { udid in
                        let session = try adapter.openDisplay(udid)
                        session.setBezelEnabled(bezel)
                        return DeviceAttachment(
                            session: session,
                            input: try? adapter.openInput(udid)
                        )
                    },
                    boot: { udid in try SimctlService().boot(udid: udid) },
                    report: { print($0) }
                )
            } catch {
                print("device state changes will not be followed: \(error.localizedDescription)")
            }

            application.activate(ignoringOtherApps: true)
            let delegate = ViewerAppDelegate { manager.closeAll() }
            // NSApplication holds its delegate weakly, and nothing else refers to these objects
            // once the run loop starts, so without this ARC releases them and the display sessions
            // die with them: the windows stay up and never draw again.
            application.delegate = delegate
            withExtendedLifetime((manager, delegate, menuTarget)) {
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
        session.setBezelEnabled(bezel)
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
            bezelEnabled: bezel,
            keepOnTop: keepOnTop,
            showFPS: fps
        )
        if case .largerThanScreen(let size) = controller.applyScaleMode(scale) {
            print("\(device.name): \(scale.displayName) needs \(Int(size.width))x\(Int(size.height)) points, which is larger than this display.")
        }
        let shape = session.supportsBezel ? (bezel ? "  [bezel]" : "  [no bezel]") : "  [bezel unavailable]"
        let density = session.pixelsPerInch.map { " \(Int($0)) ppi" } ?? ""
        print("\(device.name)  \(Int(session.pixelSize.width))x\(Int(session.pixelSize.height)) at \(session.pointScale)x\(density)  [\(scale.displayName)]\(shape)")
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

/// The buttons above each device. Unlike the menu bar these act on one device, the one whose
/// window they sit on.
@MainActor
private func installToolbars(manager: DeviceWindowManager, adapter: any SimulatorAdapter) {
    for udid in manager.openUDIDs {
        guard let controller = manager.controller(for: udid) else { continue }
        controller.setToolbarActions(DeviceToolbarActions(
            goHome: { [weak controller] in
                guard let controller else { return }
                Task {
                    do {
                        let session = try adapter.openInput(udid)
                        defer { session.close() }
                        if controller.hasHomeButton {
                            try await session.button(.home, phase: .down)
                            try await Task.sleep(for: .milliseconds(15))
                            try await session.button(.home, phase: .up)
                        } else {
                            // A Face ID device has no Home button, so it goes home the way a hand
                            // would, by swiping up from the bottom edge.
                            try await swipeHome(session)
                        }
                    } catch {
                        print("home failed: \(error.localizedDescription)")
                    }
                }
            },
            saveScreenshot: {
                for url in manager.saveScreenshots(into: recordingDirectory(), only: udid) {
                    print("saved \(url.path(percentEncoded: false))")
                }
            },
            stopRecording: {
                for url in manager.toggleRecording(into: recordingDirectory()) {
                    print("recorded \(url.path(percentEncoded: false))")
                }
            },
            rotate: { [weak controller] toLeft in
                guard let controller else { return }
                let next = toLeft
                    ? controller.currentOrientation.rotatedLeft
                    : controller.currentOrientation.rotatedRight
                do {
                    try adapter.setOrientation(next, udid: udid)
                    controller.setOrientation(next)
                } catch {
                    print("rotate failed: \(error.localizedDescription)")
                }
            }
        ))
    }
}

private func swipeHome(_ session: any InputSession) async throws {
    let path = HomeGesture.swipePath()
    try await session.touch(TouchEvent(phase: .began, points: [path[0]], edge: .bottom))
    for point in path.dropFirst() {
        try await Task.sleep(for: .milliseconds(10))
        try await session.touch(TouchEvent(phase: .moved, points: [point], edge: .bottom))
    }
    try await session.touch(
        TouchEvent(phase: .ended, points: [path[path.count - 1]], edge: .bottom)
    )
}

/// Recordings and screenshots land on the Desktop, falling back to a temporary folder on a machine
/// that has none.
private func recordingDirectory() -> URL {
    FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory())
}
