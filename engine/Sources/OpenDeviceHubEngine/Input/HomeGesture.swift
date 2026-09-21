import CoreGraphics

/// The swipe up from the bottom edge that takes a Face ID device home, as a fallback for when the
/// Home button is unavailable. Pure geometry, so the path is tested without a device.
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
}
