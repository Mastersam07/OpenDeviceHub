import AppKit
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// Installs the app menu with every action doing nothing except the ones a test sets.
@MainActor
struct MenuHarness {
    var pressButton: (HardwareButton) -> Void = { _ in }
    var hasCameraControl: () -> Bool = { false }
    var shutdown: () -> Void = {}
    var syncsPasteboard: () -> Bool = { false }
    var toggleAutomaticPasteboardSync: (Bool) -> Void = { _ in }
    var locationFavorites: () -> [LocationFavorite] = { [] }
    var setFavoriteLocation: (LocationFavorite) -> Void = { _ in }

    @discardableResult
    func install() -> MenuTarget {
        ViewerMenu.install(
            into: NSApplication.shared,
            actions: ViewerMenu.Actions(
                setScaleMode: { _ in },
                toggleBezel: {},
                toggleKeepOnTop: {},
                pasteToDevice: {},
                setAppearance: { _ in },
                saveScreenshot: {},
                copyScreenshot: {},
                toggleRecording: {},
                simulateMemoryWarning: {},
                openSystemLog: {},
                openAppData: {},
                shake: {},
                toggleSlowAnimations: {},
                toggleLatencyOverlay: {},
                pressButton: pressButton,
                hasCameraControl: hasCameraControl,
                rotate: { _ in },
                restart: {},
                shutdown: shutdown,
                erase: {},
                stepTextSize: { _ in },
                toggleIncreaseContrast: {},
                triggerICloudSync: {},
                setLocation: { _ in },
                setCustomLocation: {},
                locationFavorites: locationFavorites,
                setFavoriteLocation: setFavoriteLocation,
                toggleKeyboardInput: { _ in },
                toggleHardwareKeyboard: { _ in },
                matchKeyboardLanguage: { _ in },
                toggleAutomaticPasteboardSync: toggleAutomaticPasteboardSync,
                getPasteboard: {},
                sendPasteboard: {},
                syncsPasteboard: syncsPasteboard,
                panels: { [] },
                currentPanel: { nil },
                showPanel: { _ in },
                setOrientation: { _ in },
                appSwitcher: {},
                stopRecording: {},
                isRecording: { false }
            ),
            capabilities: [.hardwareButtons, .touch, .rotation, .shake, .pasteboardSync]
        )
    }

    /// The item with this title and the menu holding it, looked for through every submenu.
    static func item(titled title: String) -> (NSMenuItem, NSMenu)? {
        func search(_ menu: NSMenu) -> (NSMenuItem, NSMenu)? {
            for item in menu.items {
                if item.title == title { return (item, menu) }
                if let submenu = item.submenu, let found = search(submenu) { return found }
            }
            return nil
        }
        return NSApplication.shared.mainMenu.flatMap(search)
    }
}
