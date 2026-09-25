import Foundation
import XPC

/// Folding a foldable, and turning one.
///
/// A foldable does not take an ordinary rotation: its hinge and its orientation are both published
/// by the guest's virtual machine provider, which overwrites anything sent the usual way. Both are
/// driven here instead, as vendor defined HID reports over the simulator's own input service.
///
/// The report is a serialised dictionary naming a provider, one of its controls, and a value. The
/// usage page and usage below identify it as that kind of report; they are not ours to choose.
public final class FoldableControl: @unchecked Sendable {
    /// Angles the guest treats as meaningful. Closed is flat shut, open is flat open.
    public static let closedAngle: Double = 0
    public static let openAngle: Double = 180

    /// Below this the guest is drawing to the cover, above it to the unfolded panel. The guest moves
    /// the picture itself; this is only where a window should follow it.
    public static let handoffAngle: Double = 15

    static let serviceName = "com.apple.coredevice.feature.remote.hid.vendordefined"
    /// Opened and turned on alongside the vendor service. The guest's input stack comes up as a
    /// whole, and the vendor reports are ignored until it has.
    static let digitizerServiceName = "com.apple.coredevice.feature.remote.hid.digitizer"
    private static let provider = "com.apple.Virtualization.VirtualMachines"
    private static let usagePage: UInt64 = 0xff61
    private static let usage: UInt64 = 0x5b

    private let connection: xpc_connection_t
    private let digitizer: xpc_connection_t
    private let lock = NSLock()
    private var isActivated = false

    init(port: mach_port_t, digitizerPort: mach_port_t) throws {
        // These three live in libxpc and are not declared anywhere public, so they are looked up in
        // the running process rather than linked.
        typealias MakeEndpoint = @convention(c) (mach_port_t, UInt64, UInt64) -> xpc_object_t?
        typealias MakeConnection = @convention(c) (xpc_object_t) -> xpc_connection_t?
        typealias EnableGuestToHost = @convention(c) (xpc_connection_t) -> Void

        guard let image = dlopen(nil, RTLD_NOW),
              let endpointSymbol = dlsym(image, "xpc_endpoint_create_mach_port_4sim"),
              let connectionSymbol = dlsym(image, "xpc_connection_create_from_endpoint"),
              let enableSymbol = dlsym(image, "xpc_connection_enable_sim2host_4sim") else {
            throw EngineError.symbolNotFound(
                name: "xpc_endpoint_create_mach_port_4sim",
                framework: "libxpc"
            )
        }
        func open(_ port: mach_port_t) throws -> xpc_connection_t {
            guard let endpoint = unsafeBitCast(endpointSymbol, to: MakeEndpoint.self)(port, 0, 0),
                  let connection = unsafeBitCast(connectionSymbol, to: MakeConnection.self)(endpoint) else {
                throw EngineError.privateCall(
                    symbol: "xpc_connection_create_from_endpoint",
                    message: "the device's input service could not be connected to"
                )
            }
            unsafeBitCast(enableSymbol, to: EnableGuestToHost.self)(connection)
            xpc_connection_set_target_queue(connection, .global(qos: .userInteractive))
            xpc_connection_set_event_handler(connection) { _ in }
            xpc_connection_resume(connection)
            return connection
        }

        connection = try open(port)
        digitizer = try open(digitizerPort)
    }

    deinit {
        xpc_connection_cancel(connection)
        xpc_connection_cancel(digitizer)
    }

    /// The service ignores reports until the feature has been turned on, once per connection.
    public func activate() async throws {
        guard !hasActivated else { return }
        try await turnOn(digitizer, feature: Self.digitizerServiceName)
        try await turnOn(connection, feature: Self.serviceName)
        // The guest needs a moment after the features come up before it acts on a report.
        try? await Task.sleep(for: .milliseconds(200))
        markActivated()
    }

