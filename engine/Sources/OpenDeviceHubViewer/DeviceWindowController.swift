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
    private let hasFoldModes: Bool
    private let modelView: DuoModelView?
    /// Where the hinge has got to, so a pinch carries on from where the last one left off.
    private var foldAngle: Double = 0

    /// Whether this window has the fold controls, which only a foldable does.
    public var foldsAtHinge: Bool { hasFoldModes }

    /// Reports the angle the user asked for, from the positions in the bar or from a pinch.
    public var onHingeAngle: ((Double) -> Void)?

    /// Moves the fold controls to an angle that came from somewhere other than this window.
    public func showHingeAngle(_ degrees: Double) {
        foldAngle = degrees
        controlBar.showFoldAngle(degrees)
        modelView?.setHingeAngle(degrees)
    }
    private let presentationView: DevicePresentationView
    private var chrome: DeviceChrome?
    private var toolbar: DeviceToolbar?
    private var frameTask: Task<Void, Never>?
    private var overlay: ShutdownOverlayView?
    /// Called when the window's Reboot button is pressed. The owner boots the device; the window
    /// comes back on its own once the notifier says it is up.
    public var onReboot: (() -> Void)?

    private var input: (any InputSession)?

    /// The session this window drives its device with, aimed at the panel it is showing. Actions
    /// from the menus and the toolbar use it rather than opening their own, which on a foldable
    /// would be aimed at the wrong screen, and which used to mint a fresh connection per press.
    public var inputSession: (any InputSession)? { input }
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
    private let deviceName: String
    private var pendingSend: Task<Void, Never>?
    private var bezelEnabled: Bool
    private let frameStore: WindowFrameStore
    /// How far this window's panel is built round in its housing, which the renderer may or may not
    /// be undoing but a gesture always has to account for.
    private var panelBuildAngle: Int

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
        chrome: DeviceChrome?,
        foldsAtHinge: Bool = false,
        panelNativeRotation: Int = 0
    ) throws {
        self.frameStore = frameStore
        self.deviceName = deviceName
        panelBuildAngle = panelNativeRotation
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
        hasFoldModes = foldsAtHinge
        // Only a foldable, and only where the installed Xcode ships the model. Anything else stays
        // on the flat renderer, which is what every other device wants anyway.
        // The cover is the smaller panel, so the shape of what the session opened says which face
        // the guest is drawing to and therefore which one the picture goes on.
        let onTheCover = max(session.pixelSize.width, session.pixelSize.height) < 2500
        modelView = foldsAtHinge
            ? DuoModelView(
                metalDevice: device,
                showingCover: onTheCover,
                nativeRotation: panelNativeRotation
            )
            : nil
        presentationView = DevicePresentationView(
            bar: controlBar,
            chrome: chromeView,
            model: modelView
        )
        self.chrome = chrome

        // The model draws its own body, so the bezel's measurements do not shape its window.
        let contentSize = Self.contentSize(
            for: session,
            chrome: bezelEnabled && modelView == nil ? chrome : nil,
            buildAngle: panelNativeRotation,
            scaleMode: scaleMode,
            deviceName: deviceName
        )
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
        // No locked aspect ratio: the bar stops at its minimum width while the device carries on
        // shrinking, which it cannot do if the window's shape is pinned to the device's.
        window.minSize = PresentationLayout.minimumWindowSize
        window.center()
        window.collectionBehavior.insert(.fullScreenPrimary)
        super.init(window: window)
        window.delegate = self
        if foldsAtHinge {
            controlBar.addFoldModes()
            controlBar.onFoldMode = { [weak self] mode in
                guard let self else { return }
                foldAngle = mode.angle
                modelView?.setHingeAngle(mode.angle)
                onHingeAngle?(mode.angle)
            }
            screenView.onPinchFold = { [weak self] change in
                guard let self else { return }
                foldAngle = min(max(foldAngle + change, 0), 180)
                controlBar.showFoldAngle(foldAngle)
                modelView?.setHingeAngle(foldAngle)
                onHingeAngle?(foldAngle)
            }
        }
        chromeView.setScreenSize(screenPointSize)
        chromeView.setChrome(bezelEnabled ? chrome : nil)
        installChromeButtons()
        applyScaleMode(scaleMode)
        setKeepOnTop(keepOnTop)

        // A remembered frame wins over the default placement, but not over an explicit scale mode,
        // which has already sized the window by this point.
        if let remembered = frameStore.frame(for: frameKey) {
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

    /// The screen this window is showing, in points rather than pixels.
    private var screenPointSize: CGSize {
        DeviceGeometry.pointSize(pixelSize: session.pixelSize, pointScale: session.pointScale)
    }

    /// The size a window showing this screen opens at. Fit is the mode that lets any size work, so
    /// it takes a size that leaves room for other windows rather than whatever the device measures.
    private static func contentSize(
        for session: any DisplaySession,
        chrome: DeviceChrome?,
        buildAngle: Int,
        scaleMode: ScaleMode,
        deviceName: String
    ) -> CGSize {
        // Sized from the picture as it is shown, not as the framebuffer stores it. A foldable's
        // unfolded panel is stored upright and shown sideways, and a window shaped for the upright
        // framebuffer stood a wide device in a tall frame with the space left over above it.
        let screenSize = Self.shown(.portrait, nativeRotation: buildAngle).displayedSize(
            portraitNative: DeviceGeometry.pointSize(
                pixelSize: session.pixelSize,
                pointScale: session.pointScale
            )
        )
        let deviceSize = chrome.map {
            ChromeGeometry.contentSize(screen: screenSize, chrome: $0, orientation: .portrait)
        } ?? screenSize
        guard scaleMode == .fit else { return PresentationLayout.contentSize(forDevice: deviceSize) }
        return PresentationLayout.defaultContentSize(
            forDevice: deviceSize,
            isTablet: deviceName.contains("iPad"),
            available: (NSScreen.main?.visibleFrame.size) ?? CGSize(width: 1512, height: 900)
        )
    }

    /// Points this window at another of the device's screens, which is how a foldable follows its
    /// guest between the cover and the unfolded panel. The window is kept: building a new one blinks,
    /// and for that moment the application has no window at all.
    public func showPanel(
        session: any DisplaySession,
        input: (any InputSession)?,
        chrome: DeviceChrome?,
        nativeRotation: Int,
        showingCover: Bool
    ) {
        self.chrome = chrome
        chromeView.setChrome(bezelEnabled ? chrome : nil)
        installChromeButtons()
        panelBuildAngle = nativeRotation
        if let modelView {
            modelView.setShowingCover(showingCover, nativeRotation: nativeRotation)
        } else {
            // Only the flat renderer turns the picture by the panel's build angle. The model puts it
            // on the texture instead, and turning it twice lays the unfolded screen on its side.
            self.nativeRotation = nativeRotation
        }
        reattach(session: session, input: input)
        chromeView.setScreenSize(screenPointSize)
        if scaleMode == .fit, let remembered = frameStore.frame(for: frameKey), let window {
            window.setFrame(remembered, display: true)
            keepOnScreen()
        } else {
            resizeForCurrentScreen()
        }
    }

    /// The two panels of a foldable are different shapes, so a window built for one leaves the other
    /// adrift in it. Fit holds whatever size the window has, so following the guest resizes it the
    /// way opening on that panel would have; every other mode has already been sized by the scale.
    private func resizeForCurrentScreen() {
        guard scaleMode == .fit, let window else { return }
        let wanted = Self.contentSize(
            for: session,
            chrome: bezelEnabled && modelView == nil ? chrome : nil,
            buildAngle: panelBuildAngle,
            scaleMode: scaleMode,
            deviceName: deviceName
        )
        let outer = window.frameRect(forContentRect: CGRect(origin: .zero, size: wanted)).size
        var frame = window.frame
        // The top edge stays put, so the window grows and shrinks downwards rather than jumping.
        frame.origin.y += frame.height - outer.height
        frame.size = outer
        window.setFrame(frame, display: true, animate: false)
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

    /// Every send goes through here so a failure is seen. A send used to be `try?`, which made a
    /// dead session look exactly like a gesture the guest ignored.
    /// Sends are chained rather than started side by side. A contact going down and coming up are
    /// two messages, and on their own tasks the second can overtake the first, which the guest reads
    /// as a finger that lifted before it landed: a tap does nothing at all, while a swipe, being
    /// many messages, still looks like a swipe.
    private func send(_ work: @escaping @Sendable (any InputSession) async throws -> Void) {
        guard let input else { return }
        let previous = pendingSend
        pendingSend = Task { [weak self] in
            await previous?.value
            do {
                try await work(input)
            } catch {
                guard InputFailure.endsTheSession(error) else { return }
                await MainActor.run { self?.inputFailed(error) }
            }
        }
    }

    private func inputFailed(_ error: any Error) {
        guard !isStopped, !isDetached else { return }
        detach(reason: .failed(InputFailure.message(for: error)))
        onSessionLost?()
    }

    /// Called when the window has given up on its sessions, so the owner can offer a way back.
    public var onSessionLost: (() -> Void)?

    private func installChromeButtons() {
        chromeView.onButton = { [weak self] button, phase in
            guard let self else { return }
            send { try await $0.button(button, phase: phase) }
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
    /// Whether the Mac's keystrokes reach this device.
    public var sendsKeyboardInput: Bool {
        get { screenView.sendsKeyboardInput }
        set { screenView.sendsKeyboardInput = newValue }
    }

    public func screenshotPNG() -> Data? {
        // A foldable is drawn as the device itself, so a picture of it is the picture. Compositing
        // the flat body around the framebuffer instead puts a phone shaped bezel around a landscape
        // panel, which is what a Duo screenshot used to be.
        if let modelView, chromeView.hasChrome, let png = modelView.screenshotPNG() {
            return png
        }
        guard let surface = renderer.currentSurface else { return nil }
        // With the body shown, a screenshot means the device, not just its screen. Without it, the
        // screen is the whole picture.
        guard chromeView.hasChrome else { return ScreenshotWriter.pngData(from: surface) }
        return ScreenshotWriter.pngData(
            from: surface,
            inside: chromeView,
            screenRect: chromeView.screenRect
        ) ?? ScreenshotWriter.pngData(from: surface)
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
        updateTitle()
        toolbar?.setRecording(visible)
    }

    /// Turns the window and the image to match the device. The device itself is turned by the
    /// adapter; this is the half the host owns.
    /// How far this panel is built round in its housing, added to whatever the guest is doing. A
    /// foldable's unfolded panel is sideways, so its picture is landscape while the guest thinks it
    /// is upright.
    public var nativeRotation: Int = 0 {
        didSet { setOrientation(orientation) }
    }

    public func setOrientation(_ orientation: DeviceOrientation) {
        self.orientation = orientation
        let shown = Self.shown(orientation, nativeRotation: nativeRotation)
        renderer.setOrientation(shown)
        chromeView.setOrientation(shown)
        // The model shows the hardware, so it turns by how the device is standing rather than by
        // what the flat renderer would draw.
        modelView?.setOrientation(orientation)
        // The scale mode settles the window's shape and its ratio, including the body, and leaves
        // both alone in full screen.
        applyScaleMode(scaleMode)
        screenView.needsDisplay = true
    }

    public var currentOrientation: DeviceOrientation { orientation }

    /// The size of the screen this window is showing, which changes when it follows its guest to
    /// the device's other panel.
    public var screenPixelSize: CGSize { session.pixelSize }

    /// How far the guest's layout is turned from the framebuffer a touch is addressed in, which a
    /// gesture written in what the window shows has to be converted through.
    public var layoutTurn: DeviceOrientation {
        Self.shown(orientation, nativeRotation: panelBuildAngle)
    }

    /// What to draw, which is the guest's orientation turned by the panel's own build angle.
    nonisolated static func shown(
        _ orientation: DeviceOrientation,
        nativeRotation: Int
    ) -> DeviceOrientation {
        // Subtracted, not added. This project measures an orientation as the clockwise turn applied
        // to the portrait picture, and a panel's native rotation says how far the panel itself is
        // turned the other way, so adding them left the unfolded screen upside down.
        let degrees = ((orientation.degrees - nativeRotation) % 360 + 360) % 360
        return DeviceOrientation.allCases.first { $0.degrees == degrees } ?? orientation
    }

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
        frameStore.save(window.frame, for: frameKey)
    }

    /// What a remembered frame is filed under. A foldable's two panels are different shapes, so each
    /// remembers its own; anything else keeps the plain key it always had.
    private var frameKey: String {
        guard foldsAtHinge else { return udid }
        return "\(udid)/\(Int(session.pixelSize.width))x\(Int(session.pixelSize.height))"
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

        // A foldable is drawn as the model, so a click is hit tested against the posed screen and
        // arrives already in the guest's own coordinates. The panel's own build angle is already in
        // the picture, so nothing is turned again here.
        modelView?.onTouch = { [weak self] point, phase in
            guard let self else { return }
            if phase == .began {
                latency.clickSent()
                dragEdge = .beginning(at: point)
            }
            let event = TouchEvent(phase: phase, points: [point], edge: dragEdge)
            if phase == .ended { dragEdge = .none }
            send { try await $0.touch(event) }
        }

        screenView.onContact = { [weak self] point, phase, style in
            guard let self else { return }
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
                self.dragEdge = style == .single ? .beginning(at: points[0]) : .none
            }
            let event = TouchEvent(phase: touchPhase, points: points, edge: self.dragEdge)
            if touchPhase == .ended { self.dragEdge = .none }
            send { try await $0.touch(event) }
        }

        screenView.onDrop = { [weak self] urls, text in
            guard let self else { return false }
            var actions = DropRouting.actions(for: urls)
            if let text { actions.append(.openURL(text)) }
            guard !actions.isEmpty else { return false }
            return self.perform(actions)
        }

        screenView.onKey = { [weak self] usage, isDown in
            guard let self else { return }
            send { try await $0.key(KeyEvent(phase: isDown ? .down : .up, usage: usage)) }
        }

        screenView.onGesture = { [weak self] phase, spread, angle in
            guard let self else { return }
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
            send { try await $0.touch(TouchEvent(phase: touchPhase, points: contacts)) }
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
                    self?.modelView?.setScreen(frame.surface)
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
