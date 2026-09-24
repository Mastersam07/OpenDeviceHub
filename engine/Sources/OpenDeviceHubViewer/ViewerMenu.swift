import AppKit
import OpenDeviceHubEngine

/// The one menu item whose wording depends on what is on disk, so it is asked rather than told.
@MainActor
public struct CommandLineToolMenu {
    public var state: () -> CommandLineToolState
    public var install: () -> Void
    public var remove: () -> Void

    public init(
        state: @escaping () -> CommandLineToolState,
        install: @escaping () -> Void,
        remove: @escaping () -> Void
    ) {
        self.state = state
        self.install = install
        self.remove = remove
    }
}

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
        public var pressButton: (HardwareButton) -> Void
        public var rotate: (Bool) -> Void
        public var restart: () -> Void
        public var erase: () -> Void
        public var stepTextSize: (SimctlService.ContentSizeStep) -> Void
        public var toggleIncreaseContrast: () -> Void
        public var triggerICloudSync: () -> Void
        public var setLocation: (SimctlService.LocationScenario?) -> Void
        public var setCustomLocation: () -> Void
        public var toggleKeyboardInput: (Bool) -> Void
        public var toggleHardwareKeyboard: (Bool) -> Void
        public var matchKeyboardLanguage: (Bool) -> Void
        public var setOrientation: (DeviceOrientation) -> Void
        public var appSwitcher: () -> Void
        public var stopRecording: () -> Void
        public var isRecording: () -> Bool
        public var checkForUpdates: (() -> Void)?
        public var showSettings: (() -> Void)?

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
            toggleLatencyOverlay: @escaping () -> Void,
            pressButton: @escaping (HardwareButton) -> Void,
            rotate: @escaping (Bool) -> Void,
            restart: @escaping () -> Void,
            erase: @escaping () -> Void,
            stepTextSize: @escaping (SimctlService.ContentSizeStep) -> Void,
            toggleIncreaseContrast: @escaping () -> Void,
            triggerICloudSync: @escaping () -> Void,
            setLocation: @escaping (SimctlService.LocationScenario?) -> Void,
            setCustomLocation: @escaping () -> Void,
            toggleKeyboardInput: @escaping (Bool) -> Void,
            toggleHardwareKeyboard: @escaping (Bool) -> Void,
            matchKeyboardLanguage: @escaping (Bool) -> Void,
            setOrientation: @escaping (DeviceOrientation) -> Void,
            appSwitcher: @escaping () -> Void,
            stopRecording: @escaping () -> Void,
            isRecording: @escaping () -> Bool,
            checkForUpdates: (() -> Void)? = nil,
            showSettings: (() -> Void)? = nil
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
            self.pressButton = pressButton
            self.rotate = rotate
            self.restart = restart
            self.erase = erase
            self.stepTextSize = stepTextSize
            self.toggleIncreaseContrast = toggleIncreaseContrast
            self.triggerICloudSync = triggerICloudSync
            self.setLocation = setLocation
            self.setCustomLocation = setCustomLocation
            self.toggleKeyboardInput = toggleKeyboardInput
            self.toggleHardwareKeyboard = toggleHardwareKeyboard
            self.matchKeyboardLanguage = matchKeyboardLanguage
            self.setOrientation = setOrientation
            self.appSwitcher = appSwitcher
            self.stopRecording = stopRecording
            self.isRecording = isRecording
            self.checkForUpdates = checkForUpdates
            self.showSettings = showSettings
        }
    }

    public static func install(
        into application: NSApplication,
        actions: Actions,
        capabilities: Capabilities,
        openSimulatorMenu: NSMenu? = nil,
        commandLineTool: CommandLineToolMenu? = nil
    ) -> MenuTarget {
        // AppKit adds Start Dictation and Emoji & Symbols to any Edit menu. Both work, so neither is
        // a dead item, but there is no text field anywhere in this app to dictate into or to put a
        // character in, and Simulator.app carries neither. Registered rather than set, so anyone who
        // has chosen otherwise keeps their choice.
        UserDefaults.standard.register(defaults: [
            "NSDisabledDictationMenuItem": true,
            "NSDisabledCharacterPaletteMenuItem": true,
        ])

        let target = MenuTarget(actions: actions, commandLineTool: commandLineTool)
        let bar = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let aboutItem = target.item("About \(Brand.productName)", #selector(MenuTarget.about), "", [])
        aboutItem.icon("info.circle")
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        if actions.checkForUpdates != nil {
            appMenu.addItem(target.item("Check for Updates\u{2026}", #selector(MenuTarget.checkForUpdates), "", []))
            appMenu.addItem(.separator())
        }
        if commandLineTool != nil {
            let item = target.item("", #selector(MenuTarget.commandLineTool(_:)), "", [])
            target.trackCommandLineToolItem(item, in: appMenu)
            appMenu.addItem(item)
            appMenu.addItem(.separator())
        }
        if actions.showSettings != nil {
            let item = target.item("Settings\u{2026}", #selector(MenuTarget.settings), ",", [])
            item.icon("gear")
            appMenu.addItem(item)
            appMenu.addItem(.separator())
        }
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        application.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        servicesItem.icon("gearshape.2")
        appMenu.addItem(.separator())

        appMenu.addItem(withTitle: "Hide \(Brand.productName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            .icon("rectangle.dashed")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        // The closest public symbol. The one macOS draws here has no public equivalent, so this is
        // deliberately an approximation rather than a match.
        hideOthers.icon("rectangle.on.rectangle.dashed")
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
            .icon("macwindow.on.rectangle")
        appMenu.addItem(.separator())

        appMenu.addItem(withTitle: "Quit \(Brand.productName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        bar.addItem(appItem)

        if let openSimulatorMenu {
            let fileItem = NSMenuItem()
            let fileMenu = NSMenu(title: "File")
            let open = NSMenuItem(title: "Open Simulator", action: nil, keyEquivalent: "")
            open.submenu = openSimulatorMenu
            fileMenu.addItem(open)
            fileMenu.addItem(.separator())
            fileMenu.addItem(target.item("Save Screen", #selector(MenuTarget.saveScreenshot), "s", []))
            fileMenu.addItem(target.item("Record Screen", #selector(MenuTarget.record), "r", []))
            let stop = target.item("Stop Recording", #selector(MenuTarget.stopRecording), "", [])
            target.trackStopRecordingItem(stop)
            fileMenu.addItem(stop)
            fileMenu.addItem(.separator())
            fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
                .icon("xmark")
            fileItem.submenu = fileMenu
            bar.addItem(fileItem)
        }

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z").icon("arrow.uturn.backward")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z").icon("arrow.uturn.forward")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x").icon("scissors")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c").icon("doc.on.doc")
        editMenu.addItem(target.item("Copy Screen", #selector(MenuTarget.copyScreenshot), "c", [.command, .control]))
        let pasteItem = target.item("Paste", #selector(MenuTarget.paste), "v", [])
        pasteItem.icon("doc.on.clipboard")
        editMenu.addItem(pasteItem)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        bar.addItem(editItem)

        let deviceItem = NSMenuItem()
        let deviceMenu = NSMenu(title: "Device")
        deviceMenu.addItem(target.item("Restart", #selector(MenuTarget.restart), "", []))
        deviceMenu.addItem(target.item("Erase All Content and Settings\u{2026}", #selector(MenuTarget.erase), "", []))
        deviceMenu.addItem(.separator())
        let rotateLeft = target.item("Rotate Left", #selector(MenuTarget.rotateLeft), String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command])
        let rotateRight = target.item("Rotate Right", #selector(MenuTarget.rotateRight), String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command])
        for item in [rotateLeft, rotateRight] {
            disable(item, unless: capabilities.contains(.rotation), reason: "not available on this Xcode")
            deviceMenu.addItem(item)
        }

        let orientationItem = NSMenuItem(title: "Orientation", action: nil, keyEquivalent: "")
        let orientationMenu = NSMenu(title: "Orientation")
        // Four, where Simulator.app offers six: Face Up and Face Down have no equivalent in the
        // engine, and an item that cannot do anything is worse than one that is not there.
        for orientation in DeviceOrientation.allCases {
            let item = target.item(orientation.displayName, #selector(MenuTarget.orientation(_:)), "", [])
            item.representedObject = orientation.rawValue
            disable(item, unless: capabilities.contains(.rotation), reason: "not available on this Xcode")
            orientationMenu.addItem(item)
        }
        orientationItem.submenu = orientationMenu
        deviceMenu.addItem(orientationItem)
        deviceMenu.addItem(.separator())

        let home = target.item("Home", #selector(MenuTarget.home), "h", [.command, .shift])
        let lockItem = target.item("Lock", #selector(MenuTarget.lock), "l", [.command])
        let actionButton = target.item("Action Button", #selector(MenuTarget.actionButton), "", [])
        let siri = target.item("Siri", #selector(MenuTarget.siri), "h", [.command, .shift, .option])
        for item in [home, lockItem, actionButton, siri] {
            disable(item, unless: capabilities.contains(.hardwareButtons), reason: "not available on this Xcode")
            deviceMenu.addItem(item)
        }
        let deviceShake = target.item("Shake", #selector(MenuTarget.shake), "z", [.control, .command])
        disable(deviceShake, unless: capabilities.contains(.shake), reason: "not available on this Xcode")
        deviceMenu.addItem(deviceShake)
        let appSwitcher = target.item("App Switcher", #selector(MenuTarget.appSwitcher), "h", [.control, .command, .shift])
        disable(appSwitcher, unless: capabilities.contains(.touch), reason: "not available on this Xcode")
        deviceMenu.addItem(appSwitcher)
        deviceItem.submenu = deviceMenu
        bar.addItem(deviceItem)

        let ioItem = NSMenuItem()
        let ioMenu = NSMenu(title: "I/O")

        let inputItem = NSMenuItem(title: "Input", action: nil, keyEquivalent: "")
        let inputMenu = NSMenu(title: "Input")
        let sendKeys = target.item(
            "Send Keyboard Input to Device",
            #selector(MenuTarget.keyboardInput(_:)),
            "k",
            [.command, .option]
        )
        sendKeys.state = .on
        inputMenu.addItem(sendKeys)
        inputItem.submenu = inputMenu
        ioMenu.addItem(inputItem)

        let keyboardItem = NSMenuItem(title: "Keyboard", action: nil, keyEquivalent: "")
        let keyboardMenu = NSMenu(title: "Keyboard")
        let hardware = target.item(
            "Connect Hardware Keyboard",
            #selector(MenuTarget.hardwareKeyboard(_:)),
            "k",
            [.command, .shift]
        )
        hardware.state = .on
        disable(hardware, unless: capabilities.contains(.hardwareKeyboard), reason: "not available on this Xcode")
        let sameLanguage = target.item(
            "Use the Same Keyboard Language as macOS",
            #selector(MenuTarget.matchKeyboardLanguage(_:)),
            "",
            []
        )
        sameLanguage.state = .on
        disable(sameLanguage, unless: capabilities.contains(.hardwareKeyboard), reason: "not available on this Xcode")
        keyboardMenu.addItem(sameLanguage)
        keyboardMenu.addItem(hardware)
        keyboardItem.submenu = keyboardMenu
        ioMenu.addItem(keyboardItem)
        ioMenu.addItem(.separator())

        ioMenu.addItem(target.item("Increase Volume", #selector(MenuTarget.volumeUp), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command]))
        ioMenu.addItem(target.item("Decrease Volume", #selector(MenuTarget.volumeDown), String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command]))
        ioItem.submenu = ioMenu
        bar.addItem(ioItem)

        let featuresItem = NSMenuItem()
        let featuresMenu = NSMenu(title: "Features")
        featuresMenu.addItem(target.item("Toggle Appearance", #selector(MenuTarget.appearance), "a", [.command, .shift]))
        featuresMenu.addItem(target.item("Toggle Increase Contrast", #selector(MenuTarget.increaseContrast(_:)), "", []))
        featuresMenu.addItem(.separator())
        featuresMenu.addItem(target.item("Increase Preferred Text Size", #selector(MenuTarget.textSizeUp), "+", [.command, .option]))
        featuresMenu.addItem(target.item("Decrease Preferred Text Size", #selector(MenuTarget.textSizeDown), "-", [.command, .option]))
        featuresMenu.addItem(.separator())
        featuresMenu.addItem(target.item("Trigger iCloud Sync", #selector(MenuTarget.iCloudSync), "i", [.command, .shift]))
        featuresMenu.addItem(.separator())

        let locationItem = NSMenuItem(title: "Location", action: nil, keyEquivalent: "")
        let locationMenu = NSMenu(title: "Location")
        locationMenu.addItem(target.item("None", #selector(MenuTarget.clearLocation), "", []))
        locationMenu.addItem(target.item("Custom Location\u{2026}", #selector(MenuTarget.customLocation), "", []))
        locationMenu.addItem(.separator())
        for scenario in SimctlService.LocationScenario.allCases {
            let item = target.item(scenario.rawValue, #selector(MenuTarget.locationScenario(_:)), "", [])
            item.representedObject = scenario.rawValue
            locationMenu.addItem(item)
        }
        locationItem.submenu = locationMenu
        featuresMenu.addItem(locationItem)
        featuresItem.submenu = featuresMenu
        bar.addItem(featuresItem)

        let debugItem = NSMenuItem()
        let debugMenu = NSMenu(title: "Debug")
        let memoryWarning = target.item("Simulate Memory Warning", #selector(MenuTarget.memoryWarning), "m", [.command, .shift])
        // Unavailable items stay visible but disabled, with the reason in a tooltip, rather than
        // disappearing and leaving the menu looking arbitrary.
        disable(memoryWarning, unless: capabilities.contains(.memoryWarning), reason: "not available on this Xcode")
        debugMenu.addItem(memoryWarning)

        let slowAnimations = target.item("Slow Animations", #selector(MenuTarget.slowAnimations(_:)), "", [])
        disable(slowAnimations, unless: capabilities.contains(.slowAnimations), reason: "not available on this Xcode")
        debugMenu.addItem(slowAnimations)

        debugMenu.addItem(.separator())
        debugMenu.addItem(target.item("Open System Log\u{2026}", #selector(MenuTarget.systemLog), "/", []))
        debugMenu.addItem(target.item("Open App Data in Finder", #selector(MenuTarget.appData), "", []))
        debugMenu.addItem(.separator())
        debugMenu.addItem(target.item("Show Click to Frame Latency", #selector(MenuTarget.latency(_:)), "l", [.command, .shift]))
        debugItem.submenu = debugMenu
        bar.addItem(debugItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
            .icon("minus.rectangle")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.control, .command]
        windowMenu.addItem(target.item("Show Device Bezels", #selector(MenuTarget.bezel), "b", []))
        windowMenu.addItem(target.item("Stay On Top", #selector(MenuTarget.keepOnTop), "t", []))
        windowMenu.addItem(.separator())
        let scaleShortcuts: [(ScaleMode, String)] = [
            (.physicalSize, "1"), (.pointAccurate, "2"), (.pixelAccurate, "3"), (.fit, "4"),
        ]
        for (mode, key) in scaleShortcuts {
            let item = target.item(mode.displayName, #selector(MenuTarget.scale(_:)), key, [])
            item.representedObject = mode.rawValue
            windowMenu.addItem(item)
        }
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
            .icon("square.3.layers.3d")
        windowItem.submenu = windowMenu
        bar.addItem(windowItem)
        application.windowsMenu = windowMenu

        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        let helpEntry = target.item("\(Brand.productName) Help", #selector(MenuTarget.help), "?", [])
        helpEntry.icon("lightbulb")
        helpMenu.addItem(helpEntry)
        helpItem.submenu = helpMenu
        bar.addItem(helpItem)
        application.helpMenu = helpMenu

        application.mainMenu = bar
        return target
    }
}

/// The icons macOS draws on standard commands, set by hand.
///
/// Simulator.app's `MainMenu.nib` carries no images at all, yet its Undo, Cut, Copy and application
/// menu rows have them, so on macOS 26 AppKit decorates nib loaded items itself. It does not do that
/// for a menu built in code: measured here, our Undo and Cut came out bare while the three rows
/// AppKit inserted on its own, AutoFill, Start Dictation and Emoji & Symbols, arrived with icons. So
/// matching the app we replace means naming the symbols.
///
/// Only the standard commands get one. Our own commands stay bare, which is Simulator.app's own
/// seam: `Copy Screen` sits between two icon bearing rows with nothing, and the whole of Device,
/// I/O, Features and Debug has none.
/// Setting `image` is not enough on macOS 27. `preferredImageVisibility` is new there and defaults
/// to `.automatic`, which for a menu built in code resolves to hidden: the image is present,
/// template and correctly sized, and simply is not drawn.
private extension NSMenuItem {
    static let setPreferredImageVisibility = NSSelectorFromString("setPreferredImageVisibility:")
    /// `NSMenuItem.ImageVisibility.visible`, read off the enum on macOS 27 rather than assumed.
    static let imageVisibilityVisible = 1

    @discardableResult
    func icon(_ symbol: String) -> NSMenuItem {
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        // Through the runtime rather than as a property, because `#available` is a runtime test and
        // the symbol still has to exist when this compiles. It does not on the macOS 26 SDK, which
        // is what an Xcode 26 build has, and this project supports both.
        if responds(to: Self.setPreferredImageVisibility) {
            setValue(Self.imageVisibilityVisible, forKey: "preferredImageVisibility")
        }
        return self
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
public final class MenuTarget: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let actions: ViewerMenu.Actions
    private let commandLineTool: CommandLineToolMenu?
    private weak var commandLineToolItem: NSMenuItem?
    private weak var stopRecordingItem: NSMenuItem?
    private var isDark = false
    private var isSlowAnimations = false
    private var isLatencyVisible = false
    private var isIncreasedContrast = false
    private var sendsKeyboardInput = true
    private var hasHardwareKeyboard = true
    private var matchesKeyboardLanguage = true

    init(actions: ViewerMenu.Actions, commandLineTool: CommandLineToolMenu? = nil) {
        self.actions = actions
        self.commandLineTool = commandLineTool
    }

    /// The title has to be read off the disk each time the menu opens, because the link can be
    /// removed, or repointed by installing another copy of the app, while this one is running.
    func trackCommandLineToolItem(_ item: NSMenuItem, in menu: NSMenu) {
        commandLineToolItem = item
        menu.delegate = self
        retitleCommandLineToolItem()
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        retitleCommandLineToolItem()
    }

    private func retitleCommandLineToolItem() {
        guard let commandLineToolItem, let commandLineTool else { return }
        switch commandLineTool.state() {
        case .installed(let link):
            commandLineToolItem.title = "Remove Command Line Tool"
            commandLineToolItem.toolTip = "Deletes the \(link) link."
        case .pointsElsewhere(let link, let destination):
            commandLineToolItem.title = "Repair Command Line Tool\u{2026}"
            commandLineToolItem.toolTip = "\(link) points at \(destination)."
        case .missing:
            commandLineToolItem.title = "Install Command Line Tool\u{2026}"
            commandLineToolItem.toolTip = "Puts \(Brand.commandName) on your PATH."
        }
    }

    @objc func commandLineTool(_ sender: NSMenuItem) {
        guard let commandLineTool else { return }
        if case .installed = commandLineTool.state() {
            commandLineTool.remove()
        } else {
            commandLineTool.install()
        }
        retitleCommandLineToolItem()
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

    @objc func about() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: Brand.productName,
            .applicationVersion: Brand.version,
            .version: Brand.buildNumber,
        ])
    }

    @objc func bezel() { actions.toggleBezel() }
    @objc func keepOnTop() { actions.toggleKeepOnTop() }
    @objc func saveScreenshot() { actions.saveScreenshot() }
    @objc func record() { actions.toggleRecording() }
    @objc func memoryWarning() { actions.simulateMemoryWarning() }
    @objc func systemLog() { actions.openSystemLog() }
    @objc func appData() { actions.openAppData() }
    @objc func shake() { actions.shake() }
    @objc func home() { actions.pressButton(.home) }
    @objc func lock() { actions.pressButton(.lock) }
    @objc func volumeUp() { actions.pressButton(.volumeUp) }
    @objc func volumeDown() { actions.pressButton(.volumeDown) }
    @objc func rotateLeft() { actions.rotate(true) }

    @objc func orientation(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let orientation = DeviceOrientation(rawValue: raw) else { return }
        actions.setOrientation(orientation)
    }

    @objc func siri() { actions.pressButton(.siri) }
    @objc func actionButton() { actions.pressButton(.actionButton) }
    @objc func appSwitcher() { actions.appSwitcher() }
    @objc func restart() { actions.restart() }
    @objc func erase() { actions.erase() }
    @objc func textSizeUp() { actions.stepTextSize(.increment) }
    @objc func textSizeDown() { actions.stepTextSize(.decrement) }
    @objc func iCloudSync() { actions.triggerICloudSync() }
    @objc func clearLocation() { actions.setLocation(nil) }
    @objc func customLocation() { actions.setCustomLocation() }

    /// Both start on, because that is what the app does before anyone touches the menu.
    @objc func keyboardInput(_ sender: NSMenuItem) {
        sendsKeyboardInput.toggle()
        sender.state = sendsKeyboardInput ? .on : .off
        actions.toggleKeyboardInput(sendsKeyboardInput)
    }

    @objc func matchKeyboardLanguage(_ sender: NSMenuItem) {
        matchesKeyboardLanguage.toggle()
        sender.state = matchesKeyboardLanguage ? .on : .off
        actions.matchKeyboardLanguage(matchesKeyboardLanguage)
    }

    @objc func hardwareKeyboard(_ sender: NSMenuItem) {
        hasHardwareKeyboard.toggle()
        sender.state = hasHardwareKeyboard ? .on : .off
        actions.toggleHardwareKeyboard(hasHardwareKeyboard)
    }

    @objc func locationScenario(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let scenario = SimctlService.LocationScenario(rawValue: raw) else { return }
        actions.setLocation(scenario)
    }

    @objc func increaseContrast(_ sender: NSMenuItem) {
        isIncreasedContrast.toggle()
        sender.state = isIncreasedContrast ? .on : .off
        actions.toggleIncreaseContrast()
    }
    @objc func stopRecording() { actions.stopRecording() }

    func trackStopRecordingItem(_ item: NSMenuItem) {
        stopRecordingItem = item
    }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item === stopRecordingItem else { return item.action != nil }
        return actions.isRecording()
    }
    @objc func rotateRight() { actions.rotate(false) }
    @objc func checkForUpdates() { actions.checkForUpdates?() }
    @objc func settings() { actions.showSettings?() }
    @objc func help() { ControlsHelp.show() }

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
