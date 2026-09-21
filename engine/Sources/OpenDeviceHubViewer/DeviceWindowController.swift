import AppKit
import MetalKit
import OpenDeviceHubEngine

@MainActor
public final class DeviceWindowController: NSWindowController {
    private let session: any DisplaySession
    private let renderer: FrameRenderer
    private let screenView: DeviceScreenView
    private var frameTask: Task<Void, Never>?

    public var onClick: ((CGPoint) -> Void)?

    public init(title: String, session: any DisplaySession, reportFPS: Bool) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ViewerError.metalUnavailable("no system default device")
        }
        self.session = session
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

        if reportFPS {
            installFPSCounter()
        }
        startConsumingFrames()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    public func stop() {
        frameTask?.cancel()
        frameTask = nil
        session.close()
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

    private func installFPSCounter() {
        let counter = FPSCounter()
        renderer.onFrameDrawn = { counter.record() }
    }
}

private final class FPSCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var windowStart = Date()

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
        print(String(format: "%.1f fps", fps))
    }
}
