import Foundation
import OpenDeviceHubEngine

public enum CommandLineToolState: Equatable, Sendable {
    case installed(at: String)
    /// Something is already on the `PATH` under this name, pointing somewhere else. Usually an older
    /// copy of the app, sometimes another tool that happens to share the name.
    case pointsElsewhere(link: String, destination: String)
    case missing
}

/// Where the link goes, and whether putting it there needs a password.
public struct InstallLocation: Equatable, Sendable {
    public let directory: String
    public let needsAuthorization: Bool

    public init(directory: String, needsAuthorization: Bool) {
        self.directory = directory
        self.needsAuthorization = needsAuthorization
    }

    public var link: String { "\(directory)/\(Brand.commandName)" }
}

/// Putting `odhub` on the `PATH` without asking anyone to edit a shell profile.
///
/// A link in a directory that is already on the `PATH`, rather than a line in `~/.zshrc`: it works
/// in every shell and it is one file to remove afterwards. Editing someone's profile behind their
/// back is not this app's business.
///
/// A directory the person already owns is preferred over `/usr/local/bin`, which belongs to root on
/// a Mac that has never had Homebrew near it. Most developer Macs have a writable one already on the
/// `PATH`, and then this costs no password at all.
public enum CommandLineTool {
    /// Tried in order. `/usr/local/bin` is last because it is the one that usually needs a password,
    /// not because it is the worst place.
    public static func candidateDirectories(home: String) -> [String] {
        ["/opt/homebrew/bin", "\(home)/.local/bin", "\(home)/bin", "/usr/local/bin"]
    }

    /// `/usr/local/bin` is on the default `PATH` through `/etc/paths` on every Mac, so it counts as
    /// on the path whether or not a particular shell mentions it.
    public static let alwaysOnPath = "/usr/local/bin"

    public static func chooseLocation(
        candidates: [String],
        onPath: Set<String>,
        isWritable: (String) -> Bool
    ) -> InstallLocation {
        for directory in candidates
        where (onPath.contains(directory) || directory == alwaysOnPath) && isWritable(directory) {
            return InstallLocation(directory: directory, needsAuthorization: false)
        }
        return InstallLocation(directory: alwaysOnPath, needsAuthorization: true)
    }

    public static func state(
        links: [(link: String, destination: String?)],
        expecting binary: String
    ) -> CommandLineToolState {
        for entry in links where entry.destination == binary {
            return .installed(at: entry.link)
        }
        for entry in links {
            if let destination = entry.destination {
                return .pointsElsewhere(link: entry.link, destination: destination)
            }
        }
        return .missing
    }

    /// Splits a shell's `PATH` the way a shell does.
    public static func pathEntries(_ path: String) -> Set<String> {
        Set(path.split(separator: ":").map(String.init).filter { !$0.isEmpty })
    }

    /// The command that does what the menu item does, for when the app cannot and a person has to.
    public static func manualCommand(binary: String, link: String) -> String {
        let directory = (link as NSString).deletingLastPathComponent
        return "sudo mkdir -p \(shellQuoted(directory)) && sudo ln -sf \(shellQuoted(binary)) \(shellQuoted(link))"
    }

    /// The same command without `sudo`, to be run by an AppleScript that asks for authorisation.
    public static func privilegedCommand(binary: String, link: String) -> String {
        let directory = (link as NSString).deletingLastPathComponent
        return "mkdir -p \(shellQuoted(directory)) && ln -sf \(shellQuoted(binary)) \(shellQuoted(link))"
    }

    public static func privilegedRemoval(link: String) -> String {
        "rm -f \(shellQuoted(link))"
    }

    /// Wraps a path for `sh`, so a space or a quote in it cannot end the argument.
    public static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Wraps a shell command as an AppleScript string literal.
    static func appleScriptQuoted(_ command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Authorization Services' own prompt. It asks for a password rather than Touch ID: biometrics
    /// prove who is sitting there, which is not the same as holding a privilege, and bridging the
    /// two needs a helper installed as root. One symlink does not justify a permanent root
    /// component, so the better answer is the branch above that needs no password at all.
    public static func authorizingScript(_ command: String) -> String {
        "do shell script \(appleScriptQuoted(command)) with administrator privileges"
    }
}
