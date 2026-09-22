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
@MainActor
final class DeviceToolbar: NSObject, NSToolbarDelegate {
    private enum Item {
        static let home = NSToolbarItem.Identifier("odh.home")
        static let capture = NSToolbarItem.Identifier("odh.capture")
        static let rotate = NSToolbarItem.Identifier("odh.rotate")
        static let all = [home, capture, rotate]
    }

    private let actions: DeviceToolbarActions
    private var captureItem: NSToolbarItem?
    private var isRecording = false
    private var items: [NSToolbarItem] = []
    private var isEnabled = true

    init(actions: DeviceToolbarActions) {
        self.actions = actions
    }

    func install(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "odh.device")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    /// While a recording runs the camera becomes the way to stop it, so one button covers both
    /// rather than taking a second slot.
    func setRecording(_ recording: Bool) {
        guard isRecording != recording else { return }
        isRecording = recording
        if let captureItem { describeCapture(captureItem) }
    }

    /// Greyed out while the device is gone, so the buttons cannot be pressed at a device that is
    /// not there.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        for item in items { item.isEnabled = enabled }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + Item.all
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self
        item.isBordered = true
        item.visibilityPriority = .high
        // Without this AppKit re-enables the item on its own validation pass, which would light the
        // buttons back up while the device is still gone.
        item.autovalidates = false
        item.isEnabled = isEnabled
        items.append(item)

        switch identifier {
        case Item.home:
            describe(item, symbol: "house", title: "Home", tip: "Home (\u{21E7}\u{2318}H)")
            item.action = #selector(home)
        case Item.capture:
            captureItem = item
            describeCapture(item)
            item.action = #selector(capture)
        case Item.rotate:
            describe(
                item,
                symbol: "rotate.right",
                title: "Rotate",
                tip: "Rotate Right (\u{2318}\u{2192}, hold \u{2325} for left)"
            )
            item.action = #selector(rotate)
        default:
            return nil
        }
        return item
    }

    private func describeCapture(_ item: NSToolbarItem) {
        if isRecording {
            describe(item, symbol: "stop.circle", title: "Stop Recording", tip: "Stop Recording (\u{2318}R)")
        } else {
            describe(item, symbol: "camera", title: "Screenshot", tip: "Screenshot (\u{2318}S)")
        }
    }

    private func describe(_ item: NSToolbarItem, symbol: String, title: String, tip: String) {
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.label = title
        item.paletteLabel = title
        item.toolTip = tip
    }

    @objc private func home() { actions.goHome() }

    @objc private func capture() {
        if isRecording {
            actions.stopRecording()
        } else {
            actions.saveScreenshot()
        }
    }

    @objc private func rotate() {
        actions.rotate(NSApp.currentEvent?.modifierFlags.contains(.option) == true)
    }
}
