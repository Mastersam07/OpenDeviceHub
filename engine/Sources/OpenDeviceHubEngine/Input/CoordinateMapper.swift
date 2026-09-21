import CoreGraphics

/// Pure conversion between a viewer's coordinates and the device's normalized touch space.
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
    /// device's portrait native normalized space, whose origin is the top left, undoing whatever
    /// rotation the viewer is showing. Returns nil when the point falls on a letterbox bar rather
    /// than on the screen.
    public static func normalize(
        viewPoint: CGPoint,
        viewSize: CGSize,
        pixelSize: CGSize,
        orientation: DeviceOrientation
    ) -> CGPoint? {
        let displayed = orientation.displayedSize(portraitNative: pixelSize)
        guard let shown = normalize(viewPoint: viewPoint, viewSize: viewSize, pixelSize: displayed) else {
            return nil
        }
        return portraitNativePoint(from: shown, orientation: orientation)
    }

    /// Turns a point in what the viewer shows back into the portrait native space the device's
    /// digitizer expects. Both spaces have their origin at the top left.
    static func portraitNativePoint(
        from shown: CGPoint,
        orientation: DeviceOrientation
    ) -> CGPoint {
        switch orientation {
        case .portrait:
            return shown
        case .landscapeLeft:
            return CGPoint(x: shown.y, y: 1 - shown.x)
        case .portraitUpsideDown:
            return CGPoint(x: 1 - shown.x, y: 1 - shown.y)
        case .landscapeRight:
            return CGPoint(x: 1 - shown.y, y: shown.x)
        }
    }

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
