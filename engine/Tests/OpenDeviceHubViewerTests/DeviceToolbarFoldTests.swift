import AppKit
import XCTest
@testable import OpenDeviceHubViewer

/// The fold positions reach the native toolbar only while they are needed there.
@MainActor
final class DeviceToolbarFoldTests: XCTestCase {
    private func makeToolbar() -> (DeviceToolbar, NSWindow) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let toolbar = DeviceToolbar(actions: DeviceToolbarActions(
            goHome: {}, saveScreenshot: {}, stopRecording: {}, rotate: { _ in }
        ))
        toolbar.install(on: window)
        return (toolbar, window)
    }

    func testTheFoldPositionsComeAndGo() {
        let (toolbar, window) = makeToolbar()
        XCTAssertFalse(toolbar.hasFoldModes, "an ordinary toolbar carries no fold positions")
        XCTAssertEqual(window.toolbar?.items.count, 4, "flexible space, home, screenshot, rotate")

        toolbar.setFoldModes(visible: true)
        XCTAssertTrue(toolbar.hasFoldModes)
        XCTAssertEqual(window.toolbar?.items.first?.itemIdentifier.rawValue, "odh.fold", "leading the row")
        XCTAssertEqual(window.toolbar?.items.count, 5)

        // Asking twice adds nothing twice.
        toolbar.setFoldModes(visible: true)
        XCTAssertEqual(window.toolbar?.items.count, 5)

        toolbar.setFoldModes(visible: false)
        XCTAssertFalse(toolbar.hasFoldModes)
        XCTAssertEqual(window.toolbar?.items.count, 4)
    }

    func testTheSelectionFollowsTheAngleAndReportsAChoice() {
        let (toolbar, window) = makeToolbar()
        toolbar.setFoldModes(visible: true)
        let control = try? XCTUnwrap(window.toolbar?.items.first?.view as? NSSegmentedControl)
        toolbar.showFoldAngle(0)
        XCTAssertEqual(control?.selectedSegment, DeviceControlBar.FoldMode.cover.rawValue)
        toolbar.showFoldAngle(180)
        XCTAssertEqual(control?.selectedSegment, DeviceControlBar.FoldMode.fullyOpen.rawValue)

        var chosen: DeviceControlBar.FoldMode?
        toolbar.onFoldMode = { chosen = $0 }
        control?.selectedSegment = DeviceControlBar.FoldMode.partiallyOpen.rawValue
        control?.sendAction(control?.action, to: control?.target)
        XCTAssertEqual(chosen, .partiallyOpen)
    }
}
