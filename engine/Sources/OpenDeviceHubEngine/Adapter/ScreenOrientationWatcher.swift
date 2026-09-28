import Foundation

/// How the guest's screen is turned, as it changes, whoever turned the device: the viewer, Device
/// Hub or the guest itself. It is the screen's own layout that counts, not how the device is held,
/// since a screen that does not turn (an iPhone's home screen, or upside down on a Face ID phone)
/// keeps showing its picture the way it was.
public final class ScreenOrientationWatcher: @unchecked Sendable {
    public enum Event: Sendable, Equatable {
        /// The screen turned, or was read for the first time.
        case turned(DeviceOrientation)
        /// Looked at again after a turn was asked for, the screen had not moved.
        case stillAt(DeviceOrientation)
    }

    public let changes: AsyncStream<Event>

    static let burstInterval: Duration = .milliseconds(100)
    static let burstReads = 25
    /// While a foldable hands its layout from one panel to the other, the report still names the old
    /// panel for about a fifth of a second but already turns it by the new one's angle (27A9269), so
    /// a reading has to hold this long to count.
    static let settleTime: Duration = .milliseconds(400)
    /// A fold never turns a foldable, but its report says otherwise for a while on the way, longer
    /// than `settleTime` at times (27A9269), so nothing read while the hinge moves counts.
    static let foldQuiet: Duration = .seconds(1)
    /// How long after asking for a turn the screen is looked at again. A turn the screen took was
    /// believed at most 1.2 seconds after it was asked for (27A9269).
    static let confirmDelay: Duration = .seconds(2)

    private let continuation: AsyncStream<Event>.Continuation
    private let read: @Sendable () async throws -> DisplayReport
    private let nativeRotation: @Sendable (Int) -> Int
    private var pokes: AsyncStream<Void>.Continuation?
    private var task: Task<Void, Never>?
    /// Kept from one look to the next: the report catches up with a turn half a second or more after
    /// the screens announce it (27A9269), so a look begins by reading the orientation before the
    /// turn, which must not count as a change back to it. Only the one task that looks touches it.
    private var settler = OrientationSettler()
    private let lock = NSLock()
    private var quietUntil: ContinuousClock.Instant?
    private var confirmAt: ContinuousClock.Instant?

    /// `nativeRotation` is the angle the panel with that screen ID is built into the body at, from
    /// the device type. The report's own figure reads 0 for both of a foldable's panels (27A9269).
    public init(
        read: @escaping @Sendable () async throws -> DisplayReport,
        nativeRotation: @escaping @Sendable (Int) -> Int
    ) {
        var escaping: AsyncStream<Event>.Continuation!
        changes = AsyncStream(bufferingPolicy: .bufferingNewest(4)) { escaping = $0 }
        continuation = escaping
        self.read = read
        self.nativeRotation = nativeRotation

        var pokeContinuation: AsyncStream<Void>.Continuation!
        let pokeStream = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { pokeContinuation = $0 }
        pokes = pokeContinuation
        task = Task { [weak self] in
            for await _ in pokeStream {
                await self?.burst()
            }
        }
    }

    /// Looks at the screen now and for a couple of seconds after, since the report catches up with
    /// the screens' own announcement a little later.
    public func poke() {
        pokes?.yield(())
    }

    /// The hinge moved: what the report says until a second after is not believed, and it is looked
    /// at again after that.
    public func holdStill() {
        lock.lock()
        quietUntil = .now + Self.foldQuiet
        lock.unlock()
        poke()
    }

    /// A turn was asked for, which the screen may refuse (upside down on a Face ID phone) or never
    /// hear of: a foldable's turn is sent without an answer. Once the screen has had time to follow,
    /// it is looked at again and said to be still where it was if it has not moved.
    public func confirm() {
        lock.lock()
        confirmAt = .now + Self.confirmDelay
        lock.unlock()
        poke()
    }

    // Swift 6 will not let a lock be taken directly in an async function.
    private func isQuiet(at now: ContinuousClock.Instant) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return quietUntil.map { now < $0 } ?? false
    }

    private func takeConfirmation(at now: ContinuousClock.Instant) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let due = confirmAt, now >= due else { return false }
        confirmAt = nil
        return true
    }

    public func close() {
        task?.cancel()
        task = nil
        pokes?.finish()
        continuation.finish()
    }

    private func burst() async {
        for _ in 0..<Self.burstReads {
            if Task.isCancelled { return }
            let report = try? await read()
            let now = ContinuousClock.now
            let quiet = isQuiet(at: now)
            let reading = quiet ? nil : report.flatMap { Self.reading(from: $0, nativeRotation: nativeRotation) }
            if let settled = settler.observe(reading, at: now, holdingFor: Self.settleTime) {
                continuation.yield(.turned(settled))
            }
            // A screen still settling on something new is turning, and will say so itself.
            if !quiet, takeConfirmation(at: now), let believed = settler.believed, reading?.orientation == believed {
                continuation.yield(.stillAt(believed))
            }
            try? await Task.sleep(for: Self.burstInterval)
        }
    }

    /// The active panel's layout turned by the angle the panel sits at in the body.
    public static func reading(
        from report: DisplayReport,
        nativeRotation: (Int) -> Int
    ) -> OrientationSettler.Reading? {
        guard report.isSettled, let active = report.activeIntegrated,
              let orientation = DeviceOrientation(degrees: active.currentRotation + nativeRotation(active.displayID))
        else { return nil }
        return OrientationSettler.Reading(orientation: orientation, panel: active.displayID)
    }
}

/// Believes a reading once it has held, on the same panel, for a while.
public struct OrientationSettler: Sendable {
    public struct Reading: Sendable, Equatable {
        public let orientation: DeviceOrientation
        public let panel: Int

        public init(orientation: DeviceOrientation, panel: Int) {
            self.orientation = orientation
            self.panel = panel
        }
    }

    private var candidate: (reading: Reading, since: ContinuousClock.Instant)?
    public private(set) var believed: DeviceOrientation?

    public init() {}

    /// The orientation once it is believed, and again each time a different one is.
    public mutating func observe(
        _ reading: Reading?,
        at now: ContinuousClock.Instant,
        holdingFor settle: Duration
    ) -> DeviceOrientation? {
        guard let reading else {
            candidate = nil
            return nil
        }
        if candidate?.reading != reading {
            candidate = (reading, now)
        }
        guard let candidate, now - candidate.since >= settle,
              candidate.reading.orientation != believed else { return nil }
        believed = candidate.reading.orientation
        return believed
    }
}
