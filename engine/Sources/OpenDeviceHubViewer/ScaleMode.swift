public enum ScaleMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Scale the device screen to fill the window, preserving aspect ratio.
    case fit
    /// One device point maps to one macOS point.
    case pointAccurate
    /// One device pixel maps to one physical screen pixel.
    case pixelAccurate
    /// Match the device's real world size using the Mac display's physical DPI.
    case physicalSize

    public var displayName: String {
        switch self {
        case .fit: return "Fit"
        case .pointAccurate: return "Point Accurate"
        case .pixelAccurate: return "Pixel Accurate"
        case .physicalSize: return "Physical Size"
        }
    }
}
