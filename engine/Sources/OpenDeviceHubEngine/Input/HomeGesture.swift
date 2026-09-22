import CoreGraphics

/// The swipes up from the bottom edge: the one that goes home, and the one that opens the app
/// switcher. Pure geometry, so both paths are tested without a device.
///
/// Both are the same stroke and the guest tells them apart by how fast the contact is moving when
/// it lifts. A flick goes home; a contact that has come to rest opens the switcher. Measured on
/// 27A266a: the same travel with a settle after it opens the switcher, and without one goes home.
/// Repeating the final point does not count as resting, because a move with no delta changes
/// nothing; the settle has to be real movement.
public enum HomeGesture {
    /// Starts below the home indicator and travels most of the way up the screen. The contact has
    /// to begin within the bottom edge region for the guest to read it as the system gesture
    /// rather than as a drag inside whatever app is showing.
    public static func swipePath(steps: Int = 14) -> [CGPoint] {
        TouchPath.points(
            from: CGPoint(x: 0.5, y: 0.995),
            to: CGPoint(x: 0.5, y: 0.45),
            steps: steps
        )
    }

    /// Stops in the middle of the screen, where the cards are laid out, rather than carrying on up.
    public static func appSwitcherPath(steps: Int = 14) -> [CGPoint] {
        TouchPath.points(
            from: CGPoint(x: 0.5, y: 0.995),
            to: CGPoint(x: 0.5, y: 0.6),
            steps: steps
        )
    }

    /// Small movements around the resting point, alternating so the contact never repeats a
    /// position. A tenth of a percent of the screen is about one point on a phone.
    public static func settlePath(around point: CGPoint, steps: Int = 15) -> [CGPoint] {
        (1...max(steps, 1)).map { index in
            CGPoint(x: point.x, y: point.y + (index.isMultiple(of: 2) ? 0.001 : -0.001))
        }
    }
}
