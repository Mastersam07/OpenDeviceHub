import AppKit
import OpenDeviceHubEngine
import OpenDeviceHubViewer

@MainActor
enum StartupFailure {
    /// True when nobody is waiting on this process's output: a bundled app started by launchd, which
    /// is what a click in the Dock or the Finder gives. `odhub view` runs the same bundled
    /// executable as its own child, so it keeps the terminal behaviour and never blocks on a dialog.
    ///
    /// The parent, not `isatty`: stderr is a pipe whenever output is redirected, and a modal there
    /// waits for a click that is never coming.
    static var hasNoTerminal: Bool {
        Bundle.main.bundleIdentifier != nil && getppid() == 1
    }

    static func present(_ error: any Error) {
        let advice = StartupAdvice.forStartupFailure(error)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = advice.title
        alert.informativeText = advice.detail
        if advice.offersXcode {
            alert.addButton(withTitle: "Get Xcode")
        }
        alert.addButton(withTitle: "Quit")

        // Explicitly, because `NSApp` is nil until something asks for the shared application, and
        // this can run before anything else has.
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, advice.offersXcode,
           let url = URL(string: "macappstore://apps.apple.com/app/xcode/id497799835") {
            NSWorkspace.shared.open(url)
        }
    }

    /// An Xcode newer than any this was checked against runs anyway, the same as `odhub doctor`
    /// reports it, but it says so once rather than at every launch.
    static func reportUnverifiedXcode(_ install: XcodeInstall) {
        let notice = UnverifiedXcodeNotice()
        guard let advisory = notice.pending(for: install.version) else { return }
        print(advisory)
        guard hasNoTerminal else {
            notice.recordShown(for: install.version)
            return
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Xcode \(install.version.major) has not been verified."
        alert.informativeText = """
            \(advisory)

            Everything here still runs. If something behaves oddly, that is worth reporting with \
            this Xcode version.
            """
        alert.addButton(withTitle: "Continue")
        alert.runModal()
        notice.recordShown(for: install.version)
    }
}
