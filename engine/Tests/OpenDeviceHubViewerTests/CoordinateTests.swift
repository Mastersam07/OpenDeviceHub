import XCTest
@testable import OpenDeviceHubViewer

final class CoordinateTests: XCTestCase {
    func testAPlainPair() {
        let point = Coordinate(parsing: "37.3349, -122.0090")
        XCTAssertEqual(point?.latitude, 37.3349)
        XCTAssertEqual(point?.longitude, -122.009)
    }

    func testSpacingDoesNotMatter() {
        XCTAssertEqual(Coordinate(parsing: "37.3349,-122.009"), Coordinate(parsing: "  37.3349 , -122.009  "))
    }

    func testWholeNumbersAreFine() {
        XCTAssertEqual(Coordinate(parsing: "0,0")?.latitude, 0)
    }

    /// Out of range is the failure that would otherwise reach simctl and be rejected there, or worse
    /// be accepted and put the device somewhere impossible.
    func testOutOfRangeIsRefused() {
        XCTAssertNil(Coordinate(parsing: "91, 0"))
        XCTAssertNil(Coordinate(parsing: "-91, 0"))
        XCTAssertNil(Coordinate(parsing: "0, 181"))
        XCTAssertNil(Coordinate(parsing: "0, -181"))
    }

    func testTheEdgesAreAllowed() {
        XCTAssertNotNil(Coordinate(parsing: "90, 180"))
        XCTAssertNotNil(Coordinate(parsing: "-90, -180"))
    }

    func testNonsenseIsRefused() {
        for text in ["", "37.3349", "37.3349, -122.009, 5", "here, there", "37.3349 -122.009"] {
            XCTAssertNil(Coordinate(parsing: text), "accepted \(text)")
        }
    }
}
