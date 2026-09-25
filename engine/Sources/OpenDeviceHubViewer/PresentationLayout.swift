import CoreGraphics

/// Where the control bar and the device sit inside a window. Pure geometry, so the arrangement is
/// settled without a window, a screen or a device.
///
/// The bar spans the window and sits exactly where AppKit puts the title bar, so the window's own
/// buttons and the toolbar items land on it without being moved. The float comes from the device,
/// which is inset inside the window: the background is clear, so the desktop shows around the
/// device and along the bar's rounded ends.
public struct PresentationLayout: Equatable {
    /// The height AppKit gives a unified toolbar, which is the band the native items are laid out
    /// in. The bar has to match it or the items would sit off centre inside it.
    public static let barHeight: CGFloat = 52
    /// Shorter than the top bar: it carries one slider and three buttons, not the window's own
    /// controls, and the device is what the window is for.
    public static let foldBarHeight: CGFloat = 44
    public static let deviceSideMargin: CGFloat = 12
    public static let deviceTopMargin: CGFloat = 12
    public static let deviceBottomMargin: CGFloat = 24
    /// The narrowest the bar can be and still hold the window's buttons, a readable name and the
    /// actions. The window stops here; the device carries on shrinking and gains margin around it.
    public static let minimumBarWidth: CGFloat = 300
    /// What AppKit keeps at a window's edges for resizing. The content view covers it, so it has to
    /// be left alone for a drag on an edge to reach the window rather than the device.
    public static let resizeBorder: CGFloat = 5
    /// A window opens at a size that leaves room for other windows, the way the simulator it
    /// replaces does, rather than at whatever the device measures in points.
    public static let defaultPhoneWidth: CGFloat = 440
    public static let defaultTabletWidth: CGFloat = 560
    public static let defaultMaximumHeight: CGFloat = 900

    public static var minimumWindowSize: CGSize {
        CGSize(width: minimumBarWidth + deviceSideMargin * 2, height: 360)
    }

    /// The size a window opens at before anything asks for a particular scale.
    public static func defaultContentSize(
        forDevice device: CGSize,
        isTablet: Bool,
        available: CGSize,
        hasFoldBar: Bool = false
    ) -> CGSize {
        let box = CGSize(
            width: isTablet ? defaultTabletWidth : defaultPhoneWidth,
            height: min(defaultMaximumHeight, available.height)
        )
        return contentSize(forDevice: deviceSize(fitting: device, in: box), hasFoldBar: hasFoldBar)
    }

    public let bar: CGRect
    /// The second bar, along the bottom, for the controls only a foldable has. Empty when the
    /// device is not one, which is every device but the Duo.
    public let foldBar: CGRect
    public let device: CGRect
    public let cornerRadius: CGFloat

    /// Full screen hands the window to AppKit, which puts its own chrome at the top, so the bar
    /// squares off and the device takes the rest.
    public init(contentSize: CGSize, isFullScreen: Bool = false, hasFoldBar: Bool = false) {
        let width = max(contentSize.width, 0)
        let height = max(contentSize.height, 0)
        bar = CGRect(
            x: 0,
            y: max(height - Self.barHeight, 0),
            width: width,
            height: min(Self.barHeight, height)
        )
        cornerRadius = isFullScreen ? 0 : Self.barHeight / 2

        let side = isFullScreen ? 0 : Self.deviceSideMargin
        let top = isFullScreen ? 0 : Self.deviceTopMargin
        let bottom = isFullScreen ? 0 : Self.deviceBottomMargin

        // The bottom bar sits inside the margin the device already leaves, so a foldable's window is
        // taller by the bar rather than by the bar and a second set of margins.
        foldBar = hasFoldBar
            ? CGRect(x: 0, y: 0, width: width, height: min(Self.foldBarHeight, height))
            : .zero

        let floor = foldBar.height > 0 ? foldBar.maxY + bottom : bottom
        device = CGRect(
            x: side,
            y: floor,
            width: max(width - side * 2, 0),
            height: max(bar.minY - top - floor, 0)
        )
    }

    /// What a window has to be, in content points, to show a device of this size with the bar above
    /// it and the margins around it.
    public static func contentSize(forDevice device: CGSize, hasFoldBar: Bool = false) -> CGSize {
        CGSize(
            width: device.width + deviceSideMargin * 2,
            height: device.height + barHeight + deviceTopMargin + deviceBottomMargin
                + (hasFoldBar ? foldBarHeight : 0)
        )
    }

    /// How much a device has to be scaled by for the whole window to fit the space available, at
    /// most 1. A window taller than the display would put the bottom of the device out of reach,
    /// and that is where its system gestures start.
    public static func scale(fitting device: CGSize, in available: CGSize) -> CGFloat {
        guard device.width > 0, device.height > 0, available.width > 0, available.height > 0 else {
            return 1
        }
        // The margins and the bar are fixed, so they come off first and only the device is scaled.
        let room = CGSize(
            width: available.width - deviceSideMargin * 2,
            height: available.height - barHeight - deviceTopMargin - deviceBottomMargin
        )
        guard room.width > 0, room.height > 0 else { return 1 }
        return min(1, min(room.width / device.width, room.height / device.height))
    }

    /// The largest device that fits in the space available, keeping its shape.
    public static func deviceSize(fitting device: CGSize, in available: CGSize) -> CGSize {
        let factor = scale(fitting: device, in: available)
        guard factor < 1 else { return device }
        return CGSize(
            width: (device.width * factor).rounded(.down),
            height: (device.height * factor).rounded(.down)
        )
    }
}
