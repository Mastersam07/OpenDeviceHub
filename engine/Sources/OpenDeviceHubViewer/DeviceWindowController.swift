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
    private var frameTask: Task<Void, Never>?

    private let input: (any InputSession)?
    private var isStopped = false
    private var scaleMode: ScaleMode

    public init(
        udid: String,
        title: String,
        session: any DisplaySession,
        input: (any InputSession)?,
        scaleMode: ScaleMode,
        fpsLabel: String?
    ) throws {
        self.udid = udid
        self.scaleMode = scaleMode
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ViewerError.metalUnavailable("no system default device")
        }
        self.session = session
        self.input = input
        screenView = DeviceScreenView(device: device)
        renderer = try FrameRenderer(device: device, pixelFormat: screenView.colorPixelFormat)
        screenView.delegate = renderer

        let contentSize = DeviceGeometry.pointSize(
            pixelSize: session.pixelSize,
            pointScale: session.pointScale
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = screenView
        window.contentAspectRatio = contentSize
        window.center()
        super.init(window: window)
        window.delegate = self
        applyScaleMode(scaleMode)

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
    public func applyScaleMode(_ mode: ScaleMode) {
        scaleMode = mode
        guard let window else { return }
        let device = DeviceMetrics(
            pixelSize: session.pixelSize,
            pointScale: session.pointScale,
            pixelsPerInch: session.pixelsPerInch
        )
        guard let size = DeviceGeometry.contentSize(
            for: mode,
            device: device,
            screen: ScaleMode.screenMetrics(for: window.screen ?? NSScreen.main)
        ) else { return }
        window.setContentSize(size)
    }

    public var currentScaleMode: ScaleMode { scaleMode }

    public func windowWillClose(_ notification: Notification) {
        stop()
        onClose?(udid)
    }

    private func installClickToTap() {
        let pixelSize = session.pixelSize
        screenView.onContact = { [weak self] point, phase in
            guard let self, let input else { return }
            guard let normalized = CoordinateMapper.normalize(
                viewPoint: point,
                viewSize: screenView.bounds.size,
                pixelSize: pixelSize
            ) else { return }

            let event = TouchEvent(
                phase: phase == .began ? .began : .ended,
                points: [normalized]
            )
            Task { try? await input.touch(event) }
        }
    }

    private func startConsumingFrames() {
        let renderer = renderer
        let screenView = screenView
        frameTask = Task { [frames = session.frames] in
            for await frame in frames {
                if Task.isCancelled { return }
                renderer.accept(frame)
                await MainActor.run {
                    screenView.needsDisplay = true
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
