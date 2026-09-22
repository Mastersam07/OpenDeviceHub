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

extension DeviceOrientation {
    /// The value the guest's workspace port expects. Verified on Xcode 26.5 (17F42) and
    /// Xcode 27 (27A266a), all four on an iPad and all but upside down on a Face ID phone, which
    /// refuses that orientation itself.
    var gsEventValue: UInt32 {
        switch self {
        case .portrait: 1
        case .portraitUpsideDown: 2
        case .landscapeRight: 3
        case .landscapeLeft: 4
        }
    }
}
