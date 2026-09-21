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
