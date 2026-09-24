import AppKit
import CoreGraphics
import Foundation
import IOSurface

/// Turns a framebuffer surface into a PNG. Whether the bezel is included follows whichever surface
/// the session is currently delivering, so the picture matches what the window shows.
public enum ScreenshotWriter {
    public static func image(from surface: IOSurfaceRef) -> CGImage? {
        IOSurfaceLock(surface, .readOnly, nil)
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }

        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        let bytesPerRow = IOSurfaceGetBytesPerRow(surface)
        guard width > 0, height > 0, bytesPerRow > 0 else { return nil }

        // Copied rather than wrapped, because the surface keeps being drawn into and a lazily read
        // provider would show a later frame or tear.
        let data = Data(bytes: IOSurfaceGetBaseAddress(surface), count: bytesPerRow * height)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// The screen drawn inside the device's body, which is what the window shows and therefore what
    /// a screenshot of "the device" means. The body is AppKit drawing and comes out of
    /// `cacheDisplay`; the screen is Metal and does not, so it is composited in afterwards.
    ///
    /// Rendered at the device's own pixel scale rather than the window's, so a window scaled down to
    /// fit still saves a full resolution screenshot.
    @MainActor
    public static func pngData(
        from surface: IOSurfaceRef,
        inside chrome: NSView,
        screenRect: CGRect
    ) -> Data? {
        guard let screen = image(from: surface),
              screenRect.width > 0, screenRect.height > 0,
              chrome.bounds.width > 0, chrome.bounds.height > 0 else {
            return nil
        }
        let scale = CGFloat(screen.width) / screenRect.width
        let size = CGSize(
            width: (chrome.bounds.width * scale).rounded(),
            height: (chrome.bounds.height * scale).rounded()
        )
        guard size.width >= 1, size.height >= 1,
              let context = CGContext(
                  data: nil,
                  width: Int(size.width),
                  height: Int(size.height),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        chrome.displayIgnoringOpacity(chrome.bounds, in: graphics)
        NSGraphicsContext.restoreGraphicsState()

        context.draw(screen, in: screenRect)
        return context.makeImage().flatMap(pngData(from:))
    }

    static func pngData(from image: CGImage) -> Data? {
        let representation = NSBitmapImageRep(cgImage: image)
        representation.size = CGSize(width: image.width, height: image.height)
        return representation.representation(using: .png, properties: [:])
    }

    public static func pngData(from surface: IOSurfaceRef) -> Data? {
        guard let image = image(from: surface) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// A timestamped name, so repeated screenshots of one device do not overwrite each other.
    public static func fileName(deviceName: String, date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(
            format: "%04d-%02d-%02d at %02d.%02d.%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
        let safeName = deviceName.replacingOccurrences(of: "/", with: "-")
        return "\(safeName) \(stamp).png"
    }
}
