import CoreGraphics

/// Where a capture preview sits relative to the window it came from.
///
/// Beside the device rather than over it, so the thing you just captured is never hidden by the
/// proof that you captured it. To the right by default, to the left when the right would run off
/// the display, and clamped to the display when neither side fits.
public enum CapturePreviewLayout {
    public static let gap: CGFloat = 12
    /// Previews stack upwards from the window's bottom edge, newest lowest.
    public static let stackStep: CGFloat = 8

    public static func frame(
        size: CGSize,
        beside window: CGRect,
        visible: CGRect,
        index: Int = 0
    ) -> CGRect {
        let toTheRight = window.maxX + gap
        let toTheLeft = window.minX - gap - size.width

        let x: CGFloat
        if toTheRight + size.width <= visible.maxX {
            x = toTheRight
        } else if toTheLeft >= visible.minX {
            x = toTheLeft
        } else {
            // Neither side fits, so it goes as far right as the display allows and overlaps.
            x = visible.maxX - size.width
        }

        let stacked = window.minY + CGFloat(index) * (size.height + stackStep)
        return CGRect(
            x: clamp(x, low: visible.minX, high: visible.maxX - size.width),
            y: clamp(stacked, low: visible.minY, high: visible.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    /// A card the same shape as the device, so a tall phone does not become a square thumbnail.
    public static func size(for capture: CGSize, longestEdge: CGFloat = 200) -> CGSize {
        guard capture.width > 0, capture.height > 0 else {
            return CGSize(width: longestEdge, height: longestEdge)
        }
        let scale = longestEdge / max(capture.width, capture.height)
        return CGSize(
            width: max(1, (capture.width * scale).rounded()),
            height: max(1, (capture.height * scale).rounded())
        )
    }

    private static func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        guard high > low else { return low }
        return min(max(value, low), high)
    }
}
