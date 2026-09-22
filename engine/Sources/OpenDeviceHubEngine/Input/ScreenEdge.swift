import CoreGraphics

extension TouchEvent.Edge {
    /// How close to a side a contact has to begin to count as starting at it.
    public static let defaultBand: CGFloat = 0.03

    /// Which edge a contact beginning here belongs to, taking a point normalized against what the
    /// window is showing rather than against the portrait native framebuffer, since the edge the
    /// guest cares about is the one under the pointer.
    public static func beginning(at point: CGPoint, band: CGFloat = defaultBand) -> TouchEvent.Edge {
        if point.y >= 1 - band { return .bottom }
        if point.y <= band { return .top }
        if point.x <= band { return .left }
        if point.x >= 1 - band { return .right }
        return .none
    }
}
