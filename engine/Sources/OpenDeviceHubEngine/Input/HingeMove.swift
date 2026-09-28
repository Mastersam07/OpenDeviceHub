//
//  The duration by distance and the quintic ease are adapted from Siniulator (Krzysztof Magiera,
//  MIT). See THIRD_PARTY_NOTICES.md.
//

import Foundation

/// A hinge moving the way a hand would: quicker over a long way, never longer than a second.
public struct HingeMove: Sendable, Hashable {
    public let start: Double
    public let target: Double

    public init(start: Double, target: Double) {
        self.start = start
        self.target = target
    }

    public var duration: TimeInterval { max(0.35, min(1, abs(target - start) / 180)) }

    /// Where the hinge is at `progress`, 0 at the start and 1 at the end.
    public func angle(at progress: Double) -> Double {
        if progress <= 0 { return start }
        if progress >= 1 { return target }
        let t = progress
        let eased = t * t * t * (t * (6 * t - 15) + 10)
        return start + (target - start) * eased
    }

    public static let stepInterval: Duration = .milliseconds(16)

    /// When the next step is due, counted from the start of the move: the first tick after
    /// `elapsed`, so time taken between steps shortens the wait instead of adding to it, and a late
    /// step is followed by the next tick rather than a burst.
    public static func nextStep(after elapsed: Duration) -> Duration {
        stepInterval * (Int(max(elapsed, .zero) / stepInterval) + 1)
    }
}
