import AppKit
import Foundation
import OpenDeviceHubPrivate

/// Keeps a device's clipboard and the Mac's in step.
///
/// One connection per device, held for as long as the device is shown. The automatic syncing runs on
/// the connection, so letting go of it stops the syncing.
///
/// Only one of the two directions is automatic. Measured on Xcode 27 (27A266a) against a booted
/// device, reading the other side back with `simctl pbpaste` and `pbcopy` each time:
///
/// - `enableRemoteAutosync` carries the Mac's copies to the device on its own, but only while the
///   run loop turns, which an app does and a test process has to be made to do.
/// - Nothing carries the device's copies back, with or without a delegate. `pull` is the only way,
///   and it has to be asked for.
public final class PasteboardBridge: PasteboardSession, @unchecked Sendable {
    private let interface: any ODHSimPasteboardInterface
    private let pasteboard: NSPasteboard
    private let lock = NSLock()
    private var isSyncing = false
    private var lastSeenChangeCount: Int

    /// The service the guest publishes. Asked of the listener class rather than written down here, so
    /// a rename in a later Xcode is followed rather than guessed at.
    static func serviceName() -> String? {
        guard let listener = NSClassFromString("SimPasteboardPlus.SimPasteboardInterfaceListener")
            ?? NSClassFromString("SimPasteboardInterfaceListener") else {
            return nil
        }
        let selector = NSSelectorFromString("machServiceName")
        guard (listener as AnyObject).responds(to: selector) else { return nil }
        return (listener as AnyObject).perform(selector)?.takeUnretainedValue() as? String
    }

    init(port: UInt32, pasteboard: NSPasteboard = .general) throws {
        self.pasteboard = pasteboard
        self.lastSeenChangeCount = pasteboard.changeCount

        guard let interfaceClass = NSClassFromString("SimPasteboardPlus.SimPasteboardInterface")
            ?? NSClassFromString("SimPasteboardInterface") else {
            throw EngineError.symbolNotFound(
                name: "SimPasteboardInterface",
                framework: PrivateFramework.simPasteboardPlus.rawValue
            )
        }
        let selector = NSSelectorFromString(
            "initWithConnectingToPort:managingPasteboard:delegate:delegateQueue:"
        )
        guard let allocated = (interfaceClass as AnyObject).perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue(),
              allocated.responds(to: selector) else {
            throw EngineError.symbolNotFound(
                name: "-[SimPasteboardInterface \(NSStringFromSelector(selector))]",
                framework: PrivateFramework.simPasteboardPlus.rawValue
            )
        }
        // Four arguments, so `perform` cannot be used. The signature was read off the runtime:
        // `@44@0:8I16@20@28@36`, an unsigned int port then three objects. The result comes back
        // unmanaged because an initialiser hands over ownership, which `alloc` above does not.
        //
        // No delegate and no queue. Both are optional, and the delegate only reports that the
        // interface became active and that the sync state changed, neither of which says the device's
        // clipboard moved. A delegate would also commit us to passing a dispatch queue here: an
        // `OperationQueue` crashes when the interface dispatches to it.
        typealias Initialiser = @convention(c) (
            AnyObject, Selector, UInt32, AnyObject?, AnyObject?, AnyObject?
        ) -> Unmanaged<AnyObject>?
        let imp = unsafeBitCast(allocated.method(for: selector), to: Initialiser.self)
        guard let made = imp(allocated, selector, port, pasteboard, nil, nil) else {
            throw EngineError.privateCall(
                symbol: "initWithConnectingToPort:managingPasteboard:delegate:delegateQueue:",
                message: "the pasteboard interface could not connect to the device"
            )
        }
        // A Swift class does not declare conformance to an Objective-C protocol written here, so a
        // conditional cast would fail even though every selector is present.
        interface = unsafeBitCast(
            made.takeRetainedValue(),
            to: (any ODHSimPasteboardInterface).self
        )
    }

    /// Whether the Mac's copies are reaching the device on their own.
    public var isAutomatic: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSyncing
    }

    public func setAutomatic(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard isSyncing != enabled else { return }
        isSyncing = enabled
        if enabled {
            interface.enableRemoteAutosync()
        } else {
            interface.disableRemoteAutosync()
        }
        lastSeenChangeCount = pasteboard.changeCount
    }

    /// The Mac's clipboard to the device.
    public func send() {
        lock.lock()
        defer { lock.unlock() }
        interface.push()
        lastSeenChangeCount = pasteboard.changeCount
    }

    /// The device's clipboard to the Mac.
    public func get() {
        lock.lock()
        defer { lock.unlock() }
        interface.pull()
        lastSeenChangeCount = pasteboard.changeCount
    }

    /// Brings the device's clipboard back to the Mac without losing a copy made on the Mac.
    ///
    /// Called when the app stops being frontmost, which is when a copy made inside the device is
    /// about to be pasted somewhere else.
    ///
    /// A Mac copy that has not been carried over yet is pushed first, so the pull that follows cannot
    /// overwrite it: after the push both sides hold it, and the pull is then a no-op. Whichever side
    /// was copied on last wins, in either order. The push cannot be skipped by watching the Mac's
    /// change count alone, because the automatic sync pushes inside the private interface, where
    /// there is nothing to observe.
    public func reconcile() {
        lock.lock()
        defer { lock.unlock() }
        if pasteboard.changeCount != lastSeenChangeCount {
            interface.push()
        }
        interface.pull()
        lastSeenChangeCount = pasteboard.changeCount
    }
}
