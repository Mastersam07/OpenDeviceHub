import Foundation

public enum XcodeLocator {
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> XcodeInstall {
        let developerDir = try developerDirectory(environment: environment)
        let versionOutput = try ProcessRunner.run(
            "/usr/bin/xcodebuild",
            ["-version"]
        )
        guard versionOutput.status == 0 else {
            throw EngineError.xcodeVersionUnreadable(output: versionOutput.standardError)
        }
        let parsed = try parseVersionOutput(versionOutput.standardOutput)

        return XcodeInstall(
            developerDir: developerDir,
            appRoot: appRoot(forDeveloperDir: developerDir),
            version: parsed.version,
            build: parsed.build
        )
    }

    static func developerDirectory(environment: [String: String]) throws -> URL {
        if let override = environment["DEVELOPER_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw EngineError.xcodeNotFound(searched: [override])
            }
            return url.standardizedFileURL
        }

        let selected = try ProcessRunner.run("/usr/bin/xcode-select", ["-p"])
        let path = selected.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selected.status == 0, !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            throw EngineError.xcodeNotFound(searched: ["$DEVELOPER_DIR", "xcode-select -p"])
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    /// A developer directory of `<App>.app/Contents/Developer` yields `<App>.app`. Anything else,
    /// such as a Command Line Tools directory, has no app root and is returned unchanged.
    static func appRoot(forDeveloperDir developerDir: URL) -> URL {
        let components = developerDir.standardizedFileURL.pathComponents
        guard components.count >= 2,
              components[components.count - 1] == "Developer",
              components[components.count - 2] == "Contents" else {
            return developerDir.standardizedFileURL
        }
        return developerDir.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
    }

    static func parseVersionOutput(_ output: String) throws -> (version: XcodeVersion, build: String) {
        var version: XcodeVersion?
        var build: String?

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Xcode ") {
                version = XcodeVersion(parsing: String(line.dropFirst("Xcode ".count)))
            } else if line.hasPrefix("Build version ") {
                let value = line.dropFirst("Build version ".count).trimmingCharacters(in: .whitespaces)
                build = value.isEmpty ? nil : value
            }
        }

        guard let version, let build else {
            throw EngineError.xcodeVersionUnreadable(output: output)
        }
        return (version, build)
    }
}

extension XcodeVersion {
    public init?(parsing string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 3 else { return nil }

        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        guard let major = numbers.first else { return nil }

        self.init(
            major: major,
            minor: numbers.count > 1 ? numbers[1] : 0,
            patch: numbers.count > 2 ? numbers[2] : 0
        )
    }
}
