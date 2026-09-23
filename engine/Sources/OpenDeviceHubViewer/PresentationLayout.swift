import CoreGraphics

/// Where the control bar and the device sit inside a window. Pure geometry, so the arrangement is
/// settled without a window, a screen or a device.
///
/// The bar floats: it is inset from the window's sides rather than spanning them, and the device
/// hangs below it with a gap, so the window's own background shows between and around the two.
public struct PresentationLayout: Equatable {
    /// The height AppKit gives a unified toolbar, which is the band the native items are laid out
    /// in. The bar has to match it or the items would sit off centre inside it.
    public static let barHeight: CGFloat = 52
    /// Two rows, for a window too narrow to put the title beside the actions.
    public static let compactBarHeight: CGFloat = 76
    public static let sideMargin: CGFloat = 12
    public static let deviceGap: CGFloat = 10
    /// Below this the title and the actions cannot share a row.
    public static let compactWidth: CGFloat = 340

    public let bar: CGRect
    public let device: CGRect
    public let isCompact: Bool
    public let cornerRadius: CGFloat

    /// Full screen hands the window to AppKit, which puts its own chrome at the top, so the bar
    /// squares off and stops floating.
    public init(contentSize: CGSize, isFullScreen: Bool = false) {
        let width = max(contentSize.width, 0)
        let height = max(contentSize.height, 0)
        isCompact = !isFullScreen && width < Self.compactWidth
        let barHeight = isCompact ? Self.compactBarHeight : Self.barHeight
        let inset = isFullScreen ? 0 : Self.sideMargin
        let top = isFullScreen ? 0 : Self.sideMargin

        bar = CGRect(
            x: inset,
            y: max(height - barHeight - top, 0),
            width: max(width - inset * 2, 0),
            height: min(barHeight, height)
        )
        cornerRadius = isFullScreen ? 0 : barHeight / 2

        let deviceTop = bar.minY - (isFullScreen ? 0 : Self.deviceGap)
        device = CGRect(x: 0, y: 0, width: width, height: max(deviceTop, 0))
    }

    /// What a window has to be, in content points, to show a device of this size with the bar above
    /// it and the margins around it.
    public static func contentSize(forDevice device: CGSize, isCompact: Bool = false) -> CGSize {
        let barHeight = isCompact ? compactBarHeight : barHeight
        return CGSize(
            width: device.width + sideMargin * 2,
            height: device.height + barHeight + sideMargin + deviceGap
        )
    }

    /// The largest device that fits in the space available, keeping its shape. A window taller than
    /// the display would put the bottom of the device out of reach, and that is where its system
    /// gestures start.
    public static func deviceSize(fitting device: CGSize, in available: CGSize) -> CGSize {
        guard device.width > 0, device.height > 0, available.width > 0, available.height > 0 else {
            return device
        }
        // The margins and the bar are fixed, so they come off first and only the device is scaled.
        // Scaling the whole content instead leaves it a point or two too big once the margins are
        // added back to a rounded device.
        let room = CGSize(
            width: available.width - sideMargin * 2,
            height: available.height - barHeight - sideMargin - deviceGap
        )
        guard room.width > 0, room.height > 0 else { return device }
        let scale = min(room.width / device.width, room.height / device.height)
        guard scale < 1 else { return device }
        return CGSize(
            width: (device.width * scale).rounded(.down),
            height: (device.height * scale).rounded(.down)
        )
    }
}
