import AppKit
import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

@MainActor
final class CameraControlMenuTests: XCTestCase {
    private var previousMenu: NSMenu?

    override func setUp() async throws {
        previousMenu = NSApplication.shared.mainMenu
    }

    override func tearDown() async throws {
        NSApplication.shared.mainMenu = previousMenu
    }

    func testTheItemFollowsTheDeviceInFront() throws {
        var frontHasOne = false
        var pressed: [HardwareButton] = []
        let target = install(hasCameraControl: { frontHasOne }, pressButton: { pressed.append($0) })
        let (item, menu) = try cameraControlItem()
        XCTAssertTrue(item.isHidden, "offered for a device without the button")

        frontHasOne = true
        target.menuNeedsUpdate(menu)
        XCTAssertFalse(item.isHidden, "not offered for a device with the button")

        let action = try XCTUnwrap(item.action)
        NSApplication.shared.sendAction(action, to: item.target, from: item)
        XCTAssertEqual(pressed, [.cameraControl])

        frontHasOne = false
        target.menuNeedsUpdate(menu)
        XCTAssertTrue(item.isHidden, "still offered once the device in front has no button")
    }

    func testItSitsWithTheOtherHardwareButtons() throws {
        install(hasCameraControl: { true }, pressButton: { _ in })
        let (item, menu) = try cameraControlItem()
        let index = menu.index(of: item)
        XCTAssertEqual(menu.item(at: index - 1)?.title, "Action Button")
        XCTAssertEqual(menu.item(at: index + 1)?.title, "Siri")
    }

    private func cameraControlItem() throws -> (NSMenuItem, NSMenu) {
        let menus = NSApplication.shared.mainMenu?.items.compactMap(\.submenu) ?? []
        for menu in menus {
            if let item = menu.items.first(where: { $0.title == "Camera Control" }) {
                return (item, menu)
            }
        }
        throw XCTSkip("no Camera Control item")
    }

    @discardableResult
    private func install(
        hasCameraControl: @escaping () -> Bool,
        pressButton: @escaping (HardwareButton) -> Void
    ) -> MenuTarget {
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
                erase: {},
                stepTextSize: { _ in },
                toggleIncreaseContrast: {},
                triggerICloudSync: {},
                setLocation: { _ in },
                setCustomLocation: {},
                toggleKeyboardInput: { _ in },
                toggleHardwareKeyboard: { _ in },
                matchKeyboardLanguage: { _ in },
                toggleAutomaticPasteboardSync: { _ in },
                getPasteboard: {},
                sendPasteboard: {},
                syncsPasteboard: { false },
                panels: { [] },
                currentPanel: { nil },
                showPanel: { _ in },
                setOrientation: { _ in },
                appSwitcher: {},
                stopRecording: {},
                isRecording: { false }
            ),
            capabilities: [.hardwareButtons, .touch, .rotation, .shake]
        )
    }
}
