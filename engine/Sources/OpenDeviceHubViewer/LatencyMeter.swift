import Foundation

/// Measures the gap between a click being sent and the next frame arriving, which is the number
/// that decides whether the viewer feels as direct as Device Hub.
public final class LatencyMeter: @unchecked Sendable {
    public struct Reading: Sendable, Equatable {
        public let lastMilliseconds: Double
        public let averageMilliseconds: Double
        public let sampleCount: Int
    }

    private let lock = NSLock()
    private var pendingClick: UInt64?
    private var samples: [Double] = []
    private let capacity: Int
    private let staleAfterMilliseconds: Double

    /// A click that draws no frame leaves a pending measurement behind. Without an upper bound the
    /// next unrelated frame, possibly seconds later, would be reported as the latency. Anything
    /// older than this is discarded instead, because it is not a response to the click.
    public init(capacity: Int = 30, staleAfterMilliseconds: Double = 500) {
        self.capacity = max(capacity, 1)
        self.staleAfterMilliseconds = staleAfterMilliseconds
    }

    /// Called when a contact is sent. Only the first click of a drag is timed, since later frames
    /// are already flowing and would report a meaninglessly small number.
    public func clickSent(at time: UInt64 = mach_absolute_time()) {
        lock.lock()
        defer { lock.unlock() }
        guard pendingClick == nil else { return }
        pendingClick = time
    }

    /// Called when a frame is drawn. Returns a reading when it closed an outstanding click.
    @discardableResult
    public func frameDrawn(at time: UInt64 = mach_absolute_time()) -> Reading? {
        lock.lock()
        defer { lock.unlock() }
        guard let sent = pendingClick, time > sent else { return nil }
        pendingClick = nil

        let milliseconds = Self.milliseconds(from: time - sent)
        guard milliseconds <= staleAfterMilliseconds else { return nil }
        samples.append(milliseconds)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        return Reading(
            lastMilliseconds: milliseconds,
            averageMilliseconds: samples.reduce(0, +) / Double(samples.count),
            sampleCount: samples.count
        )
    }

    public var reading: Reading? {
        lock.lock()
        defer { lock.unlock() }
        guard let last = samples.last else { return nil }
        return Reading(
            lastMilliseconds: last,
            averageMilliseconds: samples.reduce(0, +) / Double(samples.count),
            sampleCount: samples.count
        )
    }

    static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Mach ticks are not nanoseconds on every machine, so the timebase ratio is applied.
    static func milliseconds(from ticks: UInt64) -> Double {
        let nanoseconds = Double(ticks) * Double(timebase.numer) / Double(timebase.denom)
        return nanoseconds / 1_000_000
    }
}
