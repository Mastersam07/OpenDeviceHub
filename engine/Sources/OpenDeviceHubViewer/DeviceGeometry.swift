import CoreGraphics

public enum DeviceGeometry {
    /// The size in macOS points that shows the device's screen at its own point size. The scale is
    /// guarded because a device type with no reported scale would otherwise divide by zero.
    public static func pointSize(pixelSize: CGSize, pointScale: CGFloat) -> CGSize {
        let scale = pointScale > 0 ? pointScale : 1
        return CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
    }
}
