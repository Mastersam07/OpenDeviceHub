import CoreGraphics
import Foundation

/// A physical button drawn on the device's body, with the HID code the chrome says it sends.
public struct ChromeButton: Sendable, Hashable {
    public enum Anchor: String, Sendable, Hashable {
        case left
        case right
        case top
        case bottom
    }

    public let name: String
    public let title: String
    public let usagePage: UInt32
    public let usage: UInt32
    public let image: String
    public let imageDown: String
    public let anchor: Anchor
    /// Distance from the anchored window edge, in points. The x of a right anchored button is
    /// negative, measured back from the right edge.
    public let offset: CGPoint
    /// Where the button moves to under the pointer. Apple slides it further out of the body, which
    /// is what makes a side button look like it rises.
    public let rolloverOffset: CGPoint
    /// Side buttons are drawn under the body so only the part standing proud of it shows. The Home
    /// button is drawn over it instead.
    public let onTop: Bool

    public init(
        name: String,
        title: String,
        usagePage: UInt32,
        usage: UInt32,
        image: String,
        imageDown: String,
        anchor: Anchor,
        offset: CGPoint,
        rolloverOffset: CGPoint,
        onTop: Bool
    ) {
        self.name = name
        self.title = title
        self.usagePage = usagePage
        self.usage = usage
        self.image = image
        self.imageDown = imageDown
        self.anchor = anchor
        self.offset = offset
        self.rolloverOffset = rolloverOffset
        self.onTop = onTop
    }
}

extension ChromeButton {
    /// The button this maps to on the input session. The chrome also names a HID usage, but the
    /// adapter's own path for Home and Lock is the one confirmed on a device, so that is used and
    /// the usage is kept only as a cross check.
    public var hardwareButton: HardwareButton? {
        switch name {
        case "home": .home
        case "power": .lock
        case "volume-up": .volumeUp
        case "volume-down": .volumeDown
        case "action": .actionButton
        default: nil
        }
    }
}

/// The body Apple draws around a simulated screen, read from a `.devicechrome` bundle in
/// `/Library/Developer/DeviceKit`. The assets stay where the machine already has them; nothing is
/// copied into this repository.
public struct DeviceChrome: Sendable, Hashable {
    public struct Insets: Sendable, Hashable {
        public let left: CGFloat
        public let right: CGFloat
        public let top: CGFloat
        public let bottom: CGFloat

        public init(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
            self.left = left
            self.right = right
            self.top = top
            self.bottom = bottom
        }
    }

    public let identifier: String
    public let bundle: URL
    /// The body's thickness around the screen, which is also the nine slice corner size.
    public let insets: Insets
    /// Extra width either side for buttons that stand proud of the body.
    public let devicePadding: Insets
    public let cornerRadius: CGFloat
    /// Some bundles ship one composite body, others only the nine pieces. Newer phones have the
    /// composite; the home button phones and the tablets do not.
    public let compositeImage: String?
    public let slices: Slices?
    public let buttons: [ChromeButton]

    public struct Slices: Sendable, Hashable {
        public let topLeft: String
        public let top: String
        public let topRight: String
        public let left: String
        public let right: String
        public let bottomLeft: String
        public let bottom: String
        public let bottomRight: String

        public init(
            topLeft: String, top: String, topRight: String, left: String,
            right: String, bottomLeft: String, bottom: String, bottomRight: String
        ) {
            self.topLeft = topLeft
            self.top = top
            self.topRight = topRight
            self.left = left
            self.right = right
            self.bottomLeft = bottomLeft
            self.bottom = bottom
            self.bottomRight = bottomRight
        }
    }

    public func resource(_ name: String) -> URL {
        bundle.appendingPathComponent("Contents/Resources/\(name).pdf")
    }

    public var compositeURL: URL? { compositeImage.map(resource) }
}

extension DeviceChrome {
    /// Reads a `chrome.json`. The shape is Apple's, so every field is optional in practice and a
    /// missing one falls back rather than failing the whole bundle.
    public static func parse(json: Data, bundle: URL) throws -> DeviceChrome {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let identifier = root["identifier"] as? String else {
            throw EngineError.capabilityUnavailable(name: "device chrome description")
        }

        let images = root["images"] as? [String: Any] ?? [:]
        let sizing = images["sizing"] as? [String: Any] ?? [:]
        let insets = Insets(
            left: number(sizing["leftWidth"]),
            right: number(sizing["rightWidth"]),
            top: number(sizing["topHeight"]),
            bottom: number(sizing["bottomHeight"])
        )

        let padding = images["devicePadding"] as? [String: Any] ?? [:]
        let devicePadding = Insets(
            left: number(padding["left"]),
            right: number(padding["right"]),
            top: number(padding["top"]),
            bottom: number(padding["bottom"])
        )

        let border = (root["paths"] as? [String: Any])?["simpleOutsideBorder"] as? [String: Any]
        let cornerRadius = number(border?["cornerRadiusX"])

        let buttons = (root["inputs"] as? [[String: Any]] ?? []).compactMap(button(from:))

        return DeviceChrome(
            identifier: identifier,
            bundle: bundle,
            insets: insets,
            devicePadding: devicePadding,
            cornerRadius: cornerRadius,
            compositeImage: images["composite"] as? String,
            slices: slices(from: images),
            buttons: buttons
        )
    }

    private static func slices(from images: [String: Any]) -> Slices? {
        guard let topLeft = images["topLeft"] as? String,
              let top = images["top"] as? String,
              let topRight = images["topRight"] as? String,
              let left = images["left"] as? String,
              let right = images["right"] as? String,
              let bottomLeft = images["bottomLeft"] as? String,
              let bottom = images["bottom"] as? String,
              let bottomRight = images["bottomRight"] as? String else { return nil }
        return Slices(
            topLeft: topLeft, top: top, topRight: topRight, left: left,
            right: right, bottomLeft: bottomLeft, bottom: bottom, bottomRight: bottomRight
        )
    }

    private static func button(from input: [String: Any]) -> ChromeButton? {
        guard input["type"] as? String == "button",
              let name = input["name"] as? String,
              let image = input["image"] as? String,
              let anchor = ChromeButton.Anchor(rawValue: input["anchor"] as? String ?? "") else {
            return nil
        }
        let allOffsets = input["offsets"] as? [String: Any]
        let offsets = allOffsets?["normal"] as? [String: Any] ?? [:]
        let rollover = allOffsets?["rollover"] as? [String: Any] ?? offsets
        return ChromeButton(
            name: name,
            title: input["accessibilityTitle"] as? String ?? name,
            usagePage: UInt32(number(input["usagePage"])),
            usage: UInt32(number(input["usage"])),
            image: image,
            imageDown: input["imageDown"] as? String ?? image,
            anchor: anchor,
            offset: CGPoint(x: number(offsets["x"]), y: number(offsets["y"])),
            rolloverOffset: CGPoint(x: number(rollover["x"]), y: number(rollover["y"])),
            onTop: input["onTop"] as? Bool ?? false
        )
    }

    private static func number(_ value: Any?) -> CGFloat {
        if let n = value as? NSNumber { return CGFloat(n.doubleValue) }
        return 0
    }
}
