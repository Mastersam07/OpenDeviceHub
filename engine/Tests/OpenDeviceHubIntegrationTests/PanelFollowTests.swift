import AppKit
import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// A foldable's window follows its guest between the two panels. It has to do that without going
/// away: a new window blinks, and for that moment an app set to quit with its last window has none.
@MainActor
final class PanelFollowTests: XCTestCase {
    func testTheWindowItselfSurvivesTheSwitch() throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("no booted foldable") }

        let panels = try adapter.panels(device.udid)
        guard panels.count > 1,
              let unfolded = panels.first(where: { $0.name == "Unfolded" }),
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
        let controller = try manager.open(
            device: device,
            session: try adapter.openDisplay(device.udid, panel: unfolded),
            input: nil,
            scaleMode: .fit,
            bezelEnabled: false,
            keepOnTop: false,
            showFPS: false,
            foldsAtHinge: true,
            panelNativeRotation: unfolded.nativeRotation
        )
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(controller.screenPixelSize, unfolded.pixelSize)
        let unfoldedFrame = window.frame

        controller.showPanel(
            session: try adapter.openDisplay(device.udid, panel: cover),
            input: nil,
            chrome: nil,
            nativeRotation: cover.nativeRotation,
            showingCover: true
        )

        XCTAssertEqual(manager.openCount, 1, "no second window was made")
        XCTAssertTrue(manager.controller(for: device.udid) === controller)
        XCTAssertTrue(controller.window === window, "the same window carried on")
        XCTAssertTrue(window.isVisible, "and it never went away")
        XCTAssertEqual(controller.screenPixelSize, cover.pixelSize, "it shows the other panel now")
        // The two panels are different shapes, so the window takes the shape of the one it shows.
        let coverFrame = window.frame
        XCTAssertNotEqual(
            coverFrame.size, unfoldedFrame.size,
            "the window kept the shape of the panel it is no longer showing"
        )
        XCTAssertEqual(
            coverFrame.width / coverFrame.height,
            cover.pixelSize.width / cover.pixelSize.height,
            accuracy: 0.25,
            "the window is not the shape of the cover"
        )
        XCTAssertEqual(coverFrame.maxY, unfoldedFrame.maxY, accuracy: 1, "the top edge moved")

        controller.showPanel(
            session: try adapter.openDisplay(device.udid, panel: unfolded),
            input: nil,
            chrome: nil,
            nativeRotation: unfolded.nativeRotation,
            showingCover: false
        )
        XCTAssertEqual(controller.screenPixelSize, unfolded.pixelSize, "and back again")
        XCTAssertTrue(controller.window === window)
        XCTAssertEqual(window.frame.size, unfoldedFrame.size, "and so does its shape")
        manager.close(device.udid)
    }
}

private final class ForgetfulStorage: PreferenceStorage, @unchecked Sendable {
    func text(forKey key: String) -> String? { nil }
    func setText(_ text: String, forKey key: String) {}
    func removeText(forKey key: String) {}
    func keys(withPrefix prefix: String) -> [String] { [] }
}
