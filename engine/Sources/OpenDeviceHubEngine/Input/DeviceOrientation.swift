import CoreGraphics

/// How the device's screen is turned relative to its portrait native framebuffer.
public enum DeviceOrientation: String, Sendable, Hashable, CaseIterable, Codable {
    case portrait
    case landscapeLeft
    case portraitUpsideDown
    case landscapeRight

    /// Clockwise rotation applied to the portrait native image to get what the viewer shows.
    public var degrees: Int {
        switch self {
        case .portrait: 0
        case .landscapeLeft: 90
        case .portraitUpsideDown: 180
        case .landscapeRight: 270
        }
    }

    public var isLandscape: Bool {
        self == .landscapeLeft || self == .landscapeRight
    }

    /// The size the viewer draws, which swaps the axes in landscape.
    public func displayedSize(portraitNative: CGSize) -> CGSize {
        isLandscape
            ? CGSize(width: portraitNative.height, height: portraitNative.width)
            : portraitNative
    }

    public var rotatedLeft: DeviceOrientation {
        switch self {
        case .portrait: .landscapeRight
        case .landscapeRight: .portraitUpsideDown
        case .portraitUpsideDown: .landscapeLeft
        case .landscapeLeft: .portrait
        }
    }

    public var rotatedRight: DeviceOrientation {
        rotatedLeft.rotatedLeft.rotatedLeft
    }
}
