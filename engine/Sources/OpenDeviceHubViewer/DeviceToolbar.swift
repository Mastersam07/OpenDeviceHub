import AppKit

/// What the buttons above a device window do. Each window drives its own device, unlike the menu
/// bar, which acts on every open one.
public struct DeviceToolbarActions {
    public var goHome: () -> Void
    public var saveScreenshot: () -> Void
    public var rotate: () -> Void

    public init(
        goHome: @escaping () -> Void,
        saveScreenshot: @escaping () -> Void,
        rotate: @escaping () -> Void
    ) {
        self.goHome = goHome
        self.saveScreenshot = saveScreenshot
        self.rotate = rotate
    }
}

/// The row of buttons above a device, matching what the classic Simulator offers.
@MainActor
final class DeviceToolbar: NSObject, NSToolbarDelegate {
    private enum Item {
        static let home = NSToolbarItem.Identifier("odh.home")
        static let screenshot = NSToolbarItem.Identifier("odh.screenshot")
        static let rotate = NSToolbarItem.Identifier("odh.rotate")
        static let all = [home, screenshot, rotate]
    }

    private let actions: DeviceToolbarActions

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
        let described: (String, String, Selector)? = switch identifier {
        case Item.home: ("house", "Home", #selector(home))
        case Item.screenshot: ("camera", "Screenshot", #selector(screenshot))
        case Item.rotate: ("rotate.right", "Rotate", #selector(rotate))
        default: nil
        }
        guard let (symbol, title, action) = described else { return nil }

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.label = title
        item.paletteLabel = title
        item.toolTip = title
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    @objc private func home() { actions.goHome() }
    @objc private func screenshot() { actions.saveScreenshot() }
    @objc private func rotate() { actions.rotate() }
}
