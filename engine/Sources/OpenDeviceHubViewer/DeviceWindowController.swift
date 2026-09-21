import AppKit
import MetalKit
import OpenDeviceHubEngine

@MainActor
public final class DeviceWindowController: NSWindowController, NSWindowDelegate {
    public let udid: String
    /// Called when the window closes, so the owner can drop its reference.
    public var onClose: ((String) -> Void)?

    private let session: any DisplaySession
    private let renderer: FrameRenderer
    private let screenView: DeviceScreenView
    private let chromeView: DeviceChromeView
    private var chrome: DeviceChrome?
    private var frameTask: Task<Void, Never>?

    private let input: (any InputSession)?
    private var isStopped = false
    private var keepOnTop = false
    private var isRecording = false
    /// Set once the window has been placed. Sizing and centring during construction move the
    /// window, and saving those would make every device look like it had a remembered position.
    private var tracksFrameChanges = false
    private var deviceAspectRatio: CGSize = .zero
    private var baseTitle: String?
    private let latency = LatencyMeter()
    private var showsLatency = false
    private var parallelOffset = CGSize(width: 0.12, height: 0)
    private var orientation: DeviceOrientation = .portrait
    private var scaleMode: ScaleMode
    private var bezelEnabled: Bool
    private let frameStore: WindowFrameStore

    public init(
        udid: String,
        title: String,
        session: any DisplaySession,
        input: (any InputSession)?,
        scaleMode: ScaleMode,
        bezelEnabled: Bool,
        keepOnTop: Bool,
        frameStore: WindowFrameStore,
        fpsLabel: String?,
        chrome: DeviceChrome?
    ) throws {
        self.frameStore = frameStore
        self.udid = udid
        self.scaleMode = scaleMode
        self.bezelEnabled = bezelEnabled
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ViewerError.metalUnavailable("no system default device")
        }
        self.session = session
        self.input = input
        screenView = DeviceScreenView(device: device)
        renderer = try FrameRenderer(device: device, pixelFormat: screenView.colorPixelFormat)
        screenView.delegate = renderer
        chromeView = DeviceChromeView(screenView: screenView)
        self.chrome = chrome

        let screenSize = DeviceGeometry.pointSize(
            pixelSize: session.pixelSize,
            pointScale: session.pointScale
        )
        let contentSize = bezelEnabled && chrome != nil
            ? ChromeGeometry.contentSize(screen: screenSize, chrome: chrome!)
            : screenSize
        let window = DeviceWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        baseTitle = title
        window.contentView = chromeView
        // Without this the body's buttons never see the pointer, so they cannot rise under it.
        window.acceptsMouseMovedEvents = true
        window.contentAspectRatio = contentSize
        self.deviceAspectRatio = contentSize
        window.center()
        window.collectionBehavior.insert(.fullScreenPrimary)
        super.init(window: window)
        window.delegate = self
        chromeView.setChrome(bezelEnabled ? chrome : nil)
        installChromeButtons()
        applyScaleMode(scaleMode)
        setKeepOnTop(keepOnTop)

        // A remembered frame wins over the default placement, but not over an explicit scale mode,
        // which has already sized the window by this point.
        if let remembered = frameStore.frame(for: udid) {
            if scaleMode == .fit {
                window.setFrame(remembered, display: false)
            } else {
                window.setFrameOrigin(remembered.origin)
            }
            keepOnScreen()
        }

        if let fpsLabel {
            installFPSCounter(label: fpsLabel)
        }
        if input != nil {
            installClickToTap()
        }
        startConsumingFrames()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    public func stop() {
        guard !isStopped else { return }
        isStopped = true
        frameTask?.cancel()
        frameTask = nil
        input?.close()
        session.close()
    }

    /// Resizes the window so the device screen is shown at the requested scale. Fit leaves the
    /// window alone, since it is the mode that lets any size work.
    @discardableResult
    public func applyScaleMode(_ mode: ScaleMode) -> ScaleApplication {
        scaleMode = mode
        guard let window else { return .unavailable }
        let device = DeviceMetrics(
            pixelSize: session.pixelSize,
            pointScale: session.pointScale,
            pixelsPerInch: session.pixelsPerInch
        )
        guard let screenSize = DeviceGeometry.contentSize(
            for: mode,
            device: device,
            screen: ScaleMode.screenMetrics(for: window.screen ?? NSScreen.main),
            orientation: orientation
        ) else {
            return mode == .fit ? .noFixedSize : .unavailable
        }
        // A scale mode sizes the screen, so the body has to be added on top of whatever it asks
        // for, or the window would crop it.
        let size = chromeView.hasChrome && chrome != nil
            ? ChromeGeometry.contentSize(screen: screenSize, chrome: chrome!)
            : screenSize
        // The ratio has to be relaxed before the size is set. AppKit applies the old one to the new
        // size otherwise, which shrank the window to the bare screen's shape when the body came
        // back.
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
        window.setContentSize(size)
        window.contentAspectRatio = size
        deviceAspectRatio = size
        keepOnScreen()

        let visible = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? .zero
        let titleBar = window.frame.height - window.contentLayoutRect.height
        let fits = DeviceGeometry.fitsOnScreen(
            contentSize: size,
            visibleSize: visible,
            titleBarHeight: titleBar
        )
        return fits ? .applied(size) : .largerThanScreen(size)
    }

