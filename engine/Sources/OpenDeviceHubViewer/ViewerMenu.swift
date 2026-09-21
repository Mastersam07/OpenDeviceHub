import AppKit
import OpenDeviceHubEngine

/// Builds the application menu. Shortcuts follow the classic Simulator where the action exists.
@MainActor
public enum ViewerMenu {
    public struct Actions {
        public var setScaleMode: (ScaleMode) -> Void
        public var toggleBezel: () -> Void
        public var toggleKeepOnTop: () -> Void
        public var pasteToDevice: () -> Void
        public var setAppearance: (SimctlService.Appearance) -> Void
        public var saveScreenshot: () -> Void
        public var copyScreenshot: () -> Void
        public var toggleRecording: () -> Void
        public var simulateMemoryWarning: () -> Void
        public var openSystemLog: () -> Void
        public var openAppData: () -> Void
        public var shake: () -> Void
        public var toggleSlowAnimations: () -> Void
        public var toggleLatencyOverlay: () -> Void

        public init(
            setScaleMode: @escaping (ScaleMode) -> Void,
            toggleBezel: @escaping () -> Void,
            toggleKeepOnTop: @escaping () -> Void,
            pasteToDevice: @escaping () -> Void,
            setAppearance: @escaping (SimctlService.Appearance) -> Void,
            saveScreenshot: @escaping () -> Void,
            copyScreenshot: @escaping () -> Void,
            toggleRecording: @escaping () -> Void,
            simulateMemoryWarning: @escaping () -> Void,
            openSystemLog: @escaping () -> Void,
            openAppData: @escaping () -> Void,
            shake: @escaping () -> Void,
            toggleSlowAnimations: @escaping () -> Void,
            toggleLatencyOverlay: @escaping () -> Void
        ) {
            self.setScaleMode = setScaleMode
            self.toggleBezel = toggleBezel
            self.toggleKeepOnTop = toggleKeepOnTop
            self.pasteToDevice = pasteToDevice
            self.setAppearance = setAppearance
            self.saveScreenshot = saveScreenshot
            self.copyScreenshot = copyScreenshot
            self.toggleRecording = toggleRecording
            self.simulateMemoryWarning = simulateMemoryWarning
            self.openSystemLog = openSystemLog
            self.openAppData = openAppData
            self.shake = shake
            self.toggleSlowAnimations = toggleSlowAnimations
            self.toggleLatencyOverlay = toggleLatencyOverlay
        }
    }

