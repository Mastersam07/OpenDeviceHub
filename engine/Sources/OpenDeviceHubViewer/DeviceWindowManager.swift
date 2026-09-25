import AppKit
import OpenDeviceHubEngine

/// Owns one window per device. Windows are cascaded rather than centred so that several devices
/// opened at once do not land on top of each other.
@MainActor
public final class DeviceWindowManager {
    private var controllers: [String: DeviceWindowController] = [:]
    private var followTask: Task<Void, Never>?
    // Held because a notifier closes itself when it goes, which would end the stream silently.
    private var notifier: (any DeviceNotifier)?
    private var boot: ((String) throws -> Void)?
    private var mirror: ((String) throws -> Void)?
    private var report: (String) -> Void = { _ in }
    private let frameStore: WindowFrameStore
    private let settings: ViewerSettings
    private let shutdownDevice: @Sendable (String) throws -> Void
    private let placementGap: CGFloat = 12

    public init(
        frameStore: WindowFrameStore = WindowFrameStore(),
        settings: ViewerSettings = ViewerSettings(),
        shutdown: @escaping @Sendable (String) throws -> Void = { try SimctlService().shutdown(udid: $0) }
    ) {
        self.frameStore = frameStore
        self.settings = settings
        self.shutdownDevice = shutdown
    }

    public var openCount: Int { controllers.count }

    public func isOpen(_ udid: String) -> Bool {
        controllers[udid] != nil
    }

