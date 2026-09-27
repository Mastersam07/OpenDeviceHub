import CoreGraphics

extension TouchEvent.Edge {
    /// How close to a side a contact has to begin to count as starting at it.
    public static let defaultBand: CGFloat = 0.03

    /// Takes a point in the portrait native framebuffer, not in what the window shows: the guest
    /// reads the edge in the same space as the coordinates.
    public static func beginning(at point: CGPoint, band: CGFloat = defaultBand) -> TouchEvent.Edge {
        if point.y >= 1 - band { return .bottom }
        if point.y <= band { return .top }
        if point.x <= band { return .left }
        if point.x >= 1 - band { return .right }
        return .none
    }
}
