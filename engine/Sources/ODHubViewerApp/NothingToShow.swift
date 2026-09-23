import AppKit
import OpenDeviceHubEngine

/// What the app says when it has no device to show.
///
/// Opened from the Dock there is no terminal to print to, so exiting with a usage message is
/// indistinguishable from an icon that does nothing.
@MainActor
enum NothingToShow {
    static func present(reasons: [String], deviceCount: Int) {
        let alert = NSAlert()
        alert.alertStyle = .informational

        if deviceCount == 0 {
            alert.messageText = "No simulators are installed."
            alert.informativeText = """
                Install an iOS runtime in Xcode, under Settings, Components, and it will appear here.
                """
        } else {
            alert.messageText = "No simulator could be opened."
            alert.informativeText = reasons.isEmpty
                ? "Pick one from Open Simulator in the File menu, or from the Dock icon."
                : reasons.joined(separator: "\n")
                    + "\n\nPick another from Open Simulator in the File menu."
        }

        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