    private func keepOnScreen() {
        guard let window,
              !window.styleMask.contains(.fullScreen),
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let origin = DeviceGeometry.onScreenOrigin(frame: window.frame, visibleFrame: visible)
        guard origin != window.frame.origin else { return }
        window.setFrameOrigin(origin)
    }

    public var currentScaleMode: ScaleMode { scaleMode }

    public var supportsBezel: Bool { session.supportsBezel || chrome != nil }

    public var isBezelEnabled: Bool { bezelEnabled }

    /// Shows or hides the device's bezel. The window keeps its size either way, since the bezel
    /// only changes what is drawn inside the same framebuffer.
    public func setBezelEnabled(_ enabled: Bool) {
        bezelEnabled = enabled
        // Two halves: the guest's own screen shape, and the body drawn around it.
        session.setBezelEnabled(enabled)
        chromeView.setChrome(enabled ? chrome : nil)
        applyScaleMode(scaleMode)
    }

    private func installChromeButtons() {
        chromeView.onButton = { [weak self] button, phase in
            guard let self, let input else { return }
            Task { try? await input.button(button, phase: phase) }
        }
    }

    /// Keeps the device above other applications, the way the classic Simulator could.
    public func setKeepOnTop(_ enabled: Bool) {
        keepOnTop = enabled
        window?.level = enabled ? .floating : .normal
    }

    public var isKeptOnTop: Bool { keepOnTop }

    public func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    /// Starts persisting the window's frame. Called once the owner has finished placing it.
    public func beginTrackingFrameChanges() {
        tracksFrameChanges = true
    }

    /// The most recent frame as a PNG, matching whatever the window is showing including the bezel.
    public func screenshotPNG() -> Data? {
        renderer.currentSurface.flatMap(ScreenshotWriter.pngData)
    }

    /// The plain device name, without the recording dot or the latency overlay, so screenshot and
    /// recording file names do not pick up whatever the title bar happens to be showing.
    public var deviceTitle: String { baseTitle ?? window?.title ?? udid }

    /// A red dot in the title bar while recording, so a long capture is obvious.
    /// Shows click to frame latency in the title bar, which is the debug overlay the plan asks for.
    public func setLatencyOverlayVisible(_ visible: Bool) {
        showsLatency = visible
        if !visible { updateTitle() }
    }

    public var isLatencyOverlayVisible: Bool { showsLatency }

    public var latencyReading: LatencyMeter.Reading? { latency.reading }

    private func updateTitle() {
        guard let window else { return }
        let base = baseTitle ?? window.title
        baseTitle = base
        var title = isRecording ? "\u{25CF} \(base)" : base
        if showsLatency, let reading = latency.reading {
            title += String(
                format: "  %.0f ms (avg %.0f over %d)",
                reading.lastMilliseconds, reading.averageMilliseconds, reading.sampleCount
            )
        }
        window.title = title
    }

    public func setRecordingIndicatorVisible(_ visible: Bool) {
        isRecording = visible
        updateTitle()
    }

    /// Turns the window and the image to match the device. The device itself is turned by the
    /// adapter; this is the half the host owns.
    public func setOrientation(_ orientation: DeviceOrientation) {
        self.orientation = orientation
        renderer.setOrientation(orientation)
        let displayed = orientation.displayedSize(portraitNative: session.pixelSize)
        let scale = session.pointScale > 0 ? session.pointScale : 1
        let aspect = CGSize(width: displayed.width / scale, height: displayed.height / scale)
        window?.contentAspectRatio = aspect
        deviceAspectRatio = aspect
        applyScaleMode(scaleMode)
        screenView.needsDisplay = true
    }

    public var currentOrientation: DeviceOrientation { orientation }

    /// Offers a finished recording for dragging out of the window.
    public func setDraggableFile(_ file: URL?) {
        screenView.draggableFile = file
    }

    public func rememberFrame() {
        guard tracksFrameChanges,
              let window,
              !window.styleMask.contains(.fullScreen) else { return }
        frameStore.save(window.frame, for: udid)
    }

    /// A locked aspect ratio cannot survive a full screen transition: AppKit collapses the window
    /// to the title bar trying to satisfy both. Clearing it through `contentResizeIncrements` is
    /// the documented way, since the two are mutually exclusive.
    public func windowWillEnterFullScreen(_ notification: Notification) {
        (window as? DeviceWindow)?.constrainsToScreen = true
        window?.contentResizeIncrements = NSSize(width: 1, height: 1)
    }

    public func windowDidExitFullScreen(_ notification: Notification) {
        (window as? DeviceWindow)?.constrainsToScreen = false
        guard deviceAspectRatio != .zero else { return }
        window?.contentAspectRatio = deviceAspectRatio
    }

