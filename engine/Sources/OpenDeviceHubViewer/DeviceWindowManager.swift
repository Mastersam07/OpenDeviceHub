import AppKit
import OpenDeviceHubEngine

/// Owns one window per device. Windows are cascaded rather than centred so that several devices
/// opened at once do not land on top of each other.
@MainActor
public final class DeviceWindowManager {
    private var controllers: [String: DeviceWindowController] = [:]
    private let frameStore: WindowFrameStore
    private let placementGap: CGFloat = 12

    public init(frameStore: WindowFrameStore = WindowFrameStore()) {
        self.frameStore = frameStore
    }

    public var openCount: Int { controllers.count }

    public func isOpen(_ udid: String) -> Bool {
        controllers[udid] != nil
    }

    @discardableResult
    public func open(
        device: DeviceInfo,
        session: any DisplaySession,
        input: (any InputSession)?,
        scaleMode: ScaleMode,
        bezelEnabled: Bool,
        keepOnTop: Bool,
        showFPS: Bool
    ) throws -> DeviceWindowController {
        if let existing = controllers[device.udid] {
            existing.window?.makeKeyAndOrderFront(nil)
            return existing
        }

        let controller = try DeviceWindowController(
            udid: device.udid,
            title: "\(device.name) (\(device.runtimeName))",
            session: session,
            input: input,
            scaleMode: scaleMode,
            bezelEnabled: bezelEnabled,
            keepOnTop: keepOnTop,
            frameStore: frameStore,
            fpsLabel: showFPS ? device.name : nil,
            chrome: ChromeLocator.chrome(forDeviceType: device.deviceTypeIdentifier)
        )
        controller.onClose = { [weak self] udid in
            self?.controllers.removeValue(forKey: udid)
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

    public func close(_ udid: String) {
        guard let controller = controllers.removeValue(forKey: udid) else { return }
        controller.onClose = nil
        controller.stop()
        controller.window?.close()
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
    public var openUDIDs: [String] { Array(controllers.keys) }

    public func controller(for udid: String) -> DeviceWindowController? { controllers[udid] }

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
        stopRecording()
        for udid in controllers.keys {
            close(udid)
        }
    }
}
