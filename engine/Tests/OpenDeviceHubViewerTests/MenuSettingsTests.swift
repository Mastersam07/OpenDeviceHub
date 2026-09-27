import AppKit
import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

@MainActor
final class MenuSettingsTests: XCTestCase {
    private var previousMenu: NSMenu?

    override func setUp() async throws {
        previousMenu = NSApplication.shared.mainMenu
    }

    override func tearDown() async throws {
        NSApplication.shared.mainMenu = previousMenu
    }

    func testTheSyncItemFollowsTheSettingWhoeverChangesIt() throws {
        var syncs = true
        var harness = MenuHarness()
        harness.syncsPasteboard = { syncs }
        let target = harness.install()
        let (sync, _) = try XCTUnwrap(MenuHarness.item(titled: "Automatically Sync Pasteboard"))
        let (get, _) = try XCTUnwrap(MenuHarness.item(titled: "Get Pasteboard"))
        XCTAssertTrue(target.validateMenuItem(sync))
        XCTAssertEqual(sync.state, .on)
        XCTAssertFalse(target.validateMenuItem(get), "the manual half is offered while syncing")

        syncs = false
        XCTAssertTrue(target.validateMenuItem(sync))
        XCTAssertEqual(sync.state, .off, "the tick missed sync being turned off in Settings")
        XCTAssertTrue(target.validateMenuItem(get), "the manual half stayed greyed after sync went off")
    }

    func testChoosingTheSyncItemTogglesTheCurrentSetting() throws {
        var syncs = true
        var sent: [Bool] = []
        var harness = MenuHarness()
        harness.syncsPasteboard = { syncs }
        harness.toggleAutomaticPasteboardSync = { value in
            sent.append(value)
            syncs = value
        }
        let target = harness.install()
        let (sync, _) = try XCTUnwrap(MenuHarness.item(titled: "Automatically Sync Pasteboard"))

        syncs = false
        target.automaticPasteboardSync(sync)
        XCTAssertEqual(sent, [true], "the menu flipped a value Settings had already changed")
        XCTAssertEqual(sync.state, .on)
    }

    func testAFavoriteIsListedAndChosenFromTheLocationMenu() throws {
        let lagos = LocationFavorite(name: "Lagos", latitude: 6.5244, longitude: 3.3792)
        var favorites: [LocationFavorite] = []
        var chosen: [LocationFavorite] = []
        var harness = MenuHarness()
        harness.locationFavorites = { favorites }
        harness.setFavoriteLocation = { chosen.append($0) }
        let target = harness.install()
        XCTAssertNil(MenuHarness.item(titled: "Lagos"))

        favorites = [lagos]
        let (_, locationMenu) = try XCTUnwrap(MenuHarness.item(titled: "Custom Location\u{2026}"))
        target.menuNeedsUpdate(locationMenu)
        let (item, _) = try XCTUnwrap(MenuHarness.item(titled: "Lagos"), "a favorite added in Settings is missing")
        NSApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
        XCTAssertEqual(chosen, [lagos])
    }

    func testEachTickShowsTheDeviceInFront() throws {
        let titles: [ViewerMenu.DeviceSetting: String] = [
            .keyboardInput: "Send Keyboard Input to Device",
            .hardwareKeyboard: "Connect Hardware Keyboard",
            .keyboardLanguage: "Use the Same Keyboard Language as macOS",
            .increasedContrast: "Toggle Increase Contrast",
            .slowAnimations: "Slow Animations",
            .latencyOverlay: "Show Click to Frame Latency",
            .bezel: "Show Device Bezels",
            .keepOnTop: "Stay On Top",
        ]
        XCTAssertEqual(Set(titles.keys), Set(ViewerMenu.DeviceSetting.allCases))
        var inFront: Set<ViewerMenu.DeviceSetting> = []
        var harness = MenuHarness()
        harness.isOn = { inFront.contains($0) }
        let target = harness.install()

        for (setting, title) in titles {
            let (item, _) = try XCTUnwrap(MenuHarness.item(titled: title), title)
            inFront = [setting]
            _ = target.validateMenuItem(item)
            XCTAssertEqual(item.state, .on, "\(title) missed the device in front having it on")
            inFront = []
            _ = target.validateMenuItem(item)
            XCTAssertEqual(item.state, .off, "\(title) missed the device in front having it off")
        }
    }

    func testTogglingKeyboardInputFlipsTheDeviceInFront() throws {
        var sent: [Bool] = []
        var harness = MenuHarness()
        harness.isOn = { $0 != .keyboardInput }
        harness.toggleKeyboardInput = { sent.append($0) }
        let target = harness.install()
        let (item, _) = try XCTUnwrap(MenuHarness.item(titled: "Send Keyboard Input to Device"))
        target.keyboardInput(item)
        XCTAssertEqual(sent, [true], "the front device had keyboard input off, so it should turn on")
    }

    func testShutDownSitsAfterRestart() throws {
        var shutDowns = 0
        var harness = MenuHarness()
        harness.shutdown = { shutDowns += 1 }
        // A menu item holds its target weakly, so the test keeps it the way the app does.
        let target = harness.install()
        let (item, menu) = try XCTUnwrap(MenuHarness.item(titled: "Shut Down"))
        XCTAssertEqual(menu.item(at: menu.index(of: item) - 1)?.title, "Restart")
        let action = try XCTUnwrap(item.action)
        withExtendedLifetime(target) {
            NSApplication.shared.sendAction(action, to: item.target, from: item)
        }
        XCTAssertEqual(shutDowns, 1)
    }
}