    public func windowDidMove(_ notification: Notification) {
        rememberFrame()
    }

    public func windowDidResize(_ notification: Notification) {
        rememberFrame()
    }

    public func windowWillClose(_ notification: Notification) {
        rememberFrame()
        stop()
        onClose?(udid)
    }

    /// Runs the dropped actions, asking first for anything that changes what the device trusts.
    private func perform(_ actions: [DropAction]) -> Bool {
        let simctl = SimctlService()
        var didSomething = false
        for action in actions {
            if action.needsConfirmation, !confirm(action) { continue }
            do {
                try simctl.perform(action, udid: udid)
                didSomething = true
            } catch {
                present(error)
            }
        }
        return didSomething
    }

    private func confirm(_ action: DropAction) -> Bool {
        guard case .addRootCertificate(let certificate) = action else { return true }
        let alert = NSAlert()
        alert.messageText = "Trust \(certificate.lastPathComponent)?"
        alert.informativeText = """
            This adds the certificate to the simulator's trusted root store, so the device will \
            trust anything it signs.
            """
        alert.addButton(withTitle: "Trust")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func present(_ error: any Error) {
        let alert = NSAlert()
        alert.messageText = "That drop did not work."
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func installClickToTap() {
        let pixelSize = session.pixelSize
        let screenView = screenView

        screenView.onContact = { [weak self] point, phase, style in
            guard let self, let input else { return }
            let orientation = self.orientation
            guard let primary = CoordinateMapper.normalize(
                viewPoint: point,
                viewSize: screenView.bounds.size,
                pixelSize: orientation.displayedSize(portraitNative: pixelSize)
            ) else { return }

            let touchPhase: TouchEvent.Phase = switch phase {
            case .began: .began
            case .moved: .moved
            case .ended: .ended
            }

            var shown = [primary]
            switch style {
            case .single:
                break
            case .mirrored:
                shown.append(TwoFingerGesture.mirrored(primary, about: CGPoint(x: 0.5, y: 0.5)))
            case .parallel:
                if phase == .began { self.parallelOffset = CGSize(width: 0.12, height: 0) }
                shown.append(TwoFingerGesture.offsetPartner(primary, by: self.parallelOffset))
            }
            let points = shown.map {
                CoordinateMapper.portraitNativePoint(from: $0, orientation: orientation)
            }

            if touchPhase == .began { self.latency.clickSent() }
            let event = TouchEvent(phase: touchPhase, points: points)
            Task { try? await input.touch(event) }
        }

        screenView.onDrop = { [weak self] urls, text in
            guard let self else { return false }
            var actions = DropRouting.actions(for: urls)
            if let text { actions.append(.openURL(text)) }
            guard !actions.isEmpty else { return false }
            return self.perform(actions)
        }

        screenView.onKey = { [weak self] usage, isDown in
            guard let self, let input else { return }
            Task { try? await input.key(KeyEvent(phase: isDown ? .down : .up, usage: usage)) }
        }

        screenView.onGesture = { [weak self] phase, spread, angle in
            guard let self, let input else { return }
            let size = screenView.bounds.size
            guard size.width > 0, size.height > 0 else { return }

            let normalizedSpread = spread / min(size.width, size.height)
            let orientation = self.orientation
            let contacts = TwoFingerGesture.contacts(
                centre: CGPoint(x: 0.5, y: 0.5),
                spread: normalizedSpread,
                angle: angle
            ).map { CoordinateMapper.portraitNativePoint(from: $0, orientation: orientation) }
            let touchPhase: TouchEvent.Phase = switch phase {
            case .began: .began
            case .moved: .moved
            case .ended: .ended
            }
            Task { try? await input.touch(TouchEvent(phase: touchPhase, points: contacts)) }
        }
    }

    private func startConsumingFrames() {
        let renderer = renderer
        let screenView = screenView
        frameTask = Task { [frames = session.frames, weak self] in
            for await frame in frames {
                if Task.isCancelled { return }
                renderer.accept(frame)
                await MainActor.run { [weak self] in
                    screenView.needsDisplay = true
                    guard let self else { return }
                    if self.latency.frameDrawn() != nil, self.showsLatency {
                        self.updateTitle()
                    }
                }
            }
        }
    }

    private func installFPSCounter(label: String) {
        let counter = FPSCounter(label: label)
        renderer.onFrameDrawn = { counter.record() }
    }
}

private final class FPSCounter: @unchecked Sendable {
    private let label: String
    private let lock = NSLock()
    private var count = 0
    private var windowStart = Date()

    init(label: String) {
        self.label = label
    }

    func record() {
        lock.lock()
        count += 1
        let elapsed = Date().timeIntervalSince(windowStart)
        guard elapsed >= 1 else {
            lock.unlock()
            return
        }
        let fps = Double(count) / elapsed
        count = 0
        windowStart = Date()
        lock.unlock()
        print(String(format: "%@  %.1f fps", label, fps))
    }
}
