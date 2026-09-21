import AppKit
import OpenDeviceHubEngine

/// Owns one window per device. Windows are cascaded rather than centred so that several devices
/// opened at once do not land on top of each other.
@MainActor
public final class DeviceWindowManager {
    private var controllers: [String: DeviceWindowController] = [:]
    private var lastWindowOrigin: NSPoint?

    public init() {}

    public var openCount: Int { controllers.count }

    public func isOpen(_ udid: String) -> Bool {
        controllers[udid] != nil
    }

    @discardableResult
    public func open(
        device: DeviceInfo,
        session: any DisplaySession,
        input: (any InputSession)?,
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
            fpsLabel: showFPS ? device.name : nil
        )
        controller.onClose = { [weak self] udid in
            self?.controllers.removeValue(forKey: udid)
        }
        controllers[device.udid] = controller

        if let window = controller.window {
            lastWindowOrigin = window.cascadeTopLeft(from: lastWindowOrigin ?? .zero)
            window.makeKeyAndOrderFront(nil)
        }
        return controller
    }

    public func close(_ udid: String) {
        guard let controller = controllers.removeValue(forKey: udid) else { return }
        controller.onClose = nil
        controller.stop()
        controller.window?.close()
    }

    public func closeAll() {
        for udid in controllers.keys {
            close(udid)
        }
    }
}
