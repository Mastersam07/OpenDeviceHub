import AppKit
import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

final class DeviceWindowTransitionTests: XCTestCase {
    func testALiveWindowDetachesWhenItsDeviceGoes() {
        XCTAssertEqual(
            DeviceWindowTransition.forState(.shuttingDown, isDetached: false),
            .detach(.shutDown)
        )
        XCTAssertEqual(
            DeviceWindowTransition.forState(.shutdown, isDetached: false),
            .detach(.shutDown)
        )
    }

    /// Shutting down is reported before shutdown, so the second one must not reset the overlay and
    /// throw away the reboot it may already be showing.
    func testAWindowAlreadyShowingTheShutDownStateIsLeftAlone() {
        XCTAssertEqual(DeviceWindowTransition.forState(.shuttingDown, isDetached: true), .ignore)
        XCTAssertEqual(DeviceWindowTransition.forState(.shutdown, isDetached: true), .ignore)
    }

    func testAWaitingWindowShowsTheBoot() {
        XCTAssertEqual(DeviceWindowTransition.forState(.booting, isDetached: true), .detach(.booting))
    }

    func testALiveWindowIgnoresABoot() {
        XCTAssertEqual(DeviceWindowTransition.forState(.booting, isDetached: false), .ignore)
        XCTAssertEqual(DeviceWindowTransition.forState(.booted, isDetached: false), .ignore)
    }

    func testAWaitingWindowReattachesOnceTheDeviceIsUp() {
        XCTAssertEqual(DeviceWindowTransition.forState(.booted, isDetached: true), .reattach)
    }

    func testAnUnknownStateChangesNothing() {
        XCTAssertEqual(DeviceWindowTransition.forState(.unknown, isDetached: true), .ignore)
        XCTAssertEqual(DeviceWindowTransition.forState(.unknown, isDetached: false), .ignore)
    }
}

@MainActor
final class ShutdownOverlayViewTests: XCTestCase {
    private func button(in overlay: ShutdownOverlayView) throws -> NSButton {
        let found = overlay.subviews
            .flatMap { [$0] + $0.subviews }
            .compactMap { $0 as? NSButton }
            .first
        return try XCTUnwrap(found, "the overlay should offer a button")
    }

    func testTheButtonRebootsAndThenShowsThatItIsStartingUp() throws {
        let overlay = ShutdownOverlayView(deviceName: "iPhone 17")
        var reboots = 0
        overlay.onReboot = { reboots += 1 }

        let reboot = try button(in: overlay)
        XCTAssertEqual(reboot.title, "Reboot")
        XCTAssertFalse(reboot.isHidden)

        reboot.performClick(nil)

        XCTAssertEqual(reboots, 1)
        XCTAssertTrue(reboot.isHidden, "a boot is under way, so there is nothing left to press")
    }

    func testTheButtonComesBackWhenABootFails() throws {
        let overlay = ShutdownOverlayView(deviceName: "iPhone 17")
        let reboot = try button(in: overlay)
        reboot.performClick(nil)
        XCTAssertTrue(reboot.isHidden)

        overlay.setFailed("no such device")
        XCTAssertFalse(reboot.isHidden)
        XCTAssertTrue(reboot.isEnabled)
    }
}
