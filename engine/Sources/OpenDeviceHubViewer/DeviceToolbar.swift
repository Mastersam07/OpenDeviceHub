//
//  The tooltips carrying shortcuts, Option on rotate and the screenshot button doubling as a
//  stop button are adapted from Siniulator (Krzysztof Magiera, MIT). See
//  THIRD_PARTY_NOTICES.md.
//

import AppKit

/// What the buttons above a device window do. Each window drives its own device, unlike the menu
/// bar, which acts on every open one.
public struct DeviceToolbarActions {
    public var goHome: () -> Void
    public var saveScreenshot: () -> Void
    public var stopRecording: () -> Void
    /// True turns the device left, which is what holding Option asks for.
    public var rotate: (Bool) -> Void

    public init(
        goHome: @escaping () -> Void,
        saveScreenshot: @escaping () -> Void,
        stopRecording: @escaping () -> Void,
        rotate: @escaping (Bool) -> Void
    ) {
        self.goHome = goHome
        self.saveScreenshot = saveScreenshot
        self.stopRecording = stopRecording
        self.rotate = rotate
    }
}

/// The row of buttons above a device, matching what the classic Simulator offers.
///
/// Every item is a plain `NSToolbarItem` with an image and an action and nothing else set on it.
/// Setting `isBordered`, or a custom view, opts an item out of all of it.
@MainActor
final class DeviceToolbar: NSObject, NSToolbarDelegate, NSToolbarItemValidation {
    private enum Item {
        static let home = NSToolbarItem.Identifier("odh.home")
        static let capture = NSToolbarItem.Identifier("odh.capture")
        static let rotate = NSToolbarItem.Identifier("odh.rotate")
    }

    private let actions: DeviceToolbarActions
    private let items: [NSToolbarItem]
    private var captureItem: NSToolbarItem { items[1] }
    private var isRecording = false
    private var isEnabled = true

    init(actions: DeviceToolbarActions) {
        self.actions = actions
        let home = NSToolbarItem(itemIdentifier: Item.home)
        let capture = NSToolbarItem(itemIdentifier: Item.capture)
        let rotate = NSToolbarItem(itemIdentifier: Item.rotate)
        items = [home, capture, rotate]
        super.init()

        describe(home, symbol: "house", title: "Home", tip: "Home (\u{21E7}\u{2318}H)")
        home.action = #selector(goHome)
        describeCapture(capture)
        capture.action = #selector(capture(_:))
        describe(
            rotate,
            symbol: "rotate.right",
            title: "Rotate",
            tip: "Rotate Right (\u{2318}\u{2192}, hold \u{2325} for left)"
        )
        rotate.action = #selector(rotateDevice)

        for item in items {
            item.target = self
            item.visibilityPriority = .high
        }
    }

    func install(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "odh.device")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        if #available(macOS 15, *) {
            toolbar.allowsDisplayModeCustomization = false
        }
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
    }

    /// While a recording runs the camera becomes the way to stop it, so one button covers both
    /// rather than taking a second slot.
    func setRecording(_ recording: Bool) {
        guard isRecording != recording else { return }
        isRecording = recording
        describeCapture(captureItem)
    }

    /// Greyed out while the device is gone, so the buttons cannot be pressed at a device that is
    /// not there. Enforced through validation rather than by switching autovalidation off, which
    /// would also give up AppKit's own handling of the items.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        for item in items { item.isEnabled = enabled }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        isEnabled
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + items.map(\.itemIdentifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        items.first { $0.itemIdentifier == identifier }
    }

    private func describeCapture(_ item: NSToolbarItem) {
        if isRecording {
            describe(item, symbol: "stop.circle", title: "Stop Recording", tip: "Stop Recording (\u{2318}R)")
            item.image = item.image?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            )
        } else {
            describe(
                item,
                symbol: "camera.on.rectangle",
                title: "Screenshot",
                tip: "Screenshot (\u{2318}S)"
            )
        }
    }

    private func describe(_ item: NSToolbarItem, symbol: String, title: String, tip: String) {
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.label = title
        item.paletteLabel = title
        item.toolTip = tip
    }

    @objc private func goHome() { actions.goHome() }

    @objc private func capture(_ sender: Any?) {
        if isRecording {
            actions.stopRecording()
        } else {
            actions.saveScreenshot()
        }
    }

    @objc private func rotateDevice() {
        actions.rotate(NSApp.currentEvent?.modifierFlags.contains(.option) == true)
    }
}
