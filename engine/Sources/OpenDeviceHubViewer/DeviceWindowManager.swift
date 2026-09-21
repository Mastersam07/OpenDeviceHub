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
            fpsLabel: showFPS ? device.name : nil
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

    public func closeAll() {
        for udid in controllers.keys {
            close(udid)
        }
    }
}
