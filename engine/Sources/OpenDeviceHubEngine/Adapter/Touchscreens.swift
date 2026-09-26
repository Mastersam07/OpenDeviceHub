import Foundation
import XPC

/// One of the guest's touchscreens, and the screen it belongs to.
///
/// A foldable has two, and a touch has to be addressed to the one under the panel being shown. The
/// guest's universal HID service lists its services with, for each touchscreen, the display it is
/// attached to, which is the join a window needs between the display report and a digitizer target.
public struct Touchscreen: Sendable, Hashable {
    /// The value an `IndigoDigitizerEvent` names in `target`.
    public let target: Int
    /// The `uniqueId` of the display this touchscreen sits under, when the guest says.
    public let displayUniqueID: String?

    static let digitizerUsagePage = 0x0D
    static let touchscreenUsage = 0x04
    static let maximumServices = 256

    /// The request is the HID service's own dialect rather than a CoreDevice action.
    static func request() -> xpc_object_t {
        let payload = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(payload, "connectedServices", xpc_dictionary_create(nil, nil, 0))
        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_bool(message, "isBarrier", false)
        xpc_dictionary_set_value(message, "payload", payload)
        return message
    }

    /// The touchscreens among the guest's HID services. Any other service is skipped; a touchscreen
    /// whose service identity does not carry an explicit target is refused, since a wrong target
    /// puts every touch on the wrong panel.
    static func parse(_ reply: xpc_object_t) throws -> [Touchscreen] {
        guard let services = XPCValue.array(reply, "connectedServices") else {
            throw EngineError.privateCall(symbol: "connectedServices", message: "the device listed no HID services")
        }
        guard services.count <= maximumServices else {
            throw EngineError.privateCall(symbol: "connectedServices", message: "the device listed too many HID services")
        }
        var touchscreens: [Touchscreen] = []
        for service in services {
            guard Int(XPCValue.number(service, "PrimaryUsagePage") ?? -1) == digitizerUsagePage,
                  Int(XPCValue.number(service, "PrimaryUsage") ?? -1) == touchscreenUsage else { continue }
            guard let identity = XPCValue.number(service, "_ServiceID") else {
                throw EngineError.privateCall(symbol: "connectedServices", message: "a touchscreen has no service identity")
            }
            let serviceID = UInt64(identity)
            // The explicit target lives in the low byte of a 0x1xx identity.
            guard serviceID & ~0xFF == 0x100, serviceID & 0xFF != 0 else {
                throw EngineError.privateCall(symbol: "connectedServices", message: "a touchscreen has no explicit target")
            }
            touchscreens.append(Touchscreen(
                target: Int(serviceID & 0xFF),
                displayUniqueID: XPCValue.string(service, "displayUUID")
            ))
        }
        return touchscreens
    }
}
