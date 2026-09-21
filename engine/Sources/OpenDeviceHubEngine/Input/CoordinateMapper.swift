import CoreGraphics

/// Pure conversion between a viewer's coordinates and the device's normalized touch space.
/// Portrait only for now; rotation is handled when the viewer supports it.
public enum CoordinateMapper {
    /// The area inside a view that shows the device screen, preserving aspect ratio and centred,
    /// so the leftover space is split evenly as letterbox or pillarbox bars.
    public static func fittedRect(viewSize: CGSize, pixelSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0,
              pixelSize.width > 0, pixelSize.height > 0 else {
            return .zero
        }

        let scale = min(viewSize.width / pixelSize.width, viewSize.height / pixelSize.height)
        let size = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        return CGRect(
            x: (viewSize.width - size.width) / 2,
            y: (viewSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Converts a point in AppKit view coordinates, whose origin is the bottom left, into the
    /// device's normalized space, whose origin is the top left. Returns nil when the point falls on
    /// a letterbox bar rather than on the screen.
    public static func normalize(
        viewPoint: CGPoint,
        viewSize: CGSize,
        pixelSize: CGSize
    ) -> CGPoint? {
        let screen = fittedRect(viewSize: viewSize, pixelSize: pixelSize)
        // Bounds are inclusive. CGRect.contains excludes the max edges, which would make the top
        // and right edges of the screen untappable while the bottom and left worked.
        guard screen.width > 0, screen.height > 0,
              viewPoint.x >= screen.minX, viewPoint.x <= screen.maxX,
              viewPoint.y >= screen.minY, viewPoint.y <= screen.maxY else { return nil }

        let x = (viewPoint.x - screen.minX) / screen.width
        let y = (viewPoint.y - screen.minY) / screen.height
        return CGPoint(x: min(max(x, 0), 1), y: min(max(1 - y, 0), 1))
    }
}
