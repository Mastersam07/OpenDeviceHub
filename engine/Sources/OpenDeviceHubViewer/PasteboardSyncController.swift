import AppKit
import OpenDeviceHubEngine

/// Holds one clipboard connection per open device.
///
/// The connection is what the automatic syncing runs on, so these are kept for as long as the device
/// is on screen rather than opened per action. A device whose connection cannot be opened is skipped:
/// a clipboard that will not sync is not a reason to refuse to show a device.
@MainActor
public final class PasteboardSyncController {
    private let open: (String) throws -> any PasteboardSession
    private let devices: () -> [String]
    private let frontmost: () -> String?
    private var sessions: [String: any PasteboardSession] = [:]

    public private(set) var isAutomatic: Bool

    public init(
        isAutomatic: Bool,
        devices: @escaping () -> [String],
        frontmost: @escaping () -> String?,
        open: @escaping (String) throws -> any PasteboardSession
    ) {
        self.isAutomatic = isAutomatic
        self.devices = devices
        self.frontmost = frontmost
        self.open = open
    }

    public func setAutomatic(_ enabled: Bool) {
        isAutomatic = enabled
        for udid in devices() {
            session(for: udid)?.setAutomatic(enabled)
        }
    }

    /// Starts syncing a device that has just appeared, if the sync is on.
    public func adopt(_ udid: String) {
        guard isAutomatic else { return }
        session(for: udid)?.setAutomatic(true)
    }

    public func forget(_ udid: String) {
        sessions[udid]?.setAutomatic(false)
        sessions[udid] = nil
    }

    /// The Mac's clipboard to every open device, since a copy is not device specific.
    public func send() {
        for udid in devices() {
            session(for: udid)?.send()
        }
    }

    /// The frontmost device's clipboard to the Mac. Every device at once would leave whichever
    /// happened to be last, which is not a decision to make on the user's behalf.
    public func get() {
        guard let udid = frontmost() else { return }
        session(for: udid)?.get()
    }

    /// Called when the app stops being frontmost, which is when a copy made inside a device is about
    /// to be pasted somewhere else. The automatic sync only carries the Mac's copies to the device,
    /// so without this a device copy would never arrive.
    public func reconcileOnResignActive() {
        guard isAutomatic, let udid = frontmost() else { return }
        session(for: udid)?.reconcile()
    }

    private func session(for udid: String) -> (any PasteboardSession)? {
        if let existing = sessions[udid] { return existing }
        guard let opened = try? open(udid) else { return nil }
        sessions[udid] = opened
        return opened
    }
}