    private func turnOn(_ connection: xpc_connection_t, feature: String) async throws {
        let payload = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(payload, "usageCode", 0)
        xpc_dictionary_set_uint64(payload, "state", 2)

        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(message, "messageType", "IndigoKeyboardButtonEvent")
        xpc_dictionary_set_bool(message, "isBarrier", true)
        xpc_dictionary_set_string(message, "featureIdentifier", feature)
        xpc_dictionary_set_value(message, "payload", payload)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = SingleReply(continuation)
            xpc_connection_send_message_with_reply(connection, message, .global(qos: .userInitiated)) { reply in
                if xpc_get_type(reply) == XPC_TYPE_ERROR {
                    once.finish(.failure(EngineError.privateCall(
                        symbol: "IndigoKeyboardButtonEvent",
                        message: "the device refused to turn on \(feature)"
                    )))
                } else {
                    once.finish(.success(()))
                }
            }
            // A guest that never answers would otherwise hang the caller for good.
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                once.finish(.failure(EngineError.privateCall(
                    symbol: "IndigoKeyboardButtonEvent",
                    message: "the device did not answer within five seconds"
                )))
            }
        }
    }

    // Swift 6 will not let a lock be taken directly in an async function, so the two places that
    // touch this flag during activation go through these.
    private var hasActivated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isActivated
    }

    private func markActivated() {
        lock.lock()
        defer { lock.unlock() }
        isActivated = true
    }

    /// Folds the device, in degrees, where 0 is shut and 180 is flat open.
    public func setHingeAngle(_ degrees: Double) throws {
        let clamped = min(max(degrees, Self.closedAngle), Self.openAngle)
        try send(source: "hinge-slider-control", type: "range", value: clamped as NSNumber)
    }

    /// Turns the device. An ordinary rotation does not stick on a foldable, because the same
    /// provider republishes orientation and overwrites it.
    public func setOrientation(_ orientation: DeviceOrientation) throws {
        // Named by quarter turns rather than by the words left and right, which mean opposite things
        // depending on whether the device or the picture is being described.
        let byQuarterTurn = ["portrait", "landscape-right", "pud", "landscape-left"]
        let index = ((orientation.degrees / 90) % 4 + 4) % 4
        try send(source: "orientation-picker-control", type: "enum", value: byQuarterTurn[index] as NSString)
    }

    private func send(source: String, type: String, value: Any) throws {
        guard let body = Self.serialize(source: source, type: type, value: value) else {
            throw EngineError.privateCall(
                symbol: "IOCFSerialize",
                message: "the \(source) report could not be encoded"
            )
        }

        let payload = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(payload, "usagePage", Self.usagePage)
        xpc_dictionary_set_uint64(payload, "usage", Self.usage)
        xpc_dictionary_set_uint64(payload, "version", 0)
        body.withUnsafeBytes { bytes in
            xpc_dictionary_set_data(payload, "data", bytes.baseAddress, bytes.count)
        }

        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(message, "messageType", "IndigoVendorDefinedEvent")
        xpc_dictionary_set_string(message, "featureIdentifier", Self.serviceName)
        xpc_dictionary_set_value(message, "payload", payload)

        lock.lock()
        defer { lock.unlock() }
        xpc_connection_send_message(connection, message)
    }

    /// The guest reads the report body as a serialised IOKit dictionary, not as JSON or a plist.
    static func serialize(source: String, type: String, value: Any) -> Data? {
        let dictionary: NSDictionary = [
            "provider": Self.provider,
            "source": source,
            "type": type,
            "value": value,
        ]
        guard let image = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let symbol = dlsym(image, "IOCFSerialize") else { return nil }
        defer { dlclose(image) }
        typealias Serialize = @convention(c) (CFTypeRef, CFOptionFlags) -> Unmanaged<CFData>?
        guard let serialized = unsafeBitCast(symbol, to: Serialize.self)(dictionary, 1) else { return nil }
        return serialized.takeRetainedValue() as Data
    }
}

/// A continuation that can be finished from either the reply or the timeout, whichever lands first.
private final class SingleReply: @unchecked Sendable {
    private let continuation: CheckedContinuation<Void, Error>
    private let lock = NSLock()
    private var isDone = false

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let alreadyDone = isDone
        isDone = true
        lock.unlock()
        guard !alreadyDone else { return }
        continuation.resume(with: result)
    }
}
