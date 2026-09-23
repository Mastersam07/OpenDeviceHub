import AppKit
import MetalKit
import OpenDeviceHubEngine

@MainActor
public final class DeviceWindowController: NSWindowController, NSWindowDelegate {
    public let udid: String
    /// Called when the window closes, so the owner can drop its reference.
    public var onClose: ((String) -> Void)?

    private var session: any DisplaySession
    private let renderer: FrameRenderer
    private let screenView: DeviceScreenView
    private let chromeView: DeviceChromeView
    private let controlBar: DeviceControlBar
    private let presentationView: DevicePresentationView
    private var chrome: DeviceChrome?
    private var toolbar: DeviceToolbar?
    private let recordingIndicator = RecordingIndicator()
    private var frameTask: Task<Void, Never>?
    private var overlay: ShutdownOverlayView?
    /// Called when the window's Reboot button is pressed. The owner boots the device; the window
    /// comes back on its own once the notifier says it is up.
    public var onReboot: (() -> Void)?

    private var input: (any InputSession)?
    private var isStopped = false
    private var keepOnTop = false
    /// Set once the window has been placed. Sizing and centring during construction move the
    /// window, and saving those would make every device look like it had a remembered position.
    private var tracksFrameChanges = false
    private var baseTitle: String?
    private let latency = LatencyMeter()
    private var showsLatency = false
    private var parallelOffset = CGSize(width: 0.12, height: 0)
    private var dragEdge: TouchEvent.Edge = .none
    private var orientation: DeviceOrientation = .portrait
    private var scaleMode: ScaleMode
    private var bezelEnabled: Bool
    private let frameStore: WindowFrameStore

    public init(
        udid: String,
        title: String,
        deviceName: String,
        runtimeName: String,
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
        controlBar = DeviceControlBar(deviceName: deviceName, runtimeName: runtimeName)
        presentationView = DevicePresentationView(bar: controlBar, chrome: chromeView)
        self.chrome = chrome

        let screenSize = DeviceGeometry.pointSize(
            pixelSize: session.pixelSize,
            pointScale: session.pointScale
        )
        let deviceSize = bezelEnabled && chrome != nil
            ? ChromeGeometry.contentSize(screen: screenSize, chrome: chrome!, orientation: .portrait)
            : screenSize
        let contentSize = PresentationLayout.contentSize(forDevice: deviceSize)
        let window = DeviceWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        baseTitle = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = presentationView
        // Without this the body's buttons never see the pointer, so they cannot rise under it.
        window.acceptsMouseMovedEvents = true
        window.contentAspectRatio = contentSize
        window.center()
        window.collectionBehavior.insert(.fullScreenPrimary)
        super.init(window: window)
        window.delegate = self
        chromeView.setScreenSize(screenSize)
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
        recordingIndicator.detach()
        closeSessions()
    }

    private func closeSessions() {
        frameTask?.cancel()
        frameTask = nil
        input?.close()
        input = nil
        session.close()
    }

    public var isDetached: Bool { overlay != nil }

    /// The device has gone. The sessions are dropped rather than left pointing at a device that no
    /// longer answers, and the window says so instead of holding the last frame it happened to get.
    public func detach(reason: DetachReason) {
        guard !isStopped else { return }
        closeSessions()
        let overlay = self.overlay ?? ShutdownOverlayView(deviceName: deviceTitle)
        if self.overlay == nil {
            overlay.onReboot = { [weak self] in self?.onReboot?() }
            self.overlay = overlay
            chromeView.overlay = overlay
        }
        switch reason {
        case .shutDown: overlay.setShutDown()
        case .booting: overlay.setBooting()
        case .failed(let message): overlay.setFailed(message)
        }
        toolbar?.setEnabled(false)
    }

