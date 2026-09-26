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

extension PanelFollowTests {
    /// A frame remembered by an earlier version, which reshaped the window for each panel, is tall.
    /// The open device does not fit a tall frame; the window takes the frame's place and width and
    /// the device's own shape.
    func testATallRememberedFrameIsGivenTheDevicesShape() throws {
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

        let remembering = RememberingStorage()
        remembering.setText("644.0,165.0,439.0,666.0", forKey: "opendevicehub.window.\(device.udid)")
        let manager = DeviceWindowManager(
            frameStore: WindowFrameStore(storage: remembering, prefix: "opendevicehub.window."),
            shutdown: { _ in }
        )
        let controller = try manager.open(
            device: device,
            session: try adapter.openDisplay(device.udid, panel: unfolded),
            input: nil,
            scaleMode: .fit,
            bezelEnabled: true,
            keepOnTop: false,
            showFPS: false,
            foldsAtHinge: true,
            panelNativeRotation: unfolded.nativeRotation,
            unfoldedPanel: unfolded,
            cover: FoldableCover(panel: cover, session: try adapter.openDisplay(device.udid, panel: cover))
        )
        defer { manager.close(device.udid) }
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView).bounds.size
        print("RESULT remembered 439x666 became a window with content \(Int(content.width))x\(Int(content.height))")
        XCTAssertEqual(window.frame.width, 439, accuracy: 1, "the remembered width is kept")
        XCTAssertLessThan(content.height, 420, "the open device does not want a tall frame")
        // The device area is the open device's shape: wider than it is tall.
        let deviceArea = content.height - PresentationLayout.barHeight
            - PresentationLayout.deviceTopMargin - PresentationLayout.deviceBottomMargin
        XCTAssertEqual(content.width / deviceArea, 2853.0 / 2007.0 * (content.width / (content.width - 24)), accuracy: 0.15)
    }
}

private final class RememberingStorage: PreferenceStorage, @unchecked Sendable {
    private var values: [String: String] = [:]
    func text(forKey key: String) -> String? { values[key] }
    func setText(_ text: String, forKey key: String) { values[key] = text }
    func removeText(forKey key: String) { values[key] = nil }
    func keys(withPrefix prefix: String) -> [String] { values.keys.filter { $0.hasPrefix(prefix) } }
}

private final class ForgetfulStorage: PreferenceStorage, @unchecked Sendable {
    func text(forKey key: String) -> String? { nil }
    func setText(_ text: String, forKey key: String) {}
    func removeText(forKey key: String) {}
    func keys(withPrefix prefix: String) -> [String] { [] }
}
