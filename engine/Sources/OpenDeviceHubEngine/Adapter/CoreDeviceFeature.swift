import Foundation
import XPC

/// One of the guest's CoreDevice features, driven by its actions.
///
/// This is the plane that knows what the guest is doing: which of its screens is active, what its
/// hinge reads, which touchscreen belongs to which screen. The simulator input services only take
/// commands; this one answers questions. `devicectl` fronts the same features, so anything read
/// here can be checked against it.
///
/// A request is one XPC dictionary under `CoreDevice.*` keys and the reply carries either
/// `CoreDevice.output` or `CoreDevice.error`. A streaming action names a side channel in its input
/// and the guest then sends events for that channel on the connection, each of which is answered
/// with whether to stop. The shapes are idb's, confirmed against `devicectl` on Xcode 27 (27A266a).
public final class CoreDeviceFeature: @unchecked Sendable {
    public static let displayInfoService = "com.apple.coredevice.feature.getdisplayinfo"
    public static let displayInfoAction = "com.apple.coredevice.action.displayinfo"
    public static let motionService = "com.apple.coredevice.feature.monitormotion"
    public static let motionCapabilitiesAction = "com.apple.coredevice.action.querymotioncapabilities"
    public static let hingeStreamAction = "com.apple.coredevice.action.streamhingeangle"
    public static let universalHIDService = "com.apple.coredevice.feature.remote.universalhidservice"

    static let replyTimeout: TimeInterval = 5
    static let sideChannelKey = "XPCSideChannel.uniqueIdentifier"
    static let cancellationKey = "CoreDevice.XPCMessageKey.cancellationRequested"

    /// A stream in flight. Cancelling asks the guest to stop at its next event.
    public final class StreamHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        public func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    private struct SideChannel {
        let handle: StreamHandle
        let onEvent: @Sendable (xpc_object_t) -> Void
        let onEnd: @Sendable ((any Error)?) -> Void
    }

    private let connection: xpc_connection_t
    private let udid: String
    private let queue = DispatchQueue(label: "\(Brand.identifierPrefix).coredevice", qos: .userInitiated)
    private let lock = NSLock()
    private var channels: [String: SideChannel] = [:]

    init(port: mach_port_t, udid: String) throws {
        self.udid = udid
        connection = try SimulatorXPC.connect(port: port, queue: queue)
        xpc_connection_set_event_handler(connection) { [weak self] event in
            self?.handle(event)
        }
        xpc_connection_resume(connection)
    }

    deinit {
        xpc_connection_cancel(connection)
    }

    /// Performs one action and hands back its output dictionary.
    public func perform(action: String, input: xpc_object_t? = nil) async throws -> xpc_object_t {
        let request = try Self.request(action: action, udid: udid, input: input)
        let reply = try await send(request, describedAs: action)
        return try Self.output(of: reply, action: action)
    }

    /// Sends a message that is not an action, for the features that speak their own dialect, and
    /// hands back the reply as it came.
    public func exchange(_ message: xpc_object_t, describedAs name: String) async throws -> xpc_object_t {
        try await send(message, describedAs: name)
    }

    /// Starts a streaming action. Every event the guest sends for `sideChannel` reaches `onEvent`,
    /// and `onEnd` is called once, with the error if the stream failed, when the guest ends it or
    /// after the handle is cancelled.
    public func stream(
        action: String,
        input: xpc_object_t,
        sideChannel: UUID,
        onEvent: @escaping @Sendable (xpc_object_t) -> Void,
        onEnd: @escaping @Sendable ((any Error)?) -> Void
    ) throws -> StreamHandle {
        let handle = StreamHandle()
        let key = sideChannel.uuidString
        lock.lock()
        channels[key] = SideChannel(handle: handle, onEvent: onEvent, onEnd: onEnd)
        lock.unlock()

        let request = try Self.request(action: action, udid: udid, input: input)
        xpc_connection_send_message_with_reply(connection, request, queue) { [weak self] reply in
            guard let self else { return }
            let failure: (any Error)?
            if xpc_get_type(reply) == XPC_TYPE_ERROR {
                failure = EngineError.privateCall(symbol: action, message: "the stream's connection was lost")
            } else {
                failure = (try? Self.output(of: reply, action: action)) == nil
                    ? EngineError.privateCall(symbol: action, message: "the device ended the stream with an error")
                    : nil
            }
            end(key, with: failure)
        }
        return handle
    }

    private func send(_ message: xpc_object_t, describedAs name: String) async throws -> xpc_object_t {
        let reply: XPCReply = try await withCheckedThrowingContinuation { continuation in
            let once = OnceContinuation(continuation)
            xpc_connection_send_message_with_reply(connection, message, queue) { reply in
                if xpc_get_type(reply) == XPC_TYPE_ERROR {
                    once.finish(.failure(EngineError.privateCall(
                        symbol: name,
                        message: "the device's CoreDevice service refused the connection"
                    )))
                } else {
                    once.finish(.success(XPCReply(object: reply)))
                }
            }
            queue.asyncAfter(deadline: .now() + Self.replyTimeout) {
                once.finish(.failure(EngineError.privateCall(
                    symbol: name,
                    message: "the device did not answer within \(Int(Self.replyTimeout)) seconds"
                )))
            }
        }
        return reply.object
    }

