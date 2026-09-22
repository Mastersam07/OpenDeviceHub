import Foundation

public struct DeviceStateChange: Sendable, Hashable {
    public let udid: String
    public let state: DeviceState
    public let previousState: DeviceState

    public init(udid: String, state: DeviceState, previousState: DeviceState) {
        self.udid = udid
        self.state = state
        self.previousState = previousState
    }
}

/// A live feed of device state changes, however the change was caused: by us, by simctl, by Xcode
/// or by Device Hub. Nothing here polls.
public protocol DeviceNotifier: AnyObject, Sendable {
    var changes: AsyncStream<DeviceStateChange> { get }
    func close()
}

/// Reads the dictionary CoreSimulator hands to a `SimDeviceNotifier` handler. Split out from the
/// notifier so the shape can be tested without a simulator, and written to survive anything: the
/// payload is whatever the other process sent, including nil.
enum DeviceStateNotification {
    static let name = "device_state"

    static func change(from payload: Any?, udidOf: (Any) -> String?) -> DeviceStateChange? {
        guard let payload,
              let notification = payload as? [AnyHashable: Any],
              notification["notification"] as? String == name,
              let device = notification["device"],
              let udid = udidOf(device),
              let newState = notification["new_state"] as? NSNumber else { return nil }

        return DeviceStateChange(
            udid: udid,
            state: state(from: newState),
            previousState: (notification["prev_state"] as? NSNumber).map(state(from:)) ?? .unknown
        )
    }

    /// The payload carries the number alone, so a value outside the known four is `unknown` rather
    /// than resolved against a state string the way a device listing can.
    private static func state(from number: NSNumber) -> DeviceState {
        DeviceState.from(state: number.uintValue, stateString: "")
    }
}
