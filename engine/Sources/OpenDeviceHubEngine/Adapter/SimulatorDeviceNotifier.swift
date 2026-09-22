import Foundation
import OpenDeviceHubPrivate

final class SimulatorDeviceNotifier: DeviceNotifier, @unchecked Sendable {
    let changes: AsyncStream<DeviceStateChange>

    private let deviceSet: any ODHSimDeviceSet
    private let handle: UInt
    private let continuation: AsyncStream<DeviceStateChange>.Continuation
    private let lock = NSLock()
    private var isClosed = false

    init(deviceSet: any ODHSimDeviceSet) throws {
        let register = NSSelectorFromString("registerNotificationHandlerOnQueue:handler:")
        let unregister = NSSelectorFromString("unregisterNotificationHandler:error:")
        guard (deviceSet as AnyObject).responds(to: register),
              (deviceSet as AnyObject).responds(to: unregister) else {
            throw EngineError.symbolNotFound(
                name: "-[SimDeviceSet registerNotificationHandlerOnQueue:handler:]",
                framework: PrivateFramework.coreSimulator.rawValue
            )
        }

        self.deviceSet = deviceSet
        var escapingContinuation: AsyncStream<DeviceStateChange>.Continuation!
        changes = AsyncStream(bufferingPolicy: .unbounded) { escapingContinuation = $0 }
        continuation = escapingContinuation

        let queue = DispatchQueue(label: "\(Brand.identifierPrefix).device-notifier")
        handle = deviceSet.registerNotificationHandler(on: queue) { [continuation] payload in
            guard let change = DeviceStateNotification.change(from: payload, udidOf: Self.udid) else {
                return
            }
            continuation.yield(change)
        }
    }

    func close() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        lock.unlock()

        try? deviceSet.unregisterNotificationHandler(handle)
        continuation.finish()
    }

    deinit {
        close()
    }

    /// The device in the payload is a `SimDevice` proxy, and a device that has just gone answers nil
    /// for everything, so a change it cannot be named for is dropped.
    private static func udid(of device: Any) -> String? {
        unsafeBitCast(device as AnyObject, to: (any ODHSimDevice).self).udid?.uuidString
    }
}
