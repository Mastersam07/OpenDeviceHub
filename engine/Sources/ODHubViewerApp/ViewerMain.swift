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

    /// Optional because the app is opened from the Dock and the Finder as often as from a terminal,
    /// and a click passes no arguments at all.
    @Argument(help: "The UDIDs of the simulators to show. Defaults to whatever is running.")
    var udids: [String] = []

    @Flag(help: "Boot a simulator first if it is not already booted.")
    var boot = false

    @Flag(help: "Print the delivered frame rate once a second.")
    var fps = false

    @Option(help: "Window sizing: fit, point-accurate, pixel-accurate or physical-size.")
    var scale: ScaleMode = .fit

    @Flag(name: .long, inversion: .prefixedNo, help: "Draw the device bezel, its rounded corners and any cutout.")
    var bezel = true

    @Flag(help: "Keep the device windows above other applications.")
    var keepOnTop = false

    @Flag(help: "Forget the remembered window position for each device given.")
    var resetWindowPosition = false

    func validate() throws {
        guard Set(udids.map { $0.lowercased() }).count == udids.count else {
            throw ValidationError("The same UDID was passed more than once.")
        }
    }

    func run() throws {
        setvbuf(stdout, nil, _IONBF, 0)

        // Anything that stops the app before its first window is the one failure a person cannot
        // see, because a click in the Dock has no terminal behind it. It gets a dialog instead.
        do {
            try start()
        } catch {
            guard MainActor.assumeIsolated({ StartupFailure.hasNoTerminal }) else { throw error }
            MainActor.assumeIsolated { StartupFailure.present(error) }
            throw ExitCode(1)
        }
    }

    private func start() throws {
        let install = try XcodeLocator.locate()
        let adapter = try AdapterFactory.make(for: install)
        MainActor.assumeIsolated { StartupFailure.reportUnverifiedXcode(install) }
        let devices = try adapter.devices()
        let recent = RecentDeviceStore()
        let launchedFromAnIcon = udids.isEmpty
        let settings = ViewerSettings()
        let plan = launchedFromAnIcon
            ? StartupDevices.plan(
                devices: devices,
                remembered: recent.udid,
                bootsMostRecent: settings.bootsMostRecentOnStart
            )
            : StartupDevices.Plan(udids: udids, boot: boot)

        // Valid because a synchronous `run()` executes on the process's main thread.
        try MainActor.assumeIsolated {
            let application = NSApplication.shared
            application.setActivationPolicy(.regular)

            let store = WindowFrameStore()
            if resetWindowPosition {
                plan.udids.forEach(store.forget)
            }
            let manager = DeviceWindowManager(frameStore: store)

            let pasteboard = PasteboardSyncController(
                isAutomatic: settings.syncsPasteboard,
                devices: { manager.openUDIDs },
                frontmost: { manager.frontmostUDID },
                open: { try adapter.openPasteboard($0) }
            )
            let foldables = FoldableController(
                open: { try adapter.openFoldableControl($0) },
                hingeStream: { try adapter.openHingeStream($0) },
                displayReport: { try await adapter.displayReport($0) }
            )
            foldables.report = { print($0) }
            foldables.onMove = { udid, event in
                guard let controller = manager.controller(for: udid) else { return }
                switch event {
                case .began(let target): controller.beginFold(to: target)
                case .angle(let angle): controller.showHingeAngle(angle)
                case .ended: controller.endFold()
                }
            }
            manager.onDeviceClosed = {
                pasteboard.forget($0)
                foldables.forget($0)
            }

            let previews = CapturePreviewPresenter(report: { print($0) })
            let present: @MainActor ([URL]) -> Void = { urls in
                for url in urls {
                    let destination = captureDirectory(for: url, settings: settings)
                    previews.show(
                        PendingCapture(temporary: url, destination: destination),
                        beside: NSApp.keyWindow ?? manager.openUDIDs.first.flatMap(manager.controller(for:))?.window
                    )
                }
            }

            var failures: [String] = []

            // The hinge provider overwrites an ordinary rotation, so a foldable turns through it.
            let turn: @MainActor (DeviceOrientation, String) -> Void = { orientation, udid in
                guard let controller = manager.controller(for: udid) else { return }
                do {
                    if controller.foldsAtHinge {
                        try foldables.setOrientation(orientation, for: udid)
                    } else {
                        try adapter.setOrientation(orientation, udid: udid)
                    }
                    controller.setOrientation(orientation)
                } catch {
                    print("rotate failed: \(error.localizedDescription)")
                }
            }

            // Opens unfolded unless told otherwise, which is where the device's own tooling starts.
            let followFold: @MainActor (String, DeviceWindowController, Double?) -> Void = { udid, controller, angle in
                let angle = angle ?? DeviceControlBar.FoldMode.fullyOpen.angle
                controller.showHingeAngle(angle)
                controller.onHingeAngle = { angle in foldables.setAngle(angle, for: udid) }
                controller.onFoldPreset = { angle in foldables.setAngle(angle, for: udid, eased: true) }
                foldables.setAngle(angle, for: udid)
                foldables.follow(
                    udid,
                    nudges: controller.screenChanges,
                    onPanel: { [weak controller] panel in
                        controller?.setActivePanel(screenID: panel.displayID)
                    },
                    onHinge: { [weak controller] degrees in
                        controller?.showHingeAngle(degrees)
                    }
                )
            }

            let show: @MainActor (String, Bool) throws -> Void = { udid, allowBoot in
                let current = try adapter.devices()
                try self.open(
                    udid: udid,
                    from: current,
                    adapter: adapter,
                    manager: manager,
                    allowBoot: allowBoot,
                    rotate: turn,
                    present: present
                )
                recent.remember(udid)
                pasteboard.adopt(udid)
                if let controller = manager.controller(for: udid), controller.foldsAtHinge {
                    followFold(udid, controller, foldables.angle(for: udid))
                }
            }

            // The hinge, its readings and the clipboard connection all belong to the boot that
            // ended, so they are opened again. The window keeps the fold it was showing.
            manager.onReattached = { udid in
                pasteboard.forget(udid)
                pasteboard.adopt(udid)
                guard let controller = manager.controller(for: udid), controller.foldsAtHinge else { return }
                let angle = foldables.angle(for: udid)
                foldables.forget(udid)
                followFold(udid, controller, angle)
            }

            for udid in plan.udids {
                do {
                    try show(udid, plan.boot)
                } catch {
                    failures.append("\(udid): \(error.localizedDescription)")
                }
            }

            guard manager.openCount > 0 || launchedFromAnIcon else {
                throw ViewerStartupError.nothingOpened(reasons: failures)
            }
            for failure in failures {
                print("Skipped \(failure)")
            }

            // Booting blocks for several seconds, so it runs off the main thread and the window
            // follows once the device is up.
            let bootThenShow: @MainActor (String) -> Void = { udid in
                Task {
                    let simctl = SimctlService()
                    do {
                        try await Task.detached {
                            try simctl.boot(udid: udid)
                            try simctl.waitForBoot(udid: udid)
                        }.value
                    } catch {
                        print("\(udid) could not be started: \(error.localizedDescription)")
                        return
                    }
                    guard !manager.isOpen(udid) else { return }
                    do { try show(udid, false) } catch {
                        print("\(udid) started but could not be shown: \(error.localizedDescription)")
                    }
                }
            }

            let chooser = DeviceChooser(
                devices: { (try? adapter.devices()) ?? [] },
                open: { udid in
                    if manager.isOpen(udid) {
                        manager.bringToFront(udid)
                        NSApp.activate(ignoringOtherApps: true)
                        return
                    }
                    bootThenShow(udid)
                }
            )

            let deviceLinks = DefaultDeviceApplication()
            let updates = UpdateController()
            // Every menu action lands on the device the user is looking at, as in Simulator.app.
            let front: @MainActor () -> (udid: String, controller: DeviceWindowController)? = {
                guard let udid = manager.frontmostUDID,
                      let controller = manager.controller(for: udid) else { return nil }
                return (udid, controller)
            }
            let menuTarget = ViewerMenu.install(into: application, actions: ViewerMenu.Actions(
                setScaleMode: { mode in
                    guard let target = front() else { return }
                    if case .largerThanScreen(let size) = target.controller.applyScaleMode(mode) {
                        print("\(target.controller.deviceTitle): \(mode.displayName) needs \(Int(size.width))x\(Int(size.height)) points, which is larger than this display.")
                    }
                },
                toggleBezel: {
                    guard let target = front() else { return }
                    target.controller.setBezelEnabled(!target.controller.isBezelEnabled)
                },
                toggleKeepOnTop: {
                    guard let target = front() else { return }
                    target.controller.setKeepOnTop(!target.controller.isKeptOnTop)
                },
                pasteToDevice: {
                    guard let target = front(),
                          let text = NSPasteboard.general.string(forType: .string) else { return }
                    try? SimctlService().pasteboardCopy(text, udid: target.udid)
                },
                toggleAppearance: {
                    guard let target = front() else { return }
                    let simctl = SimctlService()
                    let current = (try? simctl.appearance(udid: target.udid)) ?? nil
                    try? simctl.setAppearance(current == .dark ? .light : .dark, udid: target.udid)
                },
                saveScreenshot: {
                    guard let target = front() else { return }
                    if settings.savesScreenshotsToClipboard {
                        print(manager.copyScreenshotToClipboard(only: target.udid) ? "screenshot saved to clipboard" : "nothing to save")
                    } else {
                        present(manager.saveScreenshots(into: CaptureStaging.directory(), only: target.udid))
                    }
                },
                copyScreenshot: {
                    print(manager.copyScreenshotToClipboard() ? "screenshot copied" : "nothing to copy")
                },
                toggleRecording: {
                    let finished = manager.toggleRecording(into: CaptureStaging.directory(), only: front()?.udid)
                    if finished.isEmpty {
                        print("recording started")
                    } else {
                        present(finished)
                    }
                },
                simulateMemoryWarning: {
                    guard let target = front() else { return }
                    do {
                        try adapter.simulateMemoryWarning(target.udid)
                        print("sent a memory warning to \(target.udid)")
                    } catch {
                        print("memory warning failed: \(error.localizedDescription)")
                    }
                },
                openSystemLog: {
                    guard let target = front() else { return }
                    NSWorkspace.shared.open(SimctlService.systemLogDirectory(udid: target.udid))
                },
                openAppData: {
                    guard let target = front() else { return }
                    NSWorkspace.shared.open(SimctlService.deviceDataDirectory(udid: target.udid))
                },
                shake: {
                    guard let udid = manager.frontmostUDID else { return }
                    do { try SimctlService().shake(udid: udid) } catch {
                        print("shake failed: \(error.localizedDescription)")
                    }
                },
                toggleSlowAnimations: {
                    guard let target = front() else { return }
                    let wanted = !target.controller.slowAnimations
                    do {
                        try SimctlService().setSlowAnimations(wanted, udid: target.udid)
                        target.controller.slowAnimations = wanted
                        print("slow animations \(wanted ? "on" : "off")")
                    } catch {
                        print("slow animations failed: \(error.localizedDescription)")
                    }
                },
                toggleLatencyOverlay: {
                    guard let target = front() else { return }
                    target.controller.setLatencyOverlayVisible(!target.controller.isLatencyOverlayVisible)
                },
                pressButton: { button in
                    guard let udid = manager.frontmostUDID,
                          button != .cameraControl || manager.hasCameraControl(udid) else { return }
                    Task {
                        do {
                            guard let session = manager.controller(for: udid)?.inputSession
                            else { return }
                            try await session.button(button, phase: .down)
                            try await Task.sleep(for: .milliseconds(15))
                            try await session.button(button, phase: .up)
                        } catch {
                            print("\(button) failed: \(error.localizedDescription)")
                        }
                    }
                },
                hasCameraControl: {
                    manager.frontmostUDID.map { manager.hasCameraControl($0) } ?? false
                },
                rotate: { left in
                    guard let udid = manager.frontmostUDID,
                          let controller = manager.controller(for: udid) else { return }
                    let next = left
                        ? controller.currentOrientation.rotatedLeft
                        : controller.currentOrientation.rotatedRight
                    turn(next, udid)
                },
                restart: {
                    guard let udid = manager.frontmostUDID else { return }
                    runOnEveryDevice("restart", udid) { try SimctlService().restart(udid: $0) }
                },
                shutdown: {
                    guard let udid = manager.frontmostUDID else { return }
                    runOnEveryDevice("shutdown", udid) { try SimctlService().shutdown(udid: $0) }
                },
                erase: {
                    // Destructive and not undoable, so it asks, names the device, and Erase is not
                    // the default button.
                    guard let udid = manager.frontmostUDID,
                          let controller = manager.controller(for: udid) else { return }
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Erase \(controller.deviceTitle)?"
                    alert.informativeText = "Every app, setting and file on this simulator is deleted. This cannot be undone, and the device is left shut down."
                    alert.addButton(withTitle: "Cancel")
                    alert.addButton(withTitle: "Erase")
                    guard alert.runModal() == .alertSecondButtonReturn else { return }
                    runOnEveryDevice("erase", udid) { try SimctlService().erase(udid: $0) }
                },
                stepTextSize: { step in
                    guard let udid = manager.frontmostUDID else { return }
                    runOnEveryDevice("text size", udid) {
                        try SimctlService().stepContentSize(step, udid: $0)
                    }
                },
                toggleIncreaseContrast: {
                    guard let target = front() else { return }
                    let simctl = SimctlService()
                    let wanted = !simctl.increasesContrast(udid: target.udid)
                    target.controller.increasesContrast = wanted
                    runOnEveryDevice("increase contrast", target.udid) {
                        try simctl.setIncreaseContrast(wanted, udid: $0)
                    }
                },
                triggerICloudSync: {
                    guard let target = front() else { return }
                    runOnEveryDevice("iCloud sync", target.udid) {
                        try SimctlService().triggerICloudSync(udid: $0)
                    }
                },
                setLocation: { scenario in
                    guard let udid = manager.frontmostUDID else { return }
                    runOnEveryDevice("location", udid) { device in
                        if let scenario {
                            try SimctlService().runLocation(scenario, udid: device)
                        } else {
                            try SimctlService().clearLocation(udid: device)
                        }
                    }
                },
                setCustomLocation: {
                    guard let udid = manager.frontmostUDID,
                          let point = CustomLocationPrompt.ask() else { return }
                    runOnEveryDevice("location", udid) {
                        try SimctlService().setLocation(
                            latitude: point.latitude,
                            longitude: point.longitude,
                            udid: $0
                        )
                    }
                },
                locationFavorites: { settings.locationFavorites },
                setFavoriteLocation: { favorite in
                    guard let udid = manager.frontmostUDID else { return }
                    runOnEveryDevice("location", udid) {
                        try SimctlService().setLocation(
                            latitude: favorite.latitude,
                            longitude: favorite.longitude,
                            udid: $0
                        )
                    }
                },
                toggleKeyboardInput: { enabled in
                    front()?.controller.sendsKeyboardInput = enabled
                },
                toggleHardwareKeyboard: { enabled in
                    guard let target = front() else { return }
                    target.controller.hasHardwareKeyboard = enabled
                    runOnEveryDevice("hardware keyboard", target.udid) {
                        try adapter.setHardwareKeyboardEnabled(enabled, udid: $0)
                    }
                },
                matchKeyboardLanguage: { matching in
                    guard let target = front() else { return }
                    target.controller.matchesKeyboardLanguage = matching
                    // Off leaves the guest on whatever it had: there is no "stop matching" call, so
                    // turning it back on is what re-applies the Mac's language.
                    guard matching, let language = KeyboardLanguage.current() else { return }
                    runOnEveryDevice("keyboard language", target.udid) {
                        try adapter.setKeyboardLanguage(language, udid: $0)
                    }
                },
                toggleAutomaticPasteboardSync: { enabled in
                    settings.syncsPasteboard = enabled
                    pasteboard.setAutomatic(enabled)
                },
                getPasteboard: { pasteboard.get() },
                sendPasteboard: { pasteboard.send() },
                syncsPasteboard: { settings.syncsPasteboard },
                panels: {
                    guard let udid = manager.frontmostUDID else { return [] }
                    return (try? adapter.panels(udid)) ?? []
                },
                currentPanel: {
                    guard let udid = manager.frontmostUDID,
                          let panels = try? adapter.panels(udid) else { return nil }
                    if let active = foldables.activePanel(for: udid) {
                        return panels.first { $0.screenID == active.displayID }
                    }
                    return panels.first { $0.name == "Unfolded" } ?? panels.first
                },
                showPanel: { panel in
                    // The guest chooses the panel from the fold, so choosing a panel is folding.
                    guard let udid = manager.frontmostUDID,
                          let controller = manager.controller(for: udid) else { return }
                    let angle = panel.name == "Cover"
                        ? DeviceControlBar.FoldMode.cover.angle
                        : DeviceControlBar.FoldMode.fullyOpen.angle
                    controller.showHingeAngle(angle)
                    foldables.setAngle(angle, for: udid)
                },
                newSimulator: {
                    let simctl = SimctlService()
                    NewSimulatorPanel.show(actions: NewSimulatorActions(
                        deviceTypes: { (try? simctl.listDeviceTypes()) ?? [] },
                        runtimeSupport: { (try? simctl.listRuntimeSupport()) ?? [] },
                        existingNames: { ((try? adapter.devices()) ?? []).map(\.name) },
                        create: { name, type, runtime in
                            try simctl.createDevice(
                                name: name,
                                deviceType: type.identifier,
                                runtime: runtime.identifier
                            )
                        },
                        // A simulator created and then not shown would be a puzzle, so it opens,
                        // which boots it the same way the chooser does.
                        created: { udid in bootThenShow(udid) }
                    ), settings: settings)
                },
                setOrientation: { orientation in
                    guard let udid = manager.frontmostUDID else { return }
                    turn(orientation, udid)
                },
                appSwitcher: {
                    guard let target = front(), let session = target.controller.inputSession else { return }
                    let turn = target.controller.layoutTurn
                    Task {
                        do {
                            try await SystemGesture.appSwitcher(on: session, turn: turn)
                        } catch {
                            print("app switcher failed: \(error.localizedDescription)")
                        }
                    }
                },
                stopRecording: {
                    present(manager.toggleRecording(into: CaptureStaging.directory()))
                },
                isRecording: { manager.isRecording },
                isOn: { setting in
                    guard let target = front() else { return false }
                    let controller = target.controller
                    switch setting {
                    case .keyboardInput: return controller.sendsKeyboardInput
                    case .hardwareKeyboard: return controller.hasHardwareKeyboard
                    case .keyboardLanguage: return controller.matchesKeyboardLanguage
                    case .slowAnimations: return controller.slowAnimations
                    case .latencyOverlay: return controller.isLatencyOverlayVisible
                    case .bezel: return controller.isBezelEnabled
                    case .keepOnTop: return controller.isKeptOnTop
                    case .increasedContrast:
                        if let known = controller.increasesContrast { return known }
                        let read = SimctlService().increasesContrast(udid: target.udid)
                        controller.increasesContrast = read
                        return read
                    }
                },
                checkForUpdates: updates.map { updater in { updater.checkForUpdates() } },
                showSettings: {
                    SettingsWindow.show(settings: settings, actions: SettingsActions(
                        automaticUpdates: updates.map { updater in { updater.checksAutomatically } },
                        setAutomaticUpdates: updates.map { updater in { updater.checksAutomatically = $0 } },
                        checkForUpdates: updates.map { updater in { updater.checkForUpdates() } },
                        setPasteboardSync: { pasteboard.setAutomatic($0) },
                        forgetWindowPositions: { store.forgetAll() },
                        rememberedWindowCount: { store.rememberedCount },
                        openLinks: deviceLinks
                    ))
                }
            ), capabilities: adapter.capabilities, openSimulatorMenu: chooser.menu,
               commandLineTool: CommandLineToolInstaller.bundledTool == nil ? nil : CommandLineToolMenu(
                   state: { CommandLineToolInstaller.state() },
                   install: { CommandLineToolInstaller.install() },
                   remove: { CommandLineToolInstaller.remove() }
               ))
            if let updates {
                print("updates: \(updates.feedURL ?? "configured, feed unreadable")")
            } else {
                print("updates: off, this build carries no update channel")
            }

            do {
                let notifier = try adapter.watchDeviceStates()
                manager.follow(
                    notifier,
                    attach: { udid in
                        adapter.forgetConnections(udid)
                        return try openSessions(udid, adapter: adapter, bezel: bezel).attachment
                    },
                    boot: { udid in try SimctlService().boot(udid: udid) },
                    // Only when no simulator was named. `odhub view <udid>` asked for one window and
                    // should not sprout others because something else booted.
                    mirror: launchedFromAnIcon ? { try show($0, false) } : nil,
                    report: { print($0) }
                )
            } catch {
                print("device state changes will not be followed: \(error.localizedDescription)")
            }

            if manager.openCount == 0 {
                NothingToShow.present(reasons: failures, deviceCount: devices.count)
            }

            application.activate(ignoringOtherApps: true)
            let delegate = ViewerAppDelegate(
                quitsWithLastWindow: !launchedFromAnIcon,
                dockMenu: { chooser.dockMenu() },
                reopen: { bootThenShow($0) },
                openLink: { udid in
                    if manager.isOpen(udid) {
                        manager.bringToFront(udid)
                        NSApp.activate(ignoringOtherApps: true)
                    } else {
                        bootThenShow(udid)
                    }
                },
                deviceToReopen: { recent.udid ?? StartupDevices.plan(
                    devices: (try? adapter.devices()) ?? [],
                    remembered: nil
                ).udids.first },
                onTerminate: { manager.closeAll() },
                settlePreviews: { previews.settleEverything() },
                onResignActive: { pasteboard.reconcileOnResignActive() }
            )
            // NSApplication holds its delegate weakly, and nothing else refers to these objects
            // once the run loop starts, so without this ARC releases them and the display sessions
            // die with them: the windows stay up and never draw again.
            application.delegate = delegate
            withExtendedLifetime((manager, delegate, menuTarget, chooser, updates)) {
                application.run()
            }
        }
    }

    @MainActor
    private func open(
        udid: String,
        from devices: [DeviceInfo],
        adapter: any SimulatorAdapter,
        manager: DeviceWindowManager,
        allowBoot: Bool,
        rotate: @escaping @MainActor (DeviceOrientation, String) -> Void,
        present: @escaping @MainActor ([URL]) -> Void
    ) throws {
        guard var device = devices.first(where: {
            $0.udid.caseInsensitiveCompare(udid) == .orderedSame
        }) else {
            throw EngineError.deviceNotFound(udid: udid)
        }

        if device.state != .booted {
            guard allowBoot else { throw EngineError.deviceNotBooted(udid: device.udid) }
            let simctl = SimctlService()
            print("Booting \(device.name)...")
            try simctl.boot(udid: device.udid)
            try simctl.waitForBoot(udid: device.udid)
            device = try adapter.devices().first { $0.udid == device.udid } ?? device
        }

        let opened = try openSessions(device.udid, adapter: adapter, bezel: bezel)
        if let failure = opened.inputFailure {
            print("\(device.name): clicking will not send taps, \(failure)")
        }
        let panel = opened.unfolded
        let session = opened.session
        let orientation = DevicectlService().orientation(udid: device.udid, foldable: opened.foldsAtHinge) ?? .portrait

        let controller = try manager.open(
            device: device,
            session: session,
            input: opened.input,
            scaleMode: scale,
            bezelEnabled: bezel,
            keepOnTop: keepOnTop,
            showFPS: fps,
            foldsAtHinge: opened.foldsAtHinge,
            // The device type's chrome names only the cover's body, so the panel's own is used.
            chrome: panel?.chromeIdentifier.flatMap { ChromeLocator.chrome(identifier: $0) },
            panelNativeRotation: panel?.nativeRotation ?? 0,
            unfoldedPanel: panel,
            cover: opened.cover,
            retarget: opened.retarget,
            orientation: orientation
        )
        // The model turns the picture itself; setting this too turns the unfolded panel twice.
        if let panel, !controller.foldsAtHinge {
            controller.nativeRotation = panel.nativeRotation
        }
        installToolbar(
            udid: device.udid,
            manager: manager,
            adapter: adapter,
            saveScreenshotsToClipboard: { manager.savesScreenshotsToClipboard },
            rotate: rotate,
            present: present
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

@MainActor
private final class ViewerAppDelegate: NSObject, NSApplicationDelegate {
    private let quitsWithLastWindow: Bool
    private let dockMenu: () -> NSMenu
    private let reopen: (String) -> Void
    private let openLink: (String) -> Void
    private let deviceToReopen: () -> String?
    private let onTerminate: () -> Void
    private let settlePreviews: () -> Void
    private let onResignActive: () -> Void

    init(
        quitsWithLastWindow: Bool,
        dockMenu: @escaping () -> NSMenu,
        reopen: @escaping (String) -> Void,
        openLink: @escaping (String) -> Void,
        deviceToReopen: @escaping () -> String?,
        onTerminate: @escaping () -> Void,
        settlePreviews: @escaping () -> Void,
        onResignActive: @escaping () -> Void
    ) {
        self.quitsWithLastWindow = quitsWithLastWindow
        self.dockMenu = dockMenu
        self.reopen = reopen
        self.openLink = openLink
        self.deviceToReopen = deviceToReopen
        self.onTerminate = onTerminate
        self.settlePreviews = settlePreviews
        self.onResignActive = onResignActive
    }

    /// The automatic sync only carries the Mac's copies to the device, so a copy made inside a device
    /// is fetched when the user switches away, which is when they are about to paste it elsewhere.
    func applicationWillResignActive(_ notification: Notification) {
        onResignActive()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        quitsWithLastWindow
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        dockMenu()
    }

    /// A click on the icon of an app that is already running but showing nothing. Without this the
    /// click looks like it did nothing at all.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, let udid = deviceToReopen() else { return true }
        reopen(udid)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate()
    }

    /// A preview still on screen at quit is filed rather than lost, which is what leaving it alone
    /// would have done anyway.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        settlePreviews()
        return .terminateNow
    }

    /// A devices:// link only reaches this app if someone chose it in Settings. One that names a
    /// simulator opens here; anything else goes back to Device Hub whole, rather than being dropped
    /// because this app did not understand it.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch DeviceLink.destination(for: url) {
            case .simulator(let udid):
                openLink(udid)
            case .deviceHub:
                forwardToDeviceHub(url)
            case .notADeviceLink:
                continue
            }
        }
    }

    private func forwardToDeviceHub(_ url: URL) {
        guard let deviceHub = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.dt.Devices"
        ) else {
            print("no Device Hub to pass \(url) to")
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: deviceHub, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// The buttons above each device. Unlike the menu bar these act on one device, the one whose
/// window they sit on.
@MainActor
private func installToolbar(
    udid: String,
    manager: DeviceWindowManager,
    adapter: any SimulatorAdapter,
    saveScreenshotsToClipboard: @escaping @MainActor () -> Bool,
    rotate: @escaping @MainActor (DeviceOrientation, String) -> Void,
    present: @escaping @MainActor ([URL]) -> Void
) {
    guard let controller = manager.controller(for: udid) else { return }
    controller.setToolbarActions(DeviceToolbarActions(
        goHome: { [weak controller] in
            guard let controller else { return }
            Task {
                do {
                    guard let session = manager.controller(for: udid)?.inputSession else { return }
                    if controller.hasHomeButton {
                        try await session.button(.home, phase: .down)
                        try await Task.sleep(for: .milliseconds(15))
                        try await session.button(.home, phase: .up)
                    } else {
                        // A Face ID device has no Home button, so it goes home the way a hand
                        // would, by swiping up from the bottom edge.
                        try await SystemGesture.home(on: session, turn: controller.layoutTurn)
                    }
                } catch {
                    print("home failed: \(error.localizedDescription)")
                }
            }
        },
        saveScreenshot: {
            if saveScreenshotsToClipboard() {
                print(manager.copyScreenshotToClipboard(only: udid) ? "screenshot saved to clipboard" : "nothing to save")
            } else {
                present(manager.saveScreenshots(into: CaptureStaging.directory(), only: udid))
            }
        },
        stopRecording: {
            present(manager.toggleRecording(into: CaptureStaging.directory()))
        },
        rotate: { [weak controller] toLeft in
            guard let controller else { return }
            rotate(
                toLeft ? controller.currentOrientation.rotatedLeft
                       : controller.currentOrientation.rotatedRight,
                udid
            )
        }
    ))
}

/// What a window is opened with, and opened with again when its device comes back from a reboot.
@MainActor
private struct DeviceSessions {
    let foldsAtHinge: Bool
    let unfolded: DevicePanel?
    let session: any DisplaySession
    let cover: FoldableCover?
    let input: (any InputSession)?
    let inputFailure: String?
    let retarget: ((Int) -> Void)?

    var attachment: DeviceAttachment {
        DeviceAttachment(session: session, input: input, cover: cover, retarget: retarget)
    }
}

@MainActor
private func openSessions(_ udid: String, adapter: any SimulatorAdapter, bezel: Bool) throws -> DeviceSessions {
    // More than one built in screen means a hinge between them.
    let panels = (try? adapter.panels(udid)) ?? []
    let foldsAtHinge = panels.count > 1
    let unfolded = foldsAtHinge ? panels.first { $0.name == "Unfolded" } : nil
    let coverPanel = foldsAtHinge ? panels.first { $0.name == "Cover" } : nil
    let session = try adapter.openDisplay(udid, panel: unfolded)
    session.setBezelEnabled(bezel)
    var cover: FoldableCover?
    if let coverPanel, let coverSession = try? adapter.openDisplay(udid, panel: coverPanel) {
        coverSession.setBezelEnabled(bezel)
        cover = FoldableCover(panel: coverPanel, session: coverSession)
    }
    var input: (any InputSession)?
    var inputFailure: String?
    do {
        input = try adapter.openInput(udid, screenID: unfolded?.screenID ?? 0)
    } catch {
        inputFailure = error.localizedDescription
    }
    let retarget: ((Int) -> Void)? = (input as? PanelInputSession).map { targeted in
        { targeted.setTarget(screenID: $0) }
    }
    return DeviceSessions(
        foldsAtHinge: foldsAtHinge,
        unfolded: unfolded,
        session: session,
        cover: cover,
        input: input,
        inputFailure: inputFailure,
        retarget: retarget
    )
}

/// Off the main thread, because every one of these blocks for a second or more and they run from a
/// menu. A failure is printed rather than swallowed.
@MainActor
private func runOnEveryDevice(
    _ what: String,
    _ udid: String,
    _ work: @escaping @Sendable (String) throws -> Void
) {
    Task {
        let failure = await Task.detached { () -> String? in
            do {
                try work(udid)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if let failure { print("\(what) failed: \(failure)") }
    }
}

/// Latitude and longitude asked for in one line. The simulator this replaces opens a map here,
/// which is a different piece of work.
@MainActor
enum CustomLocationPrompt {
    static func ask() -> (latitude: Double, longitude: Double)? {
        let alert = NSAlert()
        alert.messageText = "Custom Location"
        alert.informativeText = "Latitude and longitude, separated by a comma."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "37.3349, -122.0090"
        alert.accessoryView = field
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard let point = Coordinate(parsing: field.stringValue) else {
            let complaint = NSAlert()
            complaint.messageText = "That is not a coordinate."
            complaint.informativeText = "Latitude is between -90 and 90, longitude between -180 and 180."
            complaint.runModal()
            return nil
        }
        return (point.latitude, point.longitude)
    }
}

/// Recordings and screenshots land on the Desktop, falling back to a temporary folder on a machine
/// that has none.
/// Captures are written here first and only move into the capture folder when their preview goes
/// away, so the folder stays empty while a preview is still on screen.
enum CaptureStaging {
    static func directory() -> URL {
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "\(Brand.identifierPrefix).captures")
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }
}

private func captureDirectory(for capture: URL, settings: ViewerSettings = ViewerSettings()) -> URL {
    let chosen = capture.pathExtension.lowercased() == "mov"
        ? settings.recordingDirectory
        : settings.screenshotDirectory
    if let chosen,
       FileManager.default.fileExists(atPath: chosen.path(percentEncoded: false)) {
        return chosen
    }
    // A folder that has been moved or unplugged since it was chosen falls back rather than losing
    // the capture.
    return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory())
}
