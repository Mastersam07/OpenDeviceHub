import CoreGraphics

public enum TouchPath {
    /// Evenly spaced points from one coordinate to another, including both ends. A drag needs the
    /// intermediate points: sending only the two ends reads as a contact that jumped, which the
    /// guest treats as a tap somewhere else rather than a swipe.
    public static func points(from start: CGPoint, to end: CGPoint, steps: Int) -> [CGPoint] {
        let count = max(steps, 1)
        return (0...count).map { index in
            let t = CGFloat(index) / CGFloat(count)
            return CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
        }
    }
}
