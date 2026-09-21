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

final class WorkspaceOrientationValueTests: XCTestCase {
    func testTheGuestValuesAreTheOnesTheWorkspacePortExpects() {
        XCTAssertEqual(DeviceOrientation.portrait.gsEventValue, 1)
        XCTAssertEqual(DeviceOrientation.portraitUpsideDown.gsEventValue, 2)
        XCTAssertEqual(DeviceOrientation.landscapeRight.gsEventValue, 3)
        XCTAssertEqual(DeviceOrientation.landscapeLeft.gsEventValue, 4)
    }

    func testEveryOrientationHasADistinctGuestValue() {
        let values = DeviceOrientation.allCases.map(\.gsEventValue)
        XCTAssertEqual(Set(values).count, values.count)
    }
}

final class HomeGestureTests: XCTestCase {
    func testTheSwipeStartsAtTheBottomEdgeAndTravelsUp() {
        let path = HomeGesture.swipePath()
        XCTAssertGreaterThan(path[0].y, 0.98, "must begin inside the bottom edge region")
        XCTAssertLessThan(path[path.count - 1].y, 0.5, "and finish well up the screen")
    }

    func testTheSwipeStaysOnTheVerticalCentreLine() {
        for point in HomeGesture.swipePath() {
            XCTAssertEqual(point.x, 0.5, accuracy: 0.0001)
        }
    }

    func testTheSwipeHasEnoughIntermediatePoints() {
        // A contact that jumps reads as a tap, so the path needs real intermediate steps.
        XCTAssertGreaterThan(HomeGesture.swipePath().count, 10)
    }

    func testEveryPointIsOnScreen() {
        for point in HomeGesture.swipePath() {
            XCTAssertTrue((0...1).contains(point.x))
            XCTAssertTrue((0...1).contains(point.y))
        }
    }
}

final class TouchEdgeTests: XCTestCase {
    func testEachEdgeHasTheValueTheGuestRecognises() {
        XCTAssertEqual(IndigoHID.edgeValue(for: .none), 0)
        XCTAssertEqual(IndigoHID.edgeValue(for: .top), 1)
        XCTAssertEqual(IndigoHID.edgeValue(for: .left), 2)
        XCTAssertEqual(IndigoHID.edgeValue(for: .bottom), 3)
        XCTAssertEqual(IndigoHID.edgeValue(for: .right), 4)
    }

    func testAPlainTouchCarriesNoEdge() {
        let event = TouchEvent(phase: .began, points: [CGPoint(x: 0.5, y: 0.5)])
        XCTAssertEqual(event.edge, TouchEvent.Edge.none)
    }

    func testTheHomeSwipeIsSentFromTheBottomEdge() {
        let event = TouchEvent(phase: .began, points: [HomeGesture.swipePath()[0]], edge: .bottom)
        XCTAssertEqual(IndigoHID.edgeValue(for: event.edge), 3)
    }
}

final class ShownToDeviceSpaceTests: XCTestCase {
    private let phone = CGSize(width: 750, height: 1334)

    /// The viewer normalizes against the displayed size and then turns the result into portrait
    /// native space itself, so that two step path has to agree with the one step mapper.
    func testTheTwoStepPathAgreesWithTheOrientationAwareMapper() {
        for orientation in DeviceOrientation.allCases {
            let displayed = orientation.displayedSize(portraitNative: phone)
            let view = CGSize(width: displayed.width / 2, height: displayed.height / 2)
            for point in [CGPoint(x: 10, y: 20), CGPoint(x: 300, y: 90), CGPoint(x: 0, y: 0)] {
                let oneStep = CoordinateMapper.normalize(
                    viewPoint: point,
                    viewSize: view,
                    pixelSize: phone,
                    orientation: orientation
                )
                let shown = CoordinateMapper.normalize(
                    viewPoint: point,
                    viewSize: view,
                    pixelSize: displayed
                )
                let twoStep = shown.map {
                    CoordinateMapper.portraitNativePoint(from: $0, orientation: orientation)
                }
                XCTAssertEqual(oneStep?.x ?? -1, twoStep?.x ?? -2, accuracy: 0.0001)
                XCTAssertEqual(oneStep?.y ?? -1, twoStep?.y ?? -2, accuracy: 0.0001)
            }
        }
    }

    func testTurningBackAndForthReturnsTheSamePoint() {
        let point = CGPoint(x: 0.31, y: 0.78)
        for orientation in DeviceOrientation.allCases {
            let there = CoordinateMapper.portraitNativePoint(from: point, orientation: orientation)
            let back = CoordinateMapper.portraitNativePoint(
                from: CoordinateMapper.portraitNativePoint(
                    from: CoordinateMapper.portraitNativePoint(from: there, orientation: orientation),
                    orientation: orientation
                ),
                orientation: orientation
            )
            XCTAssertEqual(back.x, point.x, accuracy: 0.0001)
            XCTAssertEqual(back.y, point.y, accuracy: 0.0001)
        }
    }
}
