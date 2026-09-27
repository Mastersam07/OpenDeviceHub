import CoreGraphics
import XCTest
@testable import OpenDeviceHubEngine

final class DevicePanelTests: XCTestCase {
    private let unfolded = CGSize(width: 2007, height: 2853)
    private let cover = CGSize(width: 1398, height: 2034)

    func testASingleScreenNeedsNoName() {
        XCTAssertEqual(DevicePanel.name(at: 0, of: [unfolded]), "Screen")
    }

    func testTwoPanelsAreNamedByWhichIsLarger() {
        let sizes = [unfolded, cover]
        XCTAssertEqual(DevicePanel.name(at: 0, of: sizes), "Unfolded")
        XCTAssertEqual(DevicePanel.name(at: 1, of: sizes), "Cover")
    }

    /// Port order is not something to rely on, so the names follow the sizes rather than the order.
    func testTheOrderOfTheTwoDoesNotDecideTheNames() {
        let sizes = [cover, unfolded]
        XCTAssertEqual(DevicePanel.name(at: 0, of: sizes), "Cover")
        XCTAssertEqual(DevicePanel.name(at: 1, of: sizes), "Unfolded")
    }

    func testTwoPanelsOfEqualAreaAreNumberedRatherThanGuessedAt() {
        let sizes = [unfolded, unfolded]
        XCTAssertEqual(DevicePanel.name(at: 0, of: sizes), "Screen 1")
        XCTAssertEqual(DevicePanel.name(at: 1, of: sizes), "Screen 2")
    }

    /// Nothing has three built in screens today, so they are numbered rather than named.
    func testMoreThanTwoAreNumbered() {
        let sizes = [unfolded, cover, cover]
        XCTAssertEqual(DevicePanel.name(at: 0, of: sizes), "Screen 1")
        XCTAssertEqual(DevicePanel.name(at: 2, of: sizes), "Screen 3")
    }
}
