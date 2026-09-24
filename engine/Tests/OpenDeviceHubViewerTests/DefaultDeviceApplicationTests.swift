import XCTest
@testable import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// More than one app can claim the devices scheme, and on a developer's Mac more than one usually
/// does. Handing it back has to mean handing it back to whoever had it, not to whichever app this
/// one assumes was there.
@MainActor
final class DefaultDeviceApplicationTests: XCTestCase {
    private let ours = "io.github.mastersam07.simviewer"
    private let deviceHub = "com.apple.dt.Devices"

    func testItGoesBackToWhoeverHeldIt() {
        XCTAssertEqual(
            DefaultDeviceApplication.handBackIdentifier(remembered: "app.siniulator.Siniulator", ours: ours),
            "app.siniulator.Siniulator"
        )
    }

    func testWithNothingRememberedItFallsBackToDeviceHub() {
        XCTAssertEqual(
            DefaultDeviceApplication.handBackIdentifier(remembered: nil, ours: ours),
            deviceHub
        )
    }

    /// Taking over twice must not leave this app as its own predecessor, which would make the hand
    /// back button a no-op that looks like it worked.
    func testItNeverHandsBackToItself() {
        XCTAssertEqual(
            DefaultDeviceApplication.handBackIdentifier(remembered: ours, ours: ours),
            deviceHub
        )
    }

    func testAnEmptyMemoryIsNoMemory() {
        XCTAssertEqual(
            DefaultDeviceApplication.handBackIdentifier(remembered: "", ours: ours),
            deviceHub
        )
    }
}
