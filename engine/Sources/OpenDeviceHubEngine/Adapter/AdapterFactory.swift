import Foundation

public enum AdapterKind: String, Sendable, Hashable {
    case xcode26
}

public enum AdapterFactory {
    public static let supportedMajors = "26"

    public static func make(for install: XcodeInstall) throws -> any SimulatorAdapter {
        switch try kind(for: install.version) {
        case .xcode26:
            return try Xcode26Adapter(xcode: install)
        }
    }

    static func kind(for version: XcodeVersion) throws -> AdapterKind {
        switch version.major {
        case 26:
            return .xcode26
        case 27...:
            throw EngineError.unsupportedXcode(
                version: version.description,
                supported: supportedMajors,
                note: "Xcode 27 support is in progress."
            )
        default:
            throw EngineError.unsupportedXcode(
                version: version.description,
                supported: supportedMajors,
                note: "Xcode 26 is the oldest supported release."
            )
        }
    }
}