    private func handle(_ event: xpc_object_t) {
        guard xpc_get_type(event) == XPC_TYPE_DICTIONARY else {
            // The connection itself went, so every stream on it has ended.
            lock.lock()
            let open = channels
            channels = [:]
            lock.unlock()
            for channel in open.values {
                channel.onEnd(EngineError.privateCall(symbol: "CoreDevice", message: "the connection was lost"))
            }
            return
        }
        guard let key = XPCValue.string(event, Self.sideChannelKey) else { return }
        lock.lock()
        let channel = channels[key]
        lock.unlock()
        guard let channel else { return }

        channel.onEvent(event)
        // Every event is answered with whether the guest should stop sending.
        if let reply = xpc_dictionary_create_reply(event) {
            xpc_dictionary_set_bool(reply, Self.cancellationKey, channel.handle.isCancelled)
            xpc_connection_send_message(connection, reply)
        }
    }

    private func end(_ key: String, with failure: (any Error)?) {
        lock.lock()
        let channel = channels.removeValue(forKey: key)
        lock.unlock()
        channel?.onEnd(failure)
    }

    /// The version every request has to declare, read from the framework installed on this host.
    static func installedVersion() throws -> (string: String, components: [UInt64]) {
        let bundle = Bundle(url: URL(fileURLWithPath: "/Library/Developer/PrivateFrameworks/CoreDevice.framework"))
        guard let version = bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            throw EngineError.capabilityUnavailable(name: "the CoreDevice framework's version")
        }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        let components = parts.compactMap { UInt64($0) }
        guard !components.isEmpty, components.count == parts.count else {
            throw EngineError.privateCall(symbol: "CFBundleVersion", message: "unreadable CoreDevice version \(version)")
        }
        return (version, components)
    }

    static func request(action: String, udid: String, input: xpc_object_t?) throws -> xpc_object_t {
        let version = try installedVersion()
        let versionValue = xpc_dictionary_create(nil, nil, 0)
        let components = xpc_array_create(nil, 0)
        for component in version.components {
            xpc_array_append_value(components, xpc_uint64_create(component))
        }
        xpc_dictionary_set_value(versionValue, "components", components)
        xpc_dictionary_set_int64(versionValue, "originalComponentsCount", Int64(version.components.count))
        xpc_dictionary_set_string(versionValue, "stringValue", version.string)

        let request = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(request, "CoreDevice.actionIdentifier", action)
        xpc_dictionary_set_string(request, "CoreDevice.deviceIdentifier", udid)
        xpc_dictionary_set_string(request, "CoreDevice.invocationIdentifier", UUID().uuidString)
        xpc_dictionary_set_int64(request, "CoreDevice.CoreDeviceDDIProtocolVersion", 1)
        xpc_dictionary_set_value(request, "CoreDevice.coreDeviceVersion", versionValue)
        xpc_dictionary_set_value(request, "CoreDevice.input", input ?? xpc_dictionary_create(nil, nil, 0))
        return request
    }

    static func output(of reply: xpc_object_t, action: String) throws -> xpc_object_t {
        if let failure = xpc_dictionary_get_value(reply, "CoreDevice.error") {
            let domain = XPCValue.string(failure, "domain") ?? "unknown"
            let code = Int(XPCValue.number(failure, "code") ?? 0)
            throw EngineError.privateCall(symbol: action, message: "the device answered \(domain) (\(code))")
        }
        guard let output = xpc_dictionary_get_value(reply, "CoreDevice.output"),
              xpc_get_type(output) == XPC_TYPE_DICTIONARY else {
            throw EngineError.privateCall(symbol: action, message: "the device answered without an output")
        }
        return output
    }
}

/// Reading XPC values the way a report may carry them: a number can be signed, unsigned or a double
/// depending on who encoded it, and a missing value is a missing value rather than a zero.
enum XPCValue {
    static func string(_ dictionary: xpc_object_t, _ key: String) -> String? {
        guard let value = xpc_dictionary_get_value(dictionary, key),
              xpc_get_type(value) == XPC_TYPE_STRING,
              let text = xpc_string_get_string_ptr(value) else { return nil }
        return String(cString: text)
    }

    static func bool(_ dictionary: xpc_object_t, _ key: String) -> Bool? {
        guard let value = xpc_dictionary_get_value(dictionary, key),
              xpc_get_type(value) == XPC_TYPE_BOOL else { return nil }
        return xpc_bool_get_value(value)
    }

    static func number(_ dictionary: xpc_object_t, _ key: String) -> Double? {
        guard let value = xpc_dictionary_get_value(dictionary, key) else { return nil }
        return number(value)
    }

    static func number(_ value: xpc_object_t) -> Double? {
        switch xpc_get_type(value) {
        case XPC_TYPE_INT64: Double(xpc_int64_get_value(value))
        case XPC_TYPE_UINT64: Double(xpc_uint64_get_value(value))
        case XPC_TYPE_DOUBLE: xpc_double_get_value(value)
        default: nil
        }
    }

    static func array(_ dictionary: xpc_object_t, _ key: String) -> [xpc_object_t]? {
        guard let value = xpc_dictionary_get_value(dictionary, key) else { return nil }
        return array(value)
    }

    static func array(_ value: xpc_object_t) -> [xpc_object_t]? {
        guard xpc_get_type(value) == XPC_TYPE_ARRAY else { return nil }
        return (0..<xpc_array_get_count(value)).map { xpc_array_get_value(value, $0) }
    }

    static func dictionary(_ dictionary: xpc_object_t, _ key: String) -> xpc_object_t? {
        guard let value = xpc_dictionary_get_value(dictionary, key),
              xpc_get_type(value) == XPC_TYPE_DICTIONARY else { return nil }
        return value
    }

    static func uuid(_ uuid: UUID) -> xpc_object_t {
        var bytes = uuid.uuid
        return withUnsafePointer(to: &bytes) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<uuid_t>.size) {
                xpc_uuid_create($0)
            }
        }
    }
}
