import XCTest
@testable import OpenDeviceHubEngine

final class TouchPathTests: XCTestCase {
    func testIncludesBothEnds() {
        let path = TouchPath.points(from: CGPoint(x: 0.1, y: 0.2), to: CGPoint(x: 0.9, y: 0.8), steps: 4)
        XCTAssertEqual(path.count, 5)
        XCTAssertEqual(path.first?.x ?? -1, 0.1, accuracy: 0.0001)
        XCTAssertEqual(path.last?.x ?? -1, 0.9, accuracy: 0.0001)
        XCTAssertEqual(path.last?.y ?? -1, 0.8, accuracy: 0.0001)
    }

    func testPointsAreEvenlySpaced() {
        let path = TouchPath.points(from: .zero, to: CGPoint(x: 1, y: 0), steps: 4)
        for (index, point) in path.enumerated() {
            XCTAssertEqual(point.x, CGFloat(index) * 0.25, accuracy: 0.0001)
        }
    }

    func testASingleStepIsJustTheTwoEnds() {
        let path = TouchPath.points(from: .zero, to: CGPoint(x: 1, y: 1), steps: 1)
        XCTAssertEqual(path.count, 2)
    }

    func testZeroOrNegativeStepsStillProduceAUsablePath() {
        for steps in [0, -3] {
            let path = TouchPath.points(from: .zero, to: CGPoint(x: 1, y: 1), steps: steps)
            XCTAssertEqual(path.count, 2, "steps \(steps)")
            XCTAssertEqual(path.last, CGPoint(x: 1, y: 1))
        }
    }

    func testAPathThatDoesNotMoveRepeatsThePoint() {
        let point = CGPoint(x: 0.5, y: 0.5)
        let path = TouchPath.points(from: point, to: point, steps: 3)
        XCTAssertEqual(path.count, 4)
        XCTAssertTrue(path.allSatisfy { $0 == point })
    }
}

/// The app switcher half of the bottom edge swipe, and the edge band. Which of the two gestures
/// the guest performs is decided by the settle, verified separately against a real simulator.
final class AppSwitcherGestureTests: XCTestCase {
    func testBothSwipesStartInsideTheBottomEdgeBand() {
        for path in [HomeGesture.swipePath(), HomeGesture.appSwitcherPath()] {
            XCTAssertEqual(TouchEvent.Edge.beginning(at: path[0]), .bottom)
        }
    }

    func testTheSwitcherSwipeStopsLowerThanTheHomeSwipe() {
        let home = HomeGesture.swipePath().last!
        let switcher = HomeGesture.appSwitcherPath().last!
        XCTAssertGreaterThan(switcher.y, home.y, "the cards sit lower than the home swipe travels")
    }

    func testTheSettleNeverRepeatsAPosition() {
        let rest = CGPoint(x: 0.5, y: 0.6)
        let settle = HomeGesture.settlePath(around: rest, steps: 8)
        XCTAssertEqual(settle.count, 8)
        for (previous, next) in zip(settle, settle.dropFirst()) {
            XCTAssertNotEqual(previous.y, next.y, "a move with no delta is not movement")
        }
        for point in settle {
            XCTAssertEqual(point.x, rest.x)
            XCTAssertLessThan(abs(point.y - rest.y), 0.002)
        }
    }

    func testTheSettleIsNeverEmpty() {
        XCTAssertFalse(HomeGesture.settlePath(around: .zero, steps: 0).isEmpty)
    }

    func testEachSideOfTheScreenIsRecognised() {
        XCTAssertEqual(TouchEvent.Edge.beginning(at: CGPoint(x: 0.5, y: 0.99)), .bottom)
        XCTAssertEqual(TouchEvent.Edge.beginning(at: CGPoint(x: 0.5, y: 0.01)), .top)
        XCTAssertEqual(TouchEvent.Edge.beginning(at: CGPoint(x: 0.01, y: 0.5)), .left)
        XCTAssertEqual(TouchEvent.Edge.beginning(at: CGPoint(x: 0.99, y: 0.5)), .right)
        XCTAssertEqual(TouchEvent.Edge.beginning(at: CGPoint(x: 0.5, y: 0.5)), .none)
    }

    func testAContactJustInsideTheBandIsNotAnEdge() {
        XCTAssertEqual(TouchEvent.Edge.beginning(at: CGPoint(x: 0.5, y: 0.96)), .none)
        XCTAssertEqual(TouchEvent.Edge.beginning(at: CGPoint(x: 0.5, y: 0.97)), .bottom)
    }
}