    public func bringToFront(_ udid: String) {
        controllers[udid]?.window?.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    public func open(
        device: DeviceInfo,
        session: any DisplaySession,
        input: (any InputSession)?,
        scaleMode: ScaleMode,
        bezelEnabled: Bool,
        keepOnTop: Bool,
        showFPS: Bool,
        foldsAtHinge: Bool = false,
        chrome: DeviceChrome? = nil
    ) throws -> DeviceWindowController {
        if let existing = controllers[device.udid] {
            existing.window?.makeKeyAndOrderFront(nil)
            return existing
        }

        let controller = try DeviceWindowController(
            udid: device.udid,
            title: "\(device.name) (\(device.runtimeName))",
            deviceName: device.name,
            runtimeName: device.runtimeName,
            session: session,
            input: input,
            scaleMode: scaleMode,
            bezelEnabled: bezelEnabled,
            keepOnTop: keepOnTop,
            frameStore: frameStore,
            fpsLabel: showFPS ? device.name : nil,
            chrome: chrome ?? ChromeLocator.chrome(forDeviceType: device.deviceTypeIdentifier),
            foldsAtHinge: foldsAtHinge
        )
        controller.onClose = { [weak self] udid in
            self?.controllers.removeValue(forKey: udid)
            self?.shutdownIfAsked(udid)
            self?.onDeviceClosed?(udid)
        }
        // A window that has lost its sessions offers the same way back as one whose device shut
        // down, since a wedged device usually needs the same thing.
        controller.onReboot = { [weak self] in self?.reboot(device.udid) }
        controller.onSessionLost = { [weak self] in
            self?.report("\(device.name) stopped taking input")
        }
        controllers[device.udid] = controller

        // Only place the window when nothing was remembered for this device, so a window the user
        // moved stays where they put it.
        if let window = controller.window {
            if frameStore.frame(for: device.udid) == nil {
                let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
                window.setFrameOrigin(WindowPlacement.nextOrigin(
                    for: window.frame.size,
                    placed: placedFrames(excluding: device.udid),
                    in: visible,
                    gap: placementGap
                ))
            }
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        }
        controller.beginTrackingFrameChanges()
        return controller
    }

    /// Keeps every window in step with its device. A shutdown from anywhere, ours, simctl, Xcode or
    /// Device Hub, puts the window into its shut down state, and a boot from anywhere brings it
    /// back. Driven entirely by the notifier: nothing here asks for device state on a timer.
    public func follow(
        _ notifier: any DeviceNotifier,
        attach: @escaping (String) throws -> DeviceAttachment,
        boot: @escaping (String) throws -> Void,
        mirror: ((String) throws -> Void)? = nil,
        report: @escaping (String) -> Void = { _ in }
    ) {
        self.report = report
        self.boot = boot
        self.mirror = mirror
        self.notifier = notifier
        followTask?.cancel()
        followTask = Task { [weak self] in
            for await change in notifier.changes {
                guard let self else { return }
                self.apply(change, attach: attach)
            }
        }
    }

    private func apply(_ change: DeviceStateChange, attach: (String) throws -> DeviceAttachment) {
        guard let controller = controller(for: change.udid) else {
            // A device that boots with no window of its own gets one, so booting from the chooser,
            // from simctl or from Xcode all end the same way: a window appears.
            guard change.state == .booted, let mirror else { return }
            do {
                try mirror(change.udid)
            } catch {
                report("\(change.udid) booted but could not be shown: \(error.localizedDescription)")
            }
            return
        }
        switch DeviceWindowTransition.forState(change.state, isDetached: controller.isDetached) {
        case .ignore:
            return
        case .detach(let reason):
            if reason == .shutDown {
                controller.onReboot = { [weak self] in self?.reboot(change.udid) }
            }
            controller.detach(reason: reason)
            report("\(controller.deviceTitle) \(reason.summary)")
        case .reattach:
            do {
                let attachment = try attach(change.udid)
                controller.reattach(session: attachment.session, input: attachment.input)
                report("\(controller.deviceTitle) reattached")
            } catch {
                let reason = DetachReason.failed(error.localizedDescription)
                controller.detach(reason: reason)
                report("\(controller.deviceTitle) could not be reattached: \(reason.summary)")
            }
        }
    }

    private func reboot(_ udid: String) {
        guard let boot else { return }
        do {
            try boot(udid)
        } catch {
            controller(for: udid)?.detach(reason: .failed(error.localizedDescription))
        }
    }

    public func close(_ udid: String) {
        close(udid, shuttingDown: true)
    }

    /// Closes the window and leaves the device running, which is what showing another of its screens
    /// needs: the window goes, the device does not.
    public func closeKeepingDevice(_ udid: String) {
        close(udid, shuttingDown: false)
    }

    private func close(_ udid: String, shuttingDown: Bool) {
        guard let controller = controllers.removeValue(forKey: udid) else { return }
        controller.onClose = nil
        controller.stop()
        controller.window?.close()
        if shuttingDown {
            shutdownIfAsked(udid)
        }
    }

    /// Closing a window shuts its device down, which is what Simulator.app does and what someone
    /// closing a window usually means. Off in Settings for anyone who wants the device to outlive
    /// the window.
    ///
    /// Off the main thread because shutting down blocks for a second or two, and this runs while a
    /// window is going away.
    private func shutdownIfAsked(_ udid: String) {
        guard settings.shutsDownOnWindowClose else { return }
        let shutdown = shutdownDevice
        Task { [weak self] in
            let failure = await Task.detached { () -> String? in
                do {
                    try shutdown(udid)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            guard let failure else { return }
            self?.report("\(udid) could not be shut down: \(failure)")
        }
    }

    @discardableResult
    public func applyScaleMode(_ mode: ScaleMode) -> [String: ScaleApplication] {
        controllers.mapValues { $0.applyScaleMode(mode) }
    }

    private func placedFrames(excluding udid: String) -> [CGRect] {
        controllers
            .filter { $0.key != udid }
            .compactMap { $0.value.window?.frame }
    }

    public func setKeepOnTop(_ enabled: Bool) {
        for controller in controllers.values {
            controller.setKeepOnTop(enabled)
        }
    }

    public func setBezelEnabled(_ enabled: Bool) {
        for controller in controllers.values {
            controller.setBezelEnabled(enabled)
        }
    }

    /// The UDIDs of every open window, so a menu action can reach all of them.
    /// Called after a window has closed, so anything held per device can be let go of.
    public var onDeviceClosed: ((String) -> Void)?

    public var openUDIDs: [String] { Array(controllers.keys) }

    public func controller(for udid: String) -> DeviceWindowController? { controllers[udid] }
    /// The device the user is looking at, which is where an action that can only land on one goes.
    public var frontmostUDID: String? {
        controllers.first { $0.value.window?.isKeyWindow == true }?.key ?? controllers.keys.first
    }


    public func toggleBezel() {
        let enabled = controllers.values.first?.isBezelEnabled ?? true
        setBezelEnabled(!enabled)
    }

    public func toggleKeepOnTop() {
        let enabled = controllers.values.first?.isKeptOnTop ?? false
        setKeepOnTop(!enabled)
    }

    /// Writes a PNG of every open device into `directory`, returning the files written.
    @discardableResult
    /// Writes a PNG per open device, or for just one when a udid is given, which is what the
    /// button above a single window needs.
    public func saveScreenshots(
        into directory: URL,
        date: Date = Date(),
        only udid: String? = nil
    ) -> [URL] {
        var written: [URL] = []
        let chosen = udid.map { controllers[$0].map { [$0] } ?? [] } ?? Array(controllers.values)
        for controller in chosen {
            guard let data = controller.screenshotPNG() else { continue }
            let url = directory.appending(path: ScreenshotWriter.fileName(
                deviceName: controller.deviceTitle,
                date: date
            ))
            if (try? data.write(to: url)) != nil {
                written.append(url)
            }
        }
        return written
    }

    /// Copies the frontmost device's screen to the Mac clipboard.
    @discardableResult
    public func copyScreenshotToClipboard() -> Bool {
        let controller = controllers.values.first { $0.window?.isKeyWindow == true }
            ?? controllers.values.first
        guard let data = controller?.screenshotPNG(),
              let image = NSImage(data: data) else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([image])
    }

    private var recorders: [String: ScreenRecorder] = [:]

    public var isRecording: Bool { !recorders.isEmpty }

    /// Starts or stops recording every open device. Returns the files finished by a stop.
    @discardableResult
    public func toggleRecording(into directory: URL, date: Date = Date()) -> [URL] {
        guard recorders.isEmpty else {
            var finished: [URL] = []
            for (udid, recorder) in recorders {
                let file = recorder.stop()
                finished.append(file)
                // The window now holds the file, so Command dragging from the screen hands it off
                // to Finder or anywhere else that takes a file.
                controllers[udid]?.setDraggableFile(file)
            }
            recorders.removeAll()
            for controller in controllers.values {
                controller.setRecordingIndicatorVisible(false)
            }
            return finished
        }

        for (udid, controller) in controllers {
            let name = ScreenshotWriter.fileName(deviceName: controller.deviceTitle, date: date)
                .replacingOccurrences(of: ".png", with: ".mov")
            guard let recorder = try? ScreenRecorder(udid: udid, url: directory.appending(path: name)) else {
                continue
            }
            recorders[udid] = recorder
            controller.setRecordingIndicatorVisible(true)
        }
        return []
    }

    public func stopRecording() {
        guard !recorders.isEmpty else { return }
        for recorder in recorders.values { recorder.stop() }
        recorders.removeAll()
        for controller in controllers.values {
            controller.setRecordingIndicatorVisible(false)
        }
    }

    public func setLatencyOverlayVisible(_ visible: Bool) {
        for controller in controllers.values {
            controller.setLatencyOverlayVisible(visible)
        }
    }

    public func toggleLatencyOverlay() {
        let visible = controllers.values.first?.isLatencyOverlayVisible ?? false
        setLatencyOverlayVisible(!visible)
    }

    public func closeAll() {
        followTask?.cancel()
        followTask = nil
        notifier?.close()
        notifier = nil
        stopRecording()
        for udid in controllers.keys {
            close(udid)
        }
    }
}

/// The pair of sessions a window needs, so reattaching after a reboot is one call.
public struct DeviceAttachment {
    public let session: any DisplaySession
    public let input: (any InputSession)?

    public init(session: any DisplaySession, input: (any InputSession)?) {
        self.session = session
        self.input = input
    }
}
