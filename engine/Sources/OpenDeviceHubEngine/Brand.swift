import Foundation

public enum Brand {
    public static let productName = "OpenDeviceHub"
    public static let commandName = "odhub"
    /// What SwiftPM builds. Inside the application bundle the same binary is installed under
    /// `bundledViewerExecutableName`, so the process is named after the app rather than the product.
    public static let viewerExecutableName = "odhub-viewer"
    public static let bundledViewerExecutableName = "OpenDeviceHub"
    public static let identifierPrefix = "opendevicehub"

    /// Based on the GitHub handle rather than the product name, so the app can be renamed and the
    /// repository moved without it changing. Changing it after a release makes macOS treat the app
    /// as a different one, orphaning every copy already installed.
    public static let bundleIdentifier = "io.github.mastersam07.opendevicehub"

    /// Read from the bundle that is running, which is where the release build writes it. A source
    /// build has no bundle and says so, so a development copy is never mistaken for a release.
    public static let version: String = {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !version.isEmpty else {
            return developmentVersion
        }
        return version
    }()

    public static let developmentVersion = "0.0.0-dev"

    public static var isDevelopmentBuild: Bool { version == developmentVersion }

    /// Sparkle compares this, not the marketing version, so it has to increase with every release
    /// or an update stays invisible to everyone.
    public static let buildNumber: String = {
        guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
              !build.isEmpty else {
            return "0"
        }
        return build
    }()
}
