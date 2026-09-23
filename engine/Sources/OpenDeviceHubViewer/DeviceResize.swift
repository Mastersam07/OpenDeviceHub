import AppKit

/// The four corners of the device you can drag to resize the window. A window whose content covers
/// its own edges is awkward to grab by them, and the device is the thing being sized anyway.
public enum DeviceResizeCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    public var isTop: Bool { self == .topLeft || self == .topRight }

    /// How far the target reaches from the corner point.
    public static let reach: CGFloat = 16

    /// The square you have to be inside to start a resize, in the presentation view's coordinates,
    /// which put the origin at the bottom left.
    ///
    /// It sits on the curve rather than on the rectangular vertex: a rounded device has nothing
    /// drawn at the vertex itself, so a target there would put the cursor out past the visible
    /// hardware.
    public func hitRect(in device: CGRect, cornerRadius: CGFloat) -> CGRect {
        let inset = min(cornerRadius, device.width / 2, device.height / 2) * (1 - 1 / 2.0.squareRoot())
        let point = CGPoint(
            x: isLeft ? device.minX + inset : device.maxX - inset,
            y: isTop ? device.maxY - inset : device.minY + inset
        )
        return CGRect(
            x: point.x - Self.reach,
            y: point.y - Self.reach,
            width: Self.reach * 2,
            height: Self.reach * 2
        )
    }

    @MainActor public var cursor: NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition = switch self {
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight: .bottomRight
            }
            return .frameResize(position: position, directions: [.inward, .outward])
        }
        let symbol = isLeft == isTop
            ? "arrow.up.left.and.arrow.down.right"
            : "arrow.up.right.and.arrow.down.left"
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Resize") else {
            return .arrow
        }
        image.size = CGSize(width: 20, height: 20)
        return NSCursor(image: image, hotSpot: CGPoint(x: 10, y: 10))
    }
}

/// A resize in progress. Pure geometry in Cocoa screen coordinates, so the arithmetic is tested
/// without a window: given where the drag started and where the pointer is now, it says what the
/// window's frame should be.
public struct DeviceResizeSession: Equatable {
    public let corner: DeviceResizeCorner
    public let initialFrame: CGRect
    public let initialPointer: CGPoint
    /// The device at scale 1, which is what fixes the shape the window keeps.
    public let deviceSize: CGSize
    public let visibleFrame: CGRect
    public let minimumSize: CGSize

    public init(
        corner: DeviceResizeCorner,
        initialFrame: CGRect,
        initialPointer: CGPoint,
        deviceSize: CGSize,
        visibleFrame: CGRect,
        minimumSize: CGSize
    ) {
        self.corner = corner
        self.initialFrame = initialFrame
        self.initialPointer = initialPointer
        self.deviceSize = deviceSize
        self.visibleFrame = visibleFrame
        self.minimumSize = minimumSize
    }

    /// Everything in the window that is not the device: the bar and the margins around it.
    private var extra: CGSize {
        CGSize(
            width: PresentationLayout.deviceSideMargin * 2,
            height: PresentationLayout.barHeight
                + PresentationLayout.deviceTopMargin
                + PresentationLayout.deviceBottomMargin
        )
    }

    private var initialScale: CGFloat {
        guard deviceSize.height > 0 else { return 1 }
        return max(0.01, (initialFrame.height - extra.height) / deviceSize.height)
    }

    public func frame(at pointer: CGPoint) -> CGRect {
        guard deviceSize.width > 0, deviceSize.height > 0 else { return initialFrame }
        // The corner opposite the one being dragged stays where it is.
        let anchor = CGPoint(
            x: corner.isLeft ? initialFrame.maxX : initialFrame.minX,
            y: corner.isTop ? initialFrame.minY : initialFrame.maxY
        )
        let grownX = (pointer.x - initialPointer.x) * (corner.isLeft ? -1 : 1)
        let grownY = (pointer.y - initialPointer.y) * (corner.isTop ? 1 : -1)
        // Projected onto the device's diagonal, so a drag that is not along it still keeps shape.
        let delta = (grownX * deviceSize.width + grownY * deviceSize.height)
            / (deviceSize.width * deviceSize.width + deviceSize.height * deviceSize.height)

        let room = CGSize(
            width: corner.isLeft ? anchor.x - visibleFrame.minX : visibleFrame.maxX - anchor.x,
            height: corner.isTop ? visibleFrame.maxY - anchor.y : anchor.y - visibleFrame.minY
        )
        let smallest = scale(forContent: minimumSize)
        let largest = max(smallest, scale(forContent: room))
        let scale = min(largest, max(smallest, initialScale + delta))

        let size = CGSize(
            width: max(minimumSize.width, deviceSize.width * scale + extra.width),
            height: max(minimumSize.height, deviceSize.height * scale + extra.height)
        )
        return CGRect(
            x: corner.isLeft ? anchor.x - size.width : anchor.x,
            y: corner.isTop ? anchor.y : anchor.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The device scale a window of this size leaves room for. A minimum bar width does not stop
    /// the device shrinking: below it the device simply gains space on either side.
    private func scale(forContent content: CGSize) -> CGFloat {
        guard deviceSize.width > 0, deviceSize.height > 0 else { return 1 }
        return max(0.01, min(
            (content.width - extra.width) / deviceSize.width,
            (content.height - extra.height) / deviceSize.height
        ))
    }
}
