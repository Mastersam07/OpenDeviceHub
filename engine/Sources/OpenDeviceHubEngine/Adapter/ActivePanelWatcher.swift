import Foundation

/// Which panel of a foldable the guest is laying out on, as it changes.
///
/// Reads the display report and applies the rule Device Hub applies to it: the reported active
/// panel counts only once the panels' backlights agree with it, and a report that changes its mind
/// while the fold has not moved is an oscillation, not a handoff, and does not win. The report is
/// read again after every hinge reading, after every command this app sends, and on a slow clock
/// in case neither comes.
public final class ActivePanelWatcher: @unchecked Sendable {
    public let changes: AsyncStream<DisplayReport.Display>

    static let pollInterval: Duration = .seconds(1)
    /// How far the hinge has to move between two readings for a change of panel to be believed.
    static let settledHinge: Double = 1

    private let continuation: AsyncStream<DisplayReport.Display>.Continuation
    private let read: @Sendable () async throws -> DisplayReport
    private let lock = NSLock()
    private var current: DisplayReport.Display?
    private var hingeAtLastChange: Double?
    private var latestHinge: Double?
    private var pokes: AsyncStream<Void>.Continuation?
    private var tasks: [Task<Void, Never>] = []

    public init(
        read: @escaping @Sendable () async throws -> DisplayReport,
        hinge: HingeAngleStream?,
        onHinge: (@Sendable (HingeSample) -> Void)? = nil
    ) {
        var escaping: AsyncStream<DisplayReport.Display>.Continuation!
        changes = AsyncStream(bufferingPolicy: .bufferingNewest(4)) { escaping = $0 }
        continuation = escaping
        self.read = read

        var pokeContinuation: AsyncStream<Void>.Continuation!
        let pokeStream = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { pokeContinuation = $0 }
        pokes = pokeContinuation

        tasks.append(Task { [weak self] in
            for await _ in pokeStream {
                await self?.reread()
            }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.reread()
                try? await Task.sleep(for: Self.pollInterval)
            }
        })
        if let hinge {
            tasks.append(Task { [weak self] in
                for await sample in hinge.samples {
                    guard let self else { return }
                    onHinge?(sample)
                    noteHinge(sample.degrees)
                    await reread()
                }
            })
        }
    }

    /// The last panel reported, or nil before the first settled reading.
    public var activePanel: DisplayReport.Display? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Something was just sent that may move the guest; look now rather than on the clock.
    public func poke() {
        pokes?.yield(())
    }

    public func close() {
        for task in tasks { task.cancel() }
        tasks = []
        pokes?.finish()
        continuation.finish()
    }

    private func reread() async {
        guard let report = try? await read() else { return }
        consider(report)
    }

    // Swift 6 will not let a lock be taken directly in an async function, so the two places that
    // touch the state go through these.
    private func noteHinge(_ degrees: Double) {
        lock.lock()
        latestHinge = degrees
        lock.unlock()
    }

    private func consider(_ report: DisplayReport) {
        guard report.isSettled, let active = report.activeIntegrated else { return }
        lock.lock()
        defer { lock.unlock() }
        guard active.uniqueID != current?.uniqueID else { return }
        if let hingeAtLastChange, let latestHinge, current != nil,
           abs(latestHinge - hingeAtLastChange) < Self.settledHinge {
            // The report changed its mind and the fold did not move: an oscillation, which does
            // not earn the change until the device settles.
            return
        }
        current = active
        hingeAtLastChange = latestHinge
        continuation.yield(active)
    }
}
