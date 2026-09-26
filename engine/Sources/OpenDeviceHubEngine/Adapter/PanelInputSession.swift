import Foundation
import XPC

/// Touch input addressed at one of a device's screens.
///
/// A foldable has two, and the older input path can only reach whichever the device calls its main
/// screen, which on a foldable is the cover. So while you are looking at the unfolded panel, every
/// tap goes to the other side of the device and nothing happens. The newer path carries the screen
/// as part of the report, which is the only way to reach the panel being shown.
///
/// Keys and buttons are not screen specific, but they travel on this connection too: the legacy
/// client's own reports are dropped once a device is driven this way.
public final class PanelInputSession: InputSession, @unchecked Sendable {
    private let connection: xpc_connection_t
    private let target: UInt64
    private let fallback: any InputSession
    private let lock = NSLock()
    private var isActivated = false

    init(digitizerPort: mach_port_t, screenID: Int, fallback: any InputSession) throws {
        typealias MakeEndpoint = @convention(c) (mach_port_t, UInt64, UInt64) -> xpc_object_t?
        typealias MakeConnection = @convention(c) (xpc_object_t) -> xpc_connection_t?
        typealias EnableGuestToHost = @convention(c) (xpc_connection_t) -> Void

        guard let image = dlopen(nil, RTLD_NOW),
              let endpointSymbol = dlsym(image, "xpc_endpoint_create_mach_port_4sim"),
              let connectionSymbol = dlsym(image, "xpc_connection_create_from_endpoint"),
              let enableSymbol = dlsym(image, "xpc_connection_enable_sim2host_4sim"),
              let endpoint = unsafeBitCast(endpointSymbol, to: MakeEndpoint.self)(digitizerPort, 0, 0),
              let made = unsafeBitCast(connectionSymbol, to: MakeConnection.self)(endpoint) else {
            throw EngineError.symbolNotFound(
                name: "xpc_endpoint_create_mach_port_4sim",
                framework: "libxpc"
            )
        }
        unsafeBitCast(enableSymbol, to: EnableGuestToHost.self)(made)

        connection = made
        target = UInt64(max(screenID, 0))
        self.fallback = fallback
        xpc_connection_set_target_queue(made, .global(qos: .userInteractive))
        xpc_connection_set_event_handler(made) { _ in }
        xpc_connection_resume(made)
    }

    public func touch(_ event: TouchEvent) async throws {
        try await activate()
        guard let first = event.points.first else { return }
        let payload = xpc_dictionary_create(nil, nil, 0)
        func contact(_ point: CGPoint) -> xpc_object_t {
            let value = xpc_dictionary_create(nil, nil, 0)
            xpc_dictionary_set_double(value, "x", point.x)
            xpc_dictionary_set_double(value, "y", point.y)
            return value
        }
        xpc_dictionary_set_value(payload, "pointOne", contact(first))
        if event.points.count > 1 {
            xpc_dictionary_set_value(payload, "pointTwo", contact(event.points[1]))
        }
        xpc_dictionary_set_uint64(payload, "eventType", Self.code(for: event.phase))
        xpc_dictionary_set_uint64(payload, "edge", Self.code(for: event.edge))
        // The screen this report is for. Zero is the device's default, which is the wrong one on a
        // foldable whenever the unfolded panel is being shown.
        xpc_dictionary_set_uint64(payload, "target", target)
        send("IndigoDigitizerEvent", payload: payload)
    }

    public func key(_ event: KeyEvent) async throws {
        try await activate()
        let payload = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(payload, "usageCode", UInt64(event.usage))
        xpc_dictionary_set_uint64(payload, "state", event.phase == .down ? 1 : 2)
        send("IndigoKeyboardButtonEvent", payload: payload)
    }

    public func button(_ button: HardwareButton, phase: ButtonPhase) async throws {
        guard let usage = Self.consumerUsages[button] else {
            throw EngineError.capabilityUnavailable(name: "hardware button \(button)")
        }
        try await activate()
        let payload = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(payload, "usagePage", Self.consumerUsagePage)
        xpc_dictionary_set_uint64(payload, "usageCode", usage)
        xpc_dictionary_set_uint64(payload, "state", phase == .down ? 1 : 2)
        send("IndigoButtonEvent", payload: payload)
    }

    /// Every button on this path is a consumer page usage, unlike the legacy one, where Home, Lock
    /// and Siri are event sources instead. Confirmed on Xcode 27 (27A266a).
    private static let consumerUsagePage: UInt64 = 0x0c
    private static let consumerUsages: [HardwareButton: UInt64] = [
        .home: 0x40,
        .lock: 0x30,
        .volumeUp: 0xe9,
        .volumeDown: 0xea,
        .siri: 0xcf,
    ]

    private func send(_ type: String, payload: xpc_object_t) {
        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(message, "messageType", type)
        xpc_dictionary_set_bool(message, "isBarrier", false)
        xpc_dictionary_set_string(message, "featureIdentifier", FoldableControl.digitizerServiceName)
        xpc_dictionary_set_value(message, "payload", payload)
        xpc_connection_send_message(connection, message)
    }

    public func close() {
        fallback.close()
        xpc_connection_cancel(connection)
    }

    /// The guest ignores reports until the feature has been turned on, once per connection.
    private func activate() async throws {
        guard !hasActivated else { return }

        let payload = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(payload, "usageCode", 0)
        xpc_dictionary_set_uint64(payload, "state", 2)

        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(message, "messageType", "IndigoKeyboardButtonEvent")
        xpc_dictionary_set_bool(message, "isBarrier", true)
        xpc_dictionary_set_string(message, "featureIdentifier", FoldableControl.digitizerServiceName)
        xpc_dictionary_set_value(message, "payload", payload)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = OneAnswer(continuation)
            xpc_connection_send_message_with_reply(connection, message, .global(qos: .userInitiated)) { _ in
                once.finish()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { once.finish() }
        }
        markActivated()
        // The guest needs a moment after the feature comes up before it acts on a report.
        try? await Task.sleep(for: .milliseconds(150))
    }

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

    private static func code(for phase: TouchEvent.Phase) -> UInt64 {
        switch phase {
        case .began: 0
        case .moved: 1
        case .ended, .cancelled: 2
        }
    }

    private static func code(for edge: TouchEvent.Edge) -> UInt64 {
        switch edge {
        case .none: 0
        case .top: 1
        case .left: 2
        case .bottom: 3
        case .right: 4
        }
    }
}

private final class OneAnswer: @unchecked Sendable {
    private let continuation: CheckedContinuation<Void, Never>
    private let lock = NSLock()
    private var isDone = false

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func finish() {
        lock.lock()
        let alreadyDone = isDone
        isDone = true
        lock.unlock()
        guard !alreadyDone else { return }
        continuation.resume()
    }
}
