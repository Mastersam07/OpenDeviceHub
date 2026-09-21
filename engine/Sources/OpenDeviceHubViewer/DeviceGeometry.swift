import CoreGraphics
import OpenDeviceHubEngine

public struct DeviceMetrics: Sendable, Hashable {
    public let pixelSize: CGSize
    public let pointScale: CGFloat
    public let pixelsPerInch: CGFloat?

    public init(pixelSize: CGSize, pointScale: CGFloat, pixelsPerInch: CGFloat?) {
        self.pixelSize = pixelSize
        self.pointScale = pointScale
        self.pixelsPerInch = pixelsPerInch
    }
}

public struct ScreenMetrics: Sendable, Hashable {
    public let backingScaleFactor: CGFloat
    /// Nil when the display does not report a physical size, which rules out physical size scaling.
    public let pixelsPerInch: CGFloat?

    public init(backingScaleFactor: CGFloat, pixelsPerInch: CGFloat?) {
        self.backingScaleFactor = backingScaleFactor
        self.pixelsPerInch = pixelsPerInch
    }
}

public enum ScaleApplication: Sendable, Equatable {
    case applied(CGSize)
    /// Applied, but the window is bigger than the screen can show at once.
    case largerThanScreen(CGSize)
    /// Fit imposes no size, so the window keeps whatever shape it has.
    case noFixedSize
    /// Physical size needs both the device's and the display's pixel density.
    case unavailable
}

public enum DeviceGeometry {
    /// Whether a window of this content size can be shown whole on a screen with this visible area.
    public static func fitsOnScreen(
        contentSize: CGSize,
        visibleSize: CGSize,
        titleBarHeight: CGFloat
    ) -> Bool {
        contentSize.width <= visibleSize.width
            && contentSize.height + titleBarHeight <= visibleSize.height
    }

    /// Moves a window frame so its title bar stays reachable on screen, without resizing it: a
    /// window bigger than the screen is allowed, one whose title bar sits above the menu bar is
    /// not. Rotating or changing scale mode keeps the top left corner, so a tall shape can
    /// otherwise land above the screen.
    public static func onScreenOrigin(frame: CGRect, visibleFrame: CGRect) -> CGPoint {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return frame.origin }

        var x = frame.minX
        if frame.width <= visibleFrame.width {
            x = min(max(x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        } else {
            x = min(max(x, visibleFrame.maxX - frame.width), visibleFrame.minX)
        }

        var y = frame.minY
        if frame.height <= visibleFrame.height {
            y = min(max(y, visibleFrame.minY), visibleFrame.maxY - frame.height)
        } else {
            y = visibleFrame.maxY - frame.height
        }

        return CGPoint(x: x, y: y)
    }

    /// The size in macOS points that shows the device's screen at its own point size. The scale is
    /// guarded because a device type with no reported scale would otherwise divide by zero.
    public static func pointSize(pixelSize: CGSize, pointScale: CGFloat) -> CGSize {
        let scale = pointScale > 0 ? pointScale : 1
        return CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
    }

    /// The window content size a mode asks for, in macOS points. Fit has no fixed size because the
    /// window is free to be any shape, and physical size is nil when either density is unknown.
    public static func contentSize(
        for mode: ScaleMode,
        device: DeviceMetrics,
        screen: ScreenMetrics,
        orientation: DeviceOrientation = .portrait
    ) -> CGSize? {
        guard device.pixelSize.width > 0, device.pixelSize.height > 0 else { return nil }
        let device = DeviceMetrics(
            pixelSize: orientation.displayedSize(portraitNative: device.pixelSize),
            pointScale: device.pointScale,
            pixelsPerInch: device.pixelsPerInch
        )

        switch mode {
        case .fit:
            return nil
        case .pointAccurate:
            return pointSize(pixelSize: device.pixelSize, pointScale: device.pointScale)
        case .pixelAccurate:
            let backing = screen.backingScaleFactor > 0 ? screen.backingScaleFactor : 1
            return CGSize(
                width: device.pixelSize.width / backing,
                height: device.pixelSize.height / backing
            )
        case .physicalSize:
            guard let devicePPI = device.pixelsPerInch, devicePPI > 0,
                  let screenPPI = screen.pixelsPerInch, screenPPI > 0 else { return nil }
            let backing = screen.backingScaleFactor > 0 ? screen.backingScaleFactor : 1
            // Device inches, converted into the Mac's points: its points per inch is its pixel
            // density divided by the backing scale factor.
            let pointsPerInch = screenPPI / backing
            return CGSize(
                width: device.pixelSize.width / devicePPI * pointsPerInch,
                height: device.pixelSize.height / devicePPI * pointsPerInch
            )
        }
    }
}
