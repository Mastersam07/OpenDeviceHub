import Foundation
import OpenDeviceHubEngine

/// What to tell someone when the app cannot start. Opened from the Dock there is no terminal, so a
/// startup failure has to say what is missing and what to do about it rather than exiting quietly.
public struct StartupAdvice: Equatable, Sendable {
    public let title: String
    public let detail: String
    /// True when installing Xcode is the fix, so the dialog can offer to go and get it.
    public let offersXcode: Bool

    public init(title: String, detail: String, offersXcode: Bool) {
        self.title = title
        self.detail = detail
        self.offersXcode = offersXcode
    }

    public static func forStartupFailure(_ error: any Error) -> StartupAdvice {
        guard let engine = error as? EngineError else {
            return StartupAdvice(
                title: "\(Brand.productName) could not start.",
                detail: error.localizedDescription,
                offersXcode: false
            )
        }

        switch engine {
        case .xcodeNotFound(let searched):
            return StartupAdvice(
                title: "Xcode was not found.",
                detail: """
                    \(Brand.productName) shows the simulators that Xcode installs, so it needs Xcode \
                    on this Mac.

                    Install Xcode, open it once so it can finish setting itself up, then try again.

                    Looked in: \(searched.joined(separator: ", "))
                    """,
                offersXcode: true
            )

        case .xcodeVersionUnreadable:
            return StartupAdvice(
                title: "Xcode is there but did not answer.",
                detail: """
                    xcodebuild could not report a version, which usually means Xcode has not finished \
                    installing or its command line tools point at something that is gone.

                    Open Xcode once, then run xcode-select --install if it still does not start.
                    """,
                offersXcode: false
            )

        case .unsupportedXcode(_, let supported, _):
            return StartupAdvice(
                title: "This Xcode is too old.",
                detail: """
                    \(Brand.productName) works with Xcode \(supported).

                    Install a newer Xcode, or point DEVELOPER_DIR at one you already have.
                    """,
                offersXcode: true
            )

        case .frameworkNotFound(let name, let searched):
            return StartupAdvice(
                title: "Xcode's simulator frameworks could not be loaded.",
                detail: """
                    \(name) is not where it is expected inside this Xcode. That usually means Xcode \
                    is still installing its components, or the copy is incomplete.

                    Open Xcode once and let it finish, then try again.

                    Looked in: \(searched.joined(separator: ", "))
                    """,
                offersXcode: false
            )

        case .symbolNotFound(let name, let framework):
            return StartupAdvice(
                title: "This Xcode is missing something \(Brand.productName) needs.",
                detail: """
                    \(name) is not in \(framework) on this Xcode build, so the simulator cannot be \
                    driven.

                    An Xcode newer than any this was checked against can do this. Please report the \
                    Xcode version.
                    """,
                offersXcode: false
            )

        default:
            return StartupAdvice(
                title: "\(Brand.productName) could not start.",
                detail: engine.localizedDescription,
                offersXcode: false
            )
        }
    }
}

/// Remembers which unverified Xcode versions have already been mentioned, so an Xcode newer than
/// any this was checked against is reported once rather than at every launch.
public struct UnverifiedXcodeNotice: Sendable {
    private let storage: any PreferenceStorage
    private let key: String

    public init(
        storage: any PreferenceStorage = UserDefaultsPreferenceStorage(),
        key: String = "\(Brand.identifierPrefix).unverifiedXcodeSeen"
    ) {
        self.storage = storage
        self.key = key
    }

    /// The advisory to show, or nil when this Xcode is verified or has already been mentioned.
    /// Recording it is a separate call so a caller that cannot show anything does not silence it.
    public func pending(for version: XcodeVersion) -> String? {
        guard let advisory = AdapterFactory.advisory(for: version) else { return nil }
        guard storage.text(forKey: key) != String(version.major) else { return nil }
        return advisory
    }

    public func recordShown(for version: XcodeVersion) {
        storage.setText(String(version.major), forKey: key)
    }
}
