import Foundation

/// Which panel of a foldable the guest is laying out on, as it changes.
public final class ActivePanelWatcher: @unchecked Sendable {
    public let changes: AsyncStream<DisplayReport.Display>

    /// The clock is a safety net: the screens announce their own changes, and a poke looks at once.
    static let fallbackPoll: Duration = .seconds(5)
    /// A poke arrives before the report has caught up (27A266a: the screens announce a fold about
    /// half a second before the report names the new panel), so it looks again a few times.
    static let burstInterval: Duration = .milliseconds(150)
    static let burstReads = 14
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
                await self?.burst()
            }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.reread()
                try? await Task.sleep(for: Self.fallbackPoll)
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

    /// Something happened that may have moved the guest: a command was sent, or a screen announced
    /// a change. Look now, and keep looking briefly, rather than wait for the clock.
    public func poke() {
        pokes?.yield(())
    }

    private func burst() async {
        let before = activePanel?.uniqueID
        for _ in 0..<Self.burstReads {
            await reread()
            if activePanel?.uniqueID != before { return }
            try? await Task.sleep(for: Self.burstInterval)
            if Task.isCancelled { return }
        }
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

    // Swift 6 will not let a lock be taken directly in an async function.
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
            // The report changed its mind without the fold moving: an oscillation, not a handoff.
            return
        }
        current = active
        hingeAtLastChange = latestHinge
        continuation.yield(active)
    }
}
