import CoreGraphics

public enum WindowPlacement {
    /// Where to put the next device window, in AppKit screen coordinates whose origin is the
    /// bottom left. Windows are laid out left to right along the top of the screen and wrap to a
    /// new row, so several devices are visible at once. Cascading put them almost entirely on top
    /// of each other once windows were allowed to exceed the screen.
    public static func nextOrigin(
        for size: CGSize,
        placed: [CGRect],
        in visible: CGRect,
        gap: CGFloat
    ) -> CGPoint {
        let top = CGPoint(x: visible.minX, y: visible.maxY - size.height)
        guard !placed.isEmpty else { return top }

        let rightEdge = placed.map(\.maxX).max() ?? visible.minX
        let candidateX = rightEdge + gap
        if candidateX + size.width <= visible.maxX {
            return CGPoint(x: candidateX, y: visible.maxY - size.height)
        }

        // Out of width, so start a new row under the shortest column so far.
        let bottomEdge = placed.map(\.minY).min() ?? visible.maxY
        return CGPoint(x: visible.minX, y: bottomEdge - gap - size.height)
    }
}
