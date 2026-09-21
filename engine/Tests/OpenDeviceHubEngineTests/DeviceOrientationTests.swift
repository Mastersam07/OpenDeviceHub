import XCTest
@testable import OpenDeviceHubEngine

private let phone = CGSize(width: 1206, height: 2622)

final class DeviceOrientationTests: XCTestCase {
    func testLandscapeSwapsTheAxes() {
        XCTAssertEqual(DeviceOrientation.portrait.displayedSize(portraitNative: phone), phone)
        XCTAssertEqual(DeviceOrientation.portraitUpsideDown.displayedSize(portraitNative: phone), phone)
        let swapped = CGSize(width: 2622, height: 1206)
        XCTAssertEqual(DeviceOrientation.landscapeLeft.displayedSize(portraitNative: phone), swapped)
        XCTAssertEqual(DeviceOrientation.landscapeRight.displayedSize(portraitNative: phone), swapped)
    }

    func testRotatingLeftFourTimesReturnsToTheStart() {
        for orientation in DeviceOrientation.allCases {
            var turned = orientation
            for _ in 0..<4 { turned = turned.rotatedLeft }
            XCTAssertEqual(turned, orientation)
        }
    }

    func testRotatingRightUndoesRotatingLeft() {
        for orientation in DeviceOrientation.allCases {
            XCTAssertEqual(orientation.rotatedLeft.rotatedRight, orientation, "\(orientation)")
        }
    }

    func testDegreesAreDistinctAndOrdered() {
        XCTAssertEqual(DeviceOrientation.portrait.degrees, 0)
        XCTAssertEqual(DeviceOrientation.landscapeLeft.degrees, 90)
        XCTAssertEqual(DeviceOrientation.portraitUpsideDown.degrees, 180)
        XCTAssertEqual(DeviceOrientation.landscapeRight.degrees, 270)
    }
}

final class OrientedCoordinateTests: XCTestCase {
    /// The centre must stay the centre whichever way the device is turned.
    func testTheCentreIsInvariant() {
        for orientation in DeviceOrientation.allCases {
            let mapped = CoordinateMapper.portraitNativePoint(
                from: CGPoint(x: 0.5, y: 0.5), orientation: orientation
            )
            XCTAssertEqual(mapped.x, 0.5, accuracy: 0.0001, "\(orientation)")
            XCTAssertEqual(mapped.y, 0.5, accuracy: 0.0001, "\(orientation)")
        }
    }

    func testPortraitIsIdentity() {
        let point = CGPoint(x: 0.25, y: 0.75)
        XCTAssertEqual(CoordinateMapper.portraitNativePoint(from: point, orientation: .portrait), point)
    }

    func testUpsideDownMirrorsBothAxes() {
        let mapped = CoordinateMapper.portraitNativePoint(
            from: CGPoint(x: 0.25, y: 0.75), orientation: .portraitUpsideDown
        )
        XCTAssertEqual(mapped.x, 0.75, accuracy: 0.0001)
        XCTAssertEqual(mapped.y, 0.25, accuracy: 0.0001)
    }

    /// Turned left, the top left of what you see is the bottom left of the device.
    func testLandscapeLeftCorners() {
        let topLeft = CoordinateMapper.portraitNativePoint(from: CGPoint(x: 0, y: 0), orientation: .landscapeLeft)
        XCTAssertEqual(topLeft.x, 0, accuracy: 0.0001)
        XCTAssertEqual(topLeft.y, 1, accuracy: 0.0001)

        let topRight = CoordinateMapper.portraitNativePoint(from: CGPoint(x: 1, y: 0), orientation: .landscapeLeft)
        XCTAssertEqual(topRight.x, 0, accuracy: 0.0001)
        XCTAssertEqual(topRight.y, 0, accuracy: 0.0001)
    }

    func testLandscapeRightCorners() {
        let topLeft = CoordinateMapper.portraitNativePoint(from: CGPoint(x: 0, y: 0), orientation: .landscapeRight)
        XCTAssertEqual(topLeft.x, 1, accuracy: 0.0001)
        XCTAssertEqual(topLeft.y, 0, accuracy: 0.0001)
    }

    func testEveryOrientationStaysInsideTheUnitSquare() {
        let samples = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1),
                       CGPoint(x: 1, y: 1), CGPoint(x: 0.3, y: 0.8)]
        for orientation in DeviceOrientation.allCases {
            for point in samples {
                let mapped = CoordinateMapper.portraitNativePoint(from: point, orientation: orientation)
                XCTAssertTrue((0...1).contains(mapped.x), "\(orientation) \(point) -> \(mapped)")
                XCTAssertTrue((0...1).contains(mapped.y), "\(orientation) \(point) -> \(mapped)")
            }
        }
    }

    func testFourLeftTurnsMapAPointBackToItself() {
        let start = CGPoint(x: 0.3, y: 0.8)
        var point = start
        for _ in 0..<4 {
            point = CoordinateMapper.portraitNativePoint(from: point, orientation: .landscapeLeft)
        }
        XCTAssertEqual(point.x, start.x, accuracy: 0.0001)
        XCTAssertEqual(point.y, start.y, accuracy: 0.0001)
    }

    func testAClickInALandscapeViewLandsOnTheRightPartOfTheDevice() {
        // A landscape view of a 1206x2622 phone is 2622x1206. A click in the middle of the left
        // edge should reach the bottom middle of the portrait native screen.
        let view = CGSize(width: 2622, height: 1206)
        let mapped = CoordinateMapper.normalize(
            viewPoint: CGPoint(x: 0, y: 603),
            viewSize: view,
            pixelSize: phone,
            orientation: .landscapeLeft
        )
        XCTAssertEqual(mapped?.x ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(mapped?.y ?? -1, 1, accuracy: 0.001)
    }
}
