import AppKit
import OpenDeviceHubEngine
import OpenDeviceHubViewer

/// Installs and removes the `odhub` link on the user's behalf.
///
/// Prefers a directory the person already owns, so on most developer Macs this costs no password.
/// Only when there is no such directory on their `PATH` does it ask, and asking is a dialog of ours
/// before the one macOS shows, so the authentication prompt is never a surprise.
@MainActor
enum CommandLineToolInstaller {
    /// The `odhub` that ships beside this app, or nil for a source build, which has no bundle and
    /// whose binary lives in a build directory that gets deleted.
    static var bundledTool: String? {
        guard Bundle.main.bundleIdentifier != nil,
              let running = ExecutableLocator.runningExecutableURL() else { return nil }
        let tool = ExecutableLocator.siblingURL(of: running, named: Brand.commandName)
        let path = tool.path(percentEncoded: false)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static func state() -> CommandLineToolState {
        guard let bundledTool else { return .missing }
        let links = CommandLineTool.candidateDirectories(home: NSHomeDirectory()).map { directory in
            let link = "\(directory)/\(Brand.commandName)"
            return (link: link, destination: try? FileManager.default.destinationOfSymbolicLink(atPath: link))
        }
        return CommandLineTool.state(links: links, expecting: bundledTool)
    }

    static func install() {
        guard let bundledTool else { return }
        let location = CommandLineTool.chooseLocation(
            candidates: CommandLineTool.candidateDirectories(home: NSHomeDirectory()),
            onPath: loginShellPath(),
            isWritable: { FileManager.default.isWritableFile(atPath: $0) }
        )

        if !location.needsAuthorization, writeLink(to: bundledTool, at: location.link) {
            report(
                title: "\(Brand.commandName) is ready.",
                detail: """
                    Open a new terminal and run \(Brand.commandName) doctor.

                    It is a link at \(location.link), which is already on your PATH. No password was \
                    needed because that folder is yours.
                    """
            )
            return
        }

        askThenRun(
            command: CommandLineTool.privilegedCommand(binary: bundledTool, link: location.link),
            manual: CommandLineTool.manualCommand(binary: bundledTool, link: location.link),
            question: """
                Every folder on your PATH belongs to the system on this Mac, so putting \
                \(Brand.commandName) in \(location.directory) needs your administrator password. \
                macOS will ask for it next.

                Nothing else changes: it creates one link, and Remove Command Line Tool deletes it.
                """,
            done: "\(Brand.commandName) is ready. Open a new terminal and run \(Brand.commandName) doctor."
        )
    }

    static func remove() {
        guard case .installed(let link) = state() else {
            report(
                title: "\(Brand.commandName) was not installed.",
                detail: "There is no link to remove."
            )
            return
        }
        if (try? FileManager.default.removeItem(atPath: link)) != nil {
            report(title: "\(Brand.commandName) was removed.", detail: "The link at \(link) is gone.")
            return
        }
        askThenRun(
            command: CommandLineTool.privilegedRemoval(link: link),
            manual: "sudo rm -f \(CommandLineTool.shellQuoted(link))",
            question: """
                Removing the link at \(link) needs your administrator password, because that folder \
                belongs to the system on this Mac.
                """,
            done: "The link at \(link) is gone."
        )
    }

    /// The `PATH` a terminal would have, not the one this process was launched with. An app started
    /// by launchd gets a minimal `PATH` that says nothing about where a person's tools live, so the
    /// login shell is asked instead.
    private static func loginShellPath() -> Set<String> {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return CommandLineTool.pathEntries(ProcessInfo.processInfo.environment["PATH"] ?? "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandLineTool.pathEntries(String(data: data, encoding: .utf8) ?? "")
    }

    private static func writeLink(to binary: String, at link: String) -> Bool {
        let manager = FileManager.default
        // An existing link is replaced rather than refused, so moving the app and installing again
        // repairs it instead of failing.
        try? manager.removeItem(atPath: link)
        do {
            try manager.createSymbolicLink(atPath: link, withDestinationPath: binary)
            return true
        } catch {
            return false
        }
    }

    private static func askThenRun(command: String, manual: String, question: String, done: String) {
        let ask = NSAlert()
        ask.alertStyle = .informational
        ask.messageText = "Administrator access is needed."
        ask.informativeText = question
        ask.addButton(withTitle: "Continue")
        ask.addButton(withTitle: "Copy Command Instead")
        ask.addButton(withTitle: "Cancel")

        switch ask.runModal() {
        case .alertFirstButtonReturn:
            var failure: NSDictionary?
            NSAppleScript(source: CommandLineTool.authorizingScript(command))?
                .executeAndReturnError(&failure)
            if let failure {
                // Cancelling the system prompt is error -128, which is an answer, not a fault.
                guard (failure[NSAppleScript.errorNumber] as? Int) != -128 else { return }
                report(
                    title: "That did not work.",
                    detail: (failure[NSAppleScript.errorMessage] as? String)
                        ?? "The command could not be run.\n\n\(manual)"
                )
                return
            }
            report(title: "Done.", detail: done)
        case .alertSecondButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(manual, forType: .string)
            report(title: "Copied.", detail: "Paste this into a terminal:\n\n\(manual)")
        default:
            return
        }
    }

    private static func report(title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
