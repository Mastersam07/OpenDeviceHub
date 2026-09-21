import Foundation

/// The command tree is synchronous so that AppKit can own the process's main thread, which the
/// viewer needs. This is the one seam where a command reaches asynchronous engine work.
enum AsyncBridge {
    static func run<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let box = ResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                box.store(.success(try await operation()))
            } catch {
                box.store(.failure(error))
            }
            semaphore.signal()
        }
        semaphore.wait()

        switch box.take() {
        case .success(let value): return value
        case .failure(let error): throw error
        case .none: throw CommandFailure.operationProducedNoResult
        }
    }
}

enum CommandFailure: Error, LocalizedError {
    case operationProducedNoResult

    var errorDescription: String? {
        switch self {
        case .operationProducedNoResult: "The operation finished without a result."
        }
    }
}

private final class ResultBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<T, Error>?

    func store(_ result: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        value = result
    }

    func take() -> Result<T, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