    public static func install(
        into application: NSApplication,
        actions: Actions,
        capabilities: Capabilities
    ) -> MenuTarget {
        let target = MenuTarget(actions: actions)
        let bar = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit \(Brand.productName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        bar.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(target.item("Copy Screenshot", #selector(MenuTarget.copyScreenshot), "c", []))
        editMenu.addItem(target.item("Paste to Device", #selector(MenuTarget.paste), "v", []))
        editItem.submenu = editMenu
        bar.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let scaleShortcuts: [(ScaleMode, String)] = [
            (.pointAccurate, "1"), (.pixelAccurate, "2"), (.physicalSize, "3"), (.fit, "4"),
        ]
        for (mode, key) in scaleShortcuts {
            let item = target.item(mode.displayName, #selector(MenuTarget.scale(_:)), key, [])
            item.representedObject = mode.rawValue
            viewMenu.addItem(item)
        }
        viewMenu.addItem(.separator())
        viewMenu.addItem(target.item("Show Device Bezel", #selector(MenuTarget.bezel), "b", []))
        viewMenu.addItem(target.item("Keep on Top", #selector(MenuTarget.keepOnTop), "t", []))
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.control, .command]
        viewItem.submenu = viewMenu
        bar.addItem(viewItem)

        let deviceItem = NSMenuItem()
        let deviceMenu = NSMenu(title: "Device")
        deviceMenu.addItem(target.item("Save Screenshot", #selector(MenuTarget.saveScreenshot), "s", []))
        deviceMenu.addItem(target.item("Record Screen", #selector(MenuTarget.record), "r", []))
        deviceMenu.addItem(.separator())
        let appearance = target.item("Toggle Appearance", #selector(MenuTarget.appearance), "a", [.command, .shift])
        deviceMenu.addItem(appearance)
        deviceItem.submenu = deviceMenu
        bar.addItem(deviceItem)

        let debugItem = NSMenuItem()
        let debugMenu = NSMenu(title: "Debug")
        let memoryWarning = target.item("Simulate Memory Warning", #selector(MenuTarget.memoryWarning), "", [])
        // Unavailable items stay visible but disabled, with the reason in a tooltip, rather than
        // disappearing and leaving the menu looking arbitrary.
        disable(memoryWarning, unless: capabilities.contains(.memoryWarning), reason: "not available on this Xcode")
        debugMenu.addItem(memoryWarning)

        let slowAnimations = target.item("Slow Animations", #selector(MenuTarget.slowAnimations(_:)), "", [])
        disable(slowAnimations, unless: capabilities.contains(.slowAnimations), reason: "not available on this Xcode")
        debugMenu.addItem(slowAnimations)

        let shake = target.item("Shake", #selector(MenuTarget.shake), "z", [.control, .command])
        disable(shake, unless: capabilities.contains(.shake), reason: "not available on this Xcode")
        debugMenu.addItem(shake)

        debugMenu.addItem(.separator())
        debugMenu.addItem(target.item("Open System Log", #selector(MenuTarget.systemLog), "", []))
        debugMenu.addItem(target.item("Open App Data in Finder", #selector(MenuTarget.appData), "", []))
        debugMenu.addItem(.separator())
        debugMenu.addItem(target.item("Show Click to Frame Latency", #selector(MenuTarget.latency(_:)), "l", [.command, .shift]))
        debugItem.submenu = debugMenu
        bar.addItem(debugItem)

        application.mainMenu = bar
        return target
    }
}

private func disable(_ item: NSMenuItem, unless available: Bool, reason: String) {
    guard !available else { return }
    item.action = nil
    item.isEnabled = false
    item.toolTip = reason
}

/// Holds the menu actions. AppKit keeps menu targets weakly, so the caller retains this.
@MainActor
public final class MenuTarget: NSObject {
    private let actions: ViewerMenu.Actions
    private var isDark = false
    private var isSlowAnimations = false
    private var isLatencyVisible = false

    init(actions: ViewerMenu.Actions) {
        self.actions = actions
    }

    func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !modifiers.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        item.target = self
        return item
    }

    @objc func scale(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ScaleMode(rawValue: raw) else { return }
        actions.setScaleMode(mode)
    }

    @objc func bezel() { actions.toggleBezel() }
    @objc func keepOnTop() { actions.toggleKeepOnTop() }
    @objc func saveScreenshot() { actions.saveScreenshot() }
    @objc func record() { actions.toggleRecording() }
    @objc func memoryWarning() { actions.simulateMemoryWarning() }
    @objc func systemLog() { actions.openSystemLog() }
    @objc func appData() { actions.openAppData() }
    @objc func shake() { actions.shake() }

    @objc func latency(_ sender: NSMenuItem) {
        isLatencyVisible.toggle()
        sender.state = isLatencyVisible ? .on : .off
        actions.toggleLatencyOverlay()
    }

    @objc func slowAnimations(_ sender: NSMenuItem) {
        isSlowAnimations.toggle()
        sender.state = isSlowAnimations ? .on : .off
        actions.toggleSlowAnimations()
    }
    @objc func copyScreenshot() { actions.copyScreenshot() }
    @objc func paste() { actions.pasteToDevice() }

    @objc func appearance() {
        isDark.toggle()
        actions.setAppearance(isDark ? .dark : .light)
    }
}
