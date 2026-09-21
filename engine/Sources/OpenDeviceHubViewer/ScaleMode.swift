import AppKit
import ArgumentParser

public enum ScaleMode: String, Sendable, Hashable, Codable, CaseIterable, ExpressibleByArgument {
    /// Scale the device screen to fill the window, preserving aspect ratio.
    case fit = "fit"
    /// One device point maps to one macOS point.
    case pointAccurate = "point-accurate"
    /// One device pixel maps to one physical screen pixel.
    case pixelAccurate = "pixel-accurate"
    /// Match the device's real world size using the Mac display's physical DPI.
    case physicalSize = "physical-size"

    /// Reads the metrics physical size scaling needs from the screen a window is on.
    @MainActor
    public static func screenMetrics(for screen: NSScreen?) -> ScreenMetrics {
        guard let screen else {
            return ScreenMetrics(backingScaleFactor: 1, pixelsPerInch: nil)
        }
        let backing = screen.backingScaleFactor
        var pixelsPerInch: CGFloat?
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let millimetres = CGDisplayScreenSize(CGDirectDisplayID(number.uint32Value))
            if millimetres.width > 0 {
                let pixelWidth = screen.frame.width * backing
                pixelsPerInch = pixelWidth / (millimetres.width / 25.4)
            }
        }
        return ScreenMetrics(backingScaleFactor: backing, pixelsPerInch: pixelsPerInch)
    }

    public var displayName: String {
        switch self {
        case .fit: return "Fit"
        case .pointAccurate: return "Point Accurate"
        case .pixelAccurate: return "Pixel Accurate"
        case .physicalSize: return "Physical Size"
        }
    }
}
