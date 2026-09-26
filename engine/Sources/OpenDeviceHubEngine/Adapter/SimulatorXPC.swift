import Foundation
import XPC

/// The XPC route into a booted simulator's services, from a mach port that
/// `-[SimDevice lookup:error:]` handed back.
///
/// The three functions live in libxpc and are not declared anywhere public, so they are looked up
/// in the running process rather than linked. The connection is marked simulator to host, without
/// which the service on the other side never sees the messages.
enum SimulatorXPC {
    static func connect(port: mach_port_t, queue: DispatchQueue) throws -> xpc_connection_t {
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
        guard let endpoint = unsafeBitCast(endpointSymbol, to: MakeEndpoint.self)(port, 0, 0),
              let connection = unsafeBitCast(connectionSymbol, to: MakeConnection.self)(endpoint) else {
            throw EngineError.privateCall(
                symbol: "xpc_connection_create_from_endpoint",
                message: "the simulator service could not be connected to"
            )
        }
        unsafeBitCast(enableSymbol, to: EnableGuestToHost.self)(connection)
        xpc_connection_set_target_queue(connection, queue)
        return connection
    }
}

/// An XPC object crossing a continuation. XPC objects are thread safe reference types, which is
/// what Sendable asks for, but the framework does not say so.
struct XPCReply: @unchecked Sendable {
    let object: xpc_object_t
}

/// A continuation that can be finished from either the reply or the timeout, whichever lands
/// first, and never twice.
final class OnceContinuation<Value: Sendable>: @unchecked Sendable {
    private let continuation: CheckedContinuation<Value, any Error>
    private let lock = NSLock()
    private var isDone = false

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Value, any Error>) {
        lock.lock()
        let alreadyDone = isDone
        isDone = true
        lock.unlock()
        guard !alreadyDone else { return }
        continuation.resume(with: result)
    }
}
