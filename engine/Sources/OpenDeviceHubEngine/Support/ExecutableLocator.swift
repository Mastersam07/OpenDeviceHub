import Foundation

public enum ExecutableLocator {
    /// Sibling executables are expected next to the running one, which holds both in a build
    /// directory and inside an application bundle.
    public static func siblingURL(of executable: URL, named name: String) -> URL {
        executable.deletingLastPathComponent().appending(path: name)
    }

    public static func runningExecutableURL() -> URL? {
        if let bundled = Bundle.main.executableURL {
            return bundled.resolvingSymlinksInPath()
        }
        let url = executableURL(
            fromArgument: CommandLine.arguments.first,
            currentDirectory: FileManager.default.currentDirectoryPath
        )
        return url?.resolvingSymlinksInPath()
    }

    static func executableURL(fromArgument argument: String?, currentDirectory: String) -> URL? {
        guard let argument, !argument.isEmpty else { return nil }
        if argument.hasPrefix("/") {
            return URL(fileURLWithPath: argument)
        }
        return URL(fileURLWithPath: currentDirectory).appending(path: argument)
    }
}
