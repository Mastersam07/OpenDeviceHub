import CoreGraphics
import Foundation

/// Where the body, the screen and the buttons sit. Everything is worked out in the device's own
/// upright space and then carried into the view by one transform, so turning the device turns its
/// body and its buttons with it rather than stretching an upright shape into a sideways window.
/// Pure, so the arithmetic is tested without opening anything.
public enum ChromeGeometry {
    /// How much further out than its stated offset a side button is drawn, so it matches
    /// Simulator. See `buttonRect`.
    public static let sideButtonProtrusion: CGFloat = 2

    /// The device's own size upright, including the room its buttons need to stand proud.
    public static func contentSize(screen: CGSize, chrome: DeviceChrome) -> CGSize {
        CGSize(
            width: screen.width + chrome.insets.left + chrome.insets.right
                + chrome.devicePadding.left + chrome.devicePadding.right,
            height: screen.height + chrome.insets.top + chrome.insets.bottom
                + chrome.devicePadding.top + chrome.devicePadding.bottom
        )
    }

    /// What the window asks for, which swaps the axes once the device is on its side.
    public static func contentSize(
        screen: CGSize,
        chrome: DeviceChrome,
        orientation: DeviceOrientation
    ) -> CGSize {
        orientation.displayedSize(portraitNative: contentSize(screen: screen, chrome: chrome))
    }

    /// The body's rectangle in the device's own space, which is the device minus the padding that
    /// lets buttons stand proud.
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
        chrome: DeviceChrome,
        hovered: Bool = false
    ) -> CGRect {
        let body = bodyRect(content: content, chrome: chrome)
        let offset = hovered ? button.rolloverOffset : button.offset

        // The chrome's own offset leaves a side button 2pt shy of where Simulator draws it,
        // measured on 17F42 at Point Accurate: its volume button spans 6 to 10pt from the window
        // edge, and the offset alone gives 8 to 10. The body itself lines up exactly, so this
        // moves only the buttons, and only the ones that stand proud of an edge.
        let proud = sideButtonProtrusion

        // A side button measures y down from the top of the body. A bottom anchored one, such as
        // the Home button, carries a negative y measured up from the bottom instead.
        let y: CGFloat = switch button.anchor {
        case .left, .right, .top: body.maxY - offset.y - imageSize.height
        case .bottom: body.minY - offset.y - imageSize.height
        }

        let x: CGFloat = switch button.anchor {
        case .left: offset.x - proud
        case .right: content.width - imageSize.width + offset.x + proud
        case .top, .bottom: body.midX - imageSize.width / 2 + offset.x
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

    /// The whole device fitted into the view and centred, keeping its shape. Full screen makes the
    /// view far larger than the device, so it is fitted rather than filled, which leaves a margin
    /// around it instead of a stretched body.
    public static func deviceRect(
        viewSize: CGSize,
        screen: CGSize,
        chrome: DeviceChrome,
        orientation: DeviceOrientation
    ) -> CGRect {
        let wanted = contentSize(screen: screen, chrome: chrome, orientation: orientation)
        guard wanted.width > 0, wanted.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return .zero
        }
        let scale = min(viewSize.width / wanted.width, viewSize.height / wanted.height)
        let size = CGSize(width: wanted.width * scale, height: wanted.height * scale)
        return CGRect(
            x: (viewSize.width - size.width) / 2,
            y: (viewSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Carries the device's own space into the view: scaled to fit, turned to the orientation and
    /// centred. Drawing concatenates it, hit testing inverts it.
    public static func deviceTransform(
        viewSize: CGSize,
        screen: CGSize,
        chrome: DeviceChrome,
        orientation: DeviceOrientation
    ) -> CGAffineTransform {
        let upright = contentSize(screen: screen, chrome: chrome)
        let placed = deviceRect(
            viewSize: viewSize, screen: screen, chrome: chrome, orientation: orientation
        )
        guard upright.width > 0, upright.height > 0, !placed.isEmpty else { return .identity }
        let scale = orientation.isLandscape
            ? placed.height / upright.width
            : placed.width / upright.width

        return CGAffineTransform.identity
            .translatedBy(x: placed.midX, y: placed.midY)
            // `degrees` turns the image clockwise, which is negative where y runs up the view.
            .rotated(by: -CGFloat(orientation.degrees) * .pi / 180)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -upright.width / 2, y: -upright.height / 2)
    }

    /// The screen's rectangle in the view. Turning by a quarter at a time keeps it square to the
    /// view, so the renderer carries on drawing an upright texture into it.
    public static func screenRect(
        viewSize: CGSize,
        screen: CGSize,
        chrome: DeviceChrome,
        orientation: DeviceOrientation
    ) -> CGRect {
        let upright = contentSize(screen: screen, chrome: chrome)
        return screenRect(content: upright, chrome: chrome).applying(
            deviceTransform(viewSize: viewSize, screen: screen, chrome: chrome, orientation: orientation)
        )
    }

    /// The bands left over around a centred device, which are painted rather than left showing
    /// whatever is behind. Empty when the device fills the view, which is the ordinary case.
    public static func margins(around rect: CGRect, in bounds: CGRect) -> [CGRect] {
        guard !rect.isEmpty, !rect.contains(bounds) else { return [] }
        let clipped = rect.intersection(bounds)
        guard !clipped.isEmpty else { return [bounds] }

        return [
            CGRect(x: bounds.minX, y: clipped.maxY,
                   width: bounds.width, height: bounds.maxY - clipped.maxY),
            CGRect(x: bounds.minX, y: bounds.minY,
                   width: bounds.width, height: clipped.minY - bounds.minY),
            CGRect(x: bounds.minX, y: clipped.minY,
                   width: clipped.minX - bounds.minX, height: clipped.height),
            CGRect(x: clipped.maxX, y: clipped.minY,
                   width: bounds.maxX - clipped.maxX, height: clipped.height),
        ].filter { $0.width > 0 && $0.height > 0 }
    }
}
