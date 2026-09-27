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
        var harness = MenuHarness()
        harness.hasCameraControl = { frontHasOne }
        harness.pressButton = { pressed.append($0) }
        let target = harness.install()
        let (item, menu) = try XCTUnwrap(MenuHarness.item(titled: "Camera Control"))
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
        var harness = MenuHarness()
        harness.hasCameraControl = { true }
        harness.install()
        let (item, menu) = try XCTUnwrap(MenuHarness.item(titled: "Camera Control"))
        let index = menu.index(of: item)
        XCTAssertEqual(menu.item(at: index - 1)?.title, "Action Button")
        XCTAssertEqual(menu.item(at: index + 1)?.title, "Siri")
    }
}
