import Foundation

public enum AdapterKind: String, Sendable, Hashable {
    case coreSimulator
}

public enum AdapterFactory {
    public static let supportedMajors = "26 and 27"
    public static let newestVerifiedMajor = 27
    public static let oldestSupportedMajor = 26

    public static func make(for install: XcodeInstall) throws -> any SimulatorAdapter {
        switch try kind(for: install.version) {
        case .coreSimulator:
            return try CoreSimulatorAdapter(xcode: install)
        }
    }

    static func kind(for version: XcodeVersion) throws -> AdapterKind {
        guard version.major >= oldestSupportedMajor else {
            throw EngineError.unsupportedXcode(
                version: version.description,
                supported: supportedMajors,
                note: "Xcode \(oldestSupportedMajor) is the oldest supported release."
            )
        }
        return .coreSimulator
    }

    /// An unverified major runs rather than being refused, since CoreSimulator has kept the same
    /// surface so far, but doctor has to say it is unverified.
    public static func advisory(for version: XcodeVersion) -> String? {
        guard version.major > newestVerifiedMajor else { return nil }
        return "Xcode \(version.major) has not been verified. "
            + "The adapter is the one checked against Xcode \(newestVerifiedMajor)."
    }
}
