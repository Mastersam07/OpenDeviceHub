import XCTest
@testable import OpenDeviceHubViewer

final class DeviceGeometryTests: XCTestCase {
    func testConvertsPixelsToPointsAtDeviceScale() {
        let size = DeviceGeometry.pointSize(
            pixelSize: CGSize(width: 1206, height: 2622),
            pointScale: 3
        )
        XCTAssertEqual(size, CGSize(width: 402, height: 874))
    }

    func testHandlesATwoTimesDevice() {
        let size = DeviceGeometry.pointSize(
            pixelSize: CGSize(width: 2064, height: 2752),
            pointScale: 2
        )
        XCTAssertEqual(size, CGSize(width: 1032, height: 1376))
    }

    func testFallsBackToOneWhenTheScaleIsMissing() {
        let pixels = CGSize(width: 800, height: 600)
        XCTAssertEqual(DeviceGeometry.pointSize(pixelSize: pixels, pointScale: 0), pixels)
        XCTAssertEqual(DeviceGeometry.pointSize(pixelSize: pixels, pointScale: -2), pixels)
    }
}

final class ScaleModeTests: XCTestCase {
    func testEveryModeHasADistinctDisplayName() {
        let names = ScaleMode.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(ScaleMode.pointAccurate.displayName, "Point Accurate")
    }

    func testRawValuesRoundTrip() {
        for mode in ScaleMode.allCases {
            XCTAssertEqual(ScaleMode(rawValue: mode.rawValue), mode)
        }
    }
}