    /// The device is back. The window keeps its size, position and orientation, so a reboot looks
    /// like the screen coming back on rather than a new window.
    public func reattach(session: any DisplaySession, input: (any InputSession)?) {
        guard !isStopped else { return }
        closeSessions()
        self.session = session
        self.input = input
        session.setBezelEnabled(bezelEnabled)
        chromeView.overlay = nil
        overlay = nil
        toolbar?.setEnabled(true)
        startConsumingFrames()
        applyScaleMode(scaleMode)
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
        // The scale mode already turned the screen, and the chrome turns it again, so this undoes
        // the first turn to hand the chrome the upright size it expects. Swapping twice is the
        // same size back.
        let upright = orientation.displayedSize(portraitNative: screenSize)
        let wanted = chromeView.hasChrome && chrome != nil
            ? ChromeGeometry.contentSize(screen: upright, chrome: chrome!, orientation: orientation)
            : screenSize
        // The screen the body is built around has to shrink with the window, or the chrome lays the
        // device out at its full size inside a smaller view and the bottom of it is simply cut off.
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? .zero
        var factor = PresentationLayout.scale(fitting: wanted, in: visible)
        var screen = scaled(upright, by: factor)
        var size = deviceSize(forScreen: screen, fallback: scaled(screenSize, by: factor))
        // The body's own margins do not scale exactly with the screen inside them, so the first
        // pass can land a point or two over. One correction against the size actually derived
        // settles it.
        let correction = PresentationLayout.scale(fitting: size, in: visible)
        if correction < 1 {
            factor *= correction
            screen = scaled(upright, by: factor)
            size = deviceSize(forScreen: screen, fallback: scaled(screenSize, by: factor))
        }
        chromeView.setScreenSize(screen)
        // Full screen owns the window's size, and a locked ratio collapses it, so only the shape
        // the chrome fits itself into changes there. Turning the device in full screen used to
        // resize the window and lock the new ratio, which fought the transition.
        // Clamped as well as scaled: the body's margins round, and a window a point over still
        // hangs off the bottom of the display. The chrome fits the device to whatever bounds it is
        // given, so losing that point costs nothing.
        let wholeContent = PresentationLayout.contentSize(forDevice: size)
        let content = visible == .zero ? wholeContent : CGSize(
            width: min(wholeContent.width, visible.width),
            height: min(wholeContent.height, visible.height)
        )
        if window.styleMask.contains(.fullScreen) {
            presentationView.needsLayout = true
            chromeView.needsDisplay = true
        } else {
            // The ratio has to be relaxed before the size is set. AppKit applies the old one to
            // the new size otherwise, which shrank the window to the bare screen's shape when the
            // body came back.
            window.contentResizeIncrements = NSSize(width: 1, height: 1)
            window.setContentSize(content)
            window.contentAspectRatio = content
            keepOnScreen()
        }

        // The content already covers the whole window, so nothing more is reserved for a title bar.
        let fits = factor >= 1
        return fits ? .applied(size) : .largerThanScreen(size)
    }

    private func scaled(_ size: CGSize, by factor: CGFloat) -> CGSize {
        CGSize(width: size.width * factor, height: size.height * factor)
    }

    private func deviceSize(forScreen screen: CGSize, fallback: CGSize) -> CGSize {
        guard chromeView.hasChrome, let chrome else { return fallback }
        return ChromeGeometry.contentSize(screen: screen, chrome: chrome, orientation: orientation)
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
        // The recording dot is a title bar accessory rather than part of the title, so the name
        // stays steady while it pulses.
        var title = base
        if showsLatency, let reading = latency.reading {
            title += String(
                format: "  %.0f ms (avg %.0f over %d)",
                reading.lastMilliseconds, reading.averageMilliseconds, reading.sampleCount
            )
        }
        window.title = title
    }

    public func setRecordingIndicatorVisible(_ visible: Bool) {
        recordingIndicator.setVisible(visible, on: window)
        updateTitle()
        toolbar?.setRecording(visible)
    }

    /// Turns the window and the image to match the device. The device itself is turned by the
    /// adapter; this is the half the host owns.
    public func setOrientation(_ orientation: DeviceOrientation) {
        self.orientation = orientation
        renderer.setOrientation(orientation)
        chromeView.setOrientation(orientation)
        // The scale mode settles the window's shape and its ratio, including the body, and leaves
        // both alone in full screen.
        applyScaleMode(scaleMode)
        screenView.needsDisplay = true
    }

    public var currentOrientation: DeviceOrientation { orientation }

    /// Whether the device has a real Home button, which decides between pressing it and swiping up
    /// from the bottom edge.
    public var hasHomeButton: Bool {
        chrome?.buttons.contains { $0.name == "home" } ?? false
    }

    /// Puts the buttons above this device. Each window drives its own device, so the actions are
    /// supplied per window rather than shared with the menu bar.
    public func setToolbarActions(_ actions: DeviceToolbarActions) {
        guard let window else { return }
        let toolbar = DeviceToolbar(actions: actions)
        toolbar.install(on: window)
        self.toolbar = toolbar
        // A unified toolbar makes the title bar taller, which would otherwise come out of the
        // device's own height, so the window is sized again now that it is there.
        applyScaleMode(scaleMode)
    }

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
        presentationView.setFullScreen(true)
    }

    public func windowDidExitFullScreen(_ notification: Notification) {
        (window as? DeviceWindow)?.constrainsToScreen = false
        presentationView.setFullScreen(false)
        // The device may have been turned while full screen, where the window is not resized, so
        // the shape it comes back to is whatever the current orientation asks for.
        applyScaleMode(scaleMode)
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

            if touchPhase == .began {
                self.latency.clickSent()
                self.dragEdge = style == .single ? .beginning(at: primary) : .none
            }
            let event = TouchEvent(phase: touchPhase, points: points, edge: self.dragEdge)
            if touchPhase == .ended { self.dragEdge = .none }
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
