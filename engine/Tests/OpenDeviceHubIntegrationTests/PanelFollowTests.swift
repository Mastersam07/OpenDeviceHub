import AppKit
import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// A foldable's window follows its guest between the two panels without going anywhere: the same
/// window, the same shape, both pictures still there. Only the touch target, the face a click is
/// tested against and the screenshot follow the guest.
@MainActor
final class PanelFollowTests: XCTestCase {
    func testTheWindowStaysPutWhenTheGuestMoves() throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("no booted foldable") }

        let panels = try adapter.panels(device.udid)
        guard let unfolded = panels.first(where: { $0.name == "Unfolded" }),
              let cover = panels.first(where: { $0.name == "Cover" }) else {
            throw XCTSkip("not a foldable")
        }

        // A frame remembered from an earlier run would move the window, so this one forgets, and
        // closing its window must leave the device running rather than shut it down as a real
        // window would under the user's own setting.
        let manager = DeviceWindowManager(
            frameStore: WindowFrameStore(storage: ForgetfulStorage()),
            shutdown: { _ in }
        )
        var targets: [Int] = []
        let controller = try manager.open(
            device: device,
            session: try adapter.openDisplay(device.udid, panel: unfolded),
            input: nil,
            scaleMode: .fit,
            bezelEnabled: false,
            keepOnTop: false,
            showFPS: false,
            foldsAtHinge: true,
            panelNativeRotation: unfolded.nativeRotation,
            unfoldedPanel: unfolded,
            cover: FoldableCover(panel: cover, session: try adapter.openDisplay(device.udid, panel: cover)),
            retarget: { targets.append($0) }
        )
        defer { manager.close(device.udid) }
        let window = try XCTUnwrap(controller.window)
        let frame = window.frame
        XCTAssertEqual(controller.screenPixelSize, unfolded.pixelSize)

        controller.setActivePanel(screenID: cover.screenID)
        XCTAssertEqual(manager.openCount, 1, "no second window was made")
        XCTAssertTrue(controller.window === window, "the same window carried on")
        XCTAssertTrue(window.isVisible, "and it never went away")
        XCTAssertEqual(window.frame, frame, "and it did not change shape or move")
        XCTAssertEqual(controller.screenPixelSize, unfolded.pixelSize, "the window's own session is untouched")
        XCTAssertEqual(targets, [cover.screenID], "touches now go to the cover")

        controller.setActivePanel(screenID: unfolded.screenID)
        XCTAssertEqual(window.frame, frame)
        XCTAssertEqual(targets, [cover.screenID, unfolded.screenID], "and back")

        // Saying it again changes nothing.
        controller.setActivePanel(screenID: unfolded.screenID)
        XCTAssertEqual(targets.count, 2)
    }
}

private final class ForgetfulStorage: PreferenceStorage, @unchecked Sendable {
    func text(forKey key: String) -> String? { nil }
    func setText(_ text: String, forKey key: String) {}
    func removeText(forKey key: String) {}
    func keys(withPrefix prefix: String) -> [String] { [] }
}
