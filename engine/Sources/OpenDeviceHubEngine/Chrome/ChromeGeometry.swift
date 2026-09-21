import CoreGraphics
import Foundation

/// Where the body, the screen and the buttons sit inside a window. Pure, so the arithmetic is
/// tested without opening anything.
public enum ChromeGeometry {
    /// The window content a screen of this size needs once the body and its proud buttons are
    /// allowed for.
    public static func contentSize(screen: CGSize, chrome: DeviceChrome) -> CGSize {
        CGSize(
            width: screen.width + chrome.insets.left + chrome.insets.right
                + chrome.devicePadding.left + chrome.devicePadding.right,
            height: screen.height + chrome.insets.top + chrome.insets.bottom
                + chrome.devicePadding.top + chrome.devicePadding.bottom
        )
    }

    /// The body's rectangle, which is the content minus the padding that lets buttons stand proud.
    public static func bodyRect(content: CGSize, chrome: DeviceChrome) -> CGRect {
        CGRect(
            x: chrome.devicePadding.left,
            y: chrome.devicePadding.bottom,
            width: max(content.width - chrome.devicePadding.left - chrome.devicePadding.right, 0),
            height: max(content.height - chrome.devicePadding.top - chrome.devicePadding.bottom, 0)
        )
    }

    /// The screen's rectangle in the window's own coordinates, whose origin is the bottom left.
    public static func screenRect(content: CGSize, chrome: DeviceChrome) -> CGRect {
        let body = bodyRect(content: content, chrome: chrome)
        return CGRect(
            x: body.minX + chrome.insets.left,
            y: body.minY + chrome.insets.bottom,
            width: max(body.width - chrome.insets.left - chrome.insets.right, 0),
            height: max(body.height - chrome.insets.top - chrome.insets.bottom, 0)
        )
    }

    /// Where a button's artwork goes. The chrome measures y down from the top of the body, which
    /// is why it is flipped here, and a right anchored button carries a negative x.
    public static func buttonRect(
        _ button: ChromeButton,
        imageSize: CGSize,
        content: CGSize,
        chrome: DeviceChrome
    ) -> CGRect {
        let body = bodyRect(content: content, chrome: chrome)

        // A side button measures y down from the top of the body. A bottom anchored one, such as
        // the Home button, carries a negative y measured up from the bottom instead.
        let y: CGFloat = switch button.anchor {
        case .left, .right, .top: body.maxY - button.offset.y - imageSize.height
        case .bottom: body.minY - button.offset.y - imageSize.height
        }

        let x: CGFloat = switch button.anchor {
        case .left: button.offset.x
        case .right: content.width - imageSize.width + button.offset.x
        case .top, .bottom: body.midX - imageSize.width / 2 + button.offset.x
        }

        return CGRect(x: x, y: y, width: imageSize.width, height: imageSize.height)
    }

    /// The button under a point, if any. Used for hit testing clicks on the body.
    public static func button(
        at point: CGPoint,
        sizes: [String: CGSize],
        content: CGSize,
        chrome: DeviceChrome
    ) -> ChromeButton? {
        for button in chrome.buttons {
            guard let size = sizes[button.image] else { continue }
            let rect = buttonRect(button, imageSize: size, content: content, chrome: chrome)
            if rect.contains(point) { return button }
        }
        return nil
    }
}
