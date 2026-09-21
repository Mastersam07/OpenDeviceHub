import Foundation

public struct XcodeVersion: Sendable, Hashable, Codable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }
}

public struct XcodeInstall: Sendable, Hashable, Codable {
    public let developerDir: URL
    public let appRoot: URL
    public let version: XcodeVersion
    public let build: String

    public init(developerDir: URL, appRoot: URL, version: XcodeVersion, build: String) {
        self.developerDir = developerDir
        self.appRoot = appRoot
        self.version = version
        self.build = build
    }
}
