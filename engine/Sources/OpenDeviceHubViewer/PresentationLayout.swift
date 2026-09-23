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
    /// Two rows, for a window too narrow to put the title beside the actions.
    public static let compactBarHeight: CGFloat = 76
    public static let deviceSideMargin: CGFloat = 12
    public static let deviceTopMargin: CGFloat = 12
    public static let deviceBottomMargin: CGFloat = 24
    /// Below this the title and the actions cannot share a row.
    public static let compactWidth: CGFloat = 340

    public let bar: CGRect
    public let device: CGRect
    public let isCompact: Bool
    public let cornerRadius: CGFloat

    /// Full screen hands the window to AppKit, which puts its own chrome at the top, so the bar
    /// squares off and the device takes the rest.
    public init(contentSize: CGSize, isFullScreen: Bool = false) {
        let width = max(contentSize.width, 0)
        let height = max(contentSize.height, 0)
        isCompact = !isFullScreen && width < Self.compactWidth
        let barHeight = isCompact ? Self.compactBarHeight : Self.barHeight

        bar = CGRect(
            x: 0,
            y: max(height - barHeight, 0),
            width: width,
            height: min(barHeight, height)
        )
        cornerRadius = isFullScreen ? 0 : barHeight / 2

        let side = isFullScreen ? 0 : Self.deviceSideMargin
        let top = isFullScreen ? 0 : Self.deviceTopMargin
        let bottom = isFullScreen ? 0 : Self.deviceBottomMargin
        device = CGRect(
            x: side,
            y: bottom,
            width: max(width - side * 2, 0),
            height: max(bar.minY - top - bottom, 0)
        )
    }

    /// What a window has to be, in content points, to show a device of this size with the bar above
    /// it and the margins around it.
    public static func contentSize(forDevice device: CGSize, isCompact: Bool = false) -> CGSize {
        let barHeight = isCompact ? compactBarHeight : barHeight
        return CGSize(
            width: device.width + deviceSideMargin * 2,
            height: device.height + barHeight + deviceTopMargin + deviceBottomMargin
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
