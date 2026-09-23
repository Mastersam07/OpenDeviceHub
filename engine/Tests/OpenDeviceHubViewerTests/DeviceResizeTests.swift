import XCTest
@testable import OpenDeviceHubViewer

final class DeviceResizeCornerTests: XCTestCase {
    private let device = CGRect(x: 100, y: 100, width: 400, height: 800)

    func testEachCornerTargetsItsOwnEnd() {
        let radius: CGFloat = 40
        let targets = DeviceResizeCorner.allCases.map { $0.hitRect(in: device, cornerRadius: radius) }
        for (corner, target) in zip(DeviceResizeCorner.allCases, targets) {
            XCTAssertTrue(device.insetBy(dx: -DeviceResizeCorner.reach, dy: -DeviceResizeCorner.reach).contains(target))
            XCTAssertEqual(target.midX < device.midX, corner.isLeft)
            XCTAssertEqual(target.midY > device.midY, corner.isTop)
        }
    }

    /// A rounded device has nothing drawn at the rectangular vertex, so the target sits inside it,
    /// on the curve.
    func testTheTargetSitsOnTheCurveNotTheVertex() {
        let target = DeviceResizeCorner.bottomLeft.hitRect(in: device, cornerRadius: 60)
        XCTAssertGreaterThan(target.midX, device.minX)
        XCTAssertGreaterThan(target.midY, device.minY)
    }

    func testTheCornersDoNotOverlapOnASmallDevice() {
        let small = CGRect(x: 0, y: 0, width: 120, height: 200)
        let targets = DeviceResizeCorner.allCases.map { $0.hitRect(in: small, cornerRadius: 40) }
        for (index, one) in targets.enumerated() {
            for other in targets[(index + 1)...] {
                XCTAssertFalse(one.intersects(other), "a resize target should mean one corner only")
            }
        }
    }
}

final class DeviceResizeSessionTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
    private let minimum = PresentationLayout.minimumWindowSize

    private func session(_ corner: DeviceResizeCorner, from frame: CGRect, at pointer: CGPoint) -> DeviceResizeSession {
        DeviceResizeSession(
            corner: corner,
            initialFrame: frame,
            initialPointer: pointer,
            deviceSize: CGSize(width: 400, height: 800),
            visibleFrame: visible,
            minimumSize: minimum
        )
    }

    func testNotMovingChangesNothing() {
        let frame = CGRect(x: 200, y: 100, width: 424, height: 888)
        let pointer = CGPoint(x: 624, y: 100)
        let resized = session(.bottomRight, from: frame, at: pointer).frame(at: pointer)
        XCTAssertEqual(resized.width, frame.width, accuracy: 1)
        XCTAssertEqual(resized.height, frame.height, accuracy: 1)
    }

    /// Whichever corner is dragged, the one opposite it stays exactly where it was.
    func testTheOppositeCornerIsPinned() {
        let frame = CGRect(x: 200, y: 100, width: 424, height: 888)
        for corner in DeviceResizeCorner.allCases {
            let pointer = CGPoint(
                x: corner.isLeft ? frame.minX : frame.maxX,
                y: corner.isTop ? frame.maxY : frame.minY
            )
            let moved = CGPoint(x: pointer.x + (corner.isLeft ? 40 : -40), y: pointer.y + (corner.isTop ? -40 : 40))
            let resized = session(corner, from: frame, at: pointer).frame(at: moved)
            XCTAssertEqual(
                corner.isLeft ? resized.maxX : resized.minX,
                corner.isLeft ? frame.maxX : frame.minX,
                accuracy: 0.5
            )
            XCTAssertEqual(
                corner.isTop ? resized.minY : resized.maxY,
                corner.isTop ? frame.minY : frame.maxY,
                accuracy: 0.5
            )
        }
    }

    func testTheDeviceKeepsItsShape() {
        let frame = CGRect(x: 200, y: 100, width: 424, height: 888)
        let pointer = CGPoint(x: 624, y: 100)
        let resized = session(.bottomRight, from: frame, at: pointer)
            .frame(at: CGPoint(x: pointer.x - 100, y: pointer.y + 100))
        // The window is the device plus fixed margins, so the device itself is what keeps its ratio.
        let extraWidth = PresentationLayout.deviceSideMargin * 2
        let extraHeight = PresentationLayout.barHeight
            + PresentationLayout.deviceTopMargin
            + PresentationLayout.deviceBottomMargin
        XCTAssertEqual((resized.width - extraWidth) / (resized.height - extraHeight), 0.5, accuracy: 0.02)
    }

    func testItNeverGoesBelowTheMinimum() {
        let frame = CGRect(x: 200, y: 100, width: 424, height: 888)
        let pointer = CGPoint(x: 624, y: 100)
        let resized = session(.bottomRight, from: frame, at: pointer)
            .frame(at: CGPoint(x: pointer.x - 5000, y: pointer.y + 5000))
        XCTAssertGreaterThanOrEqual(resized.width, minimum.width)
        XCTAssertGreaterThanOrEqual(resized.height, minimum.height)
    }

    func testItNeverGrowsPastTheScreen() {
        let frame = CGRect(x: 200, y: 100, width: 424, height: 888)
        let pointer = CGPoint(x: 624, y: 100)
        let resized = session(.bottomRight, from: frame, at: pointer)
            .frame(at: CGPoint(x: pointer.x + 5000, y: pointer.y - 5000))
        XCTAssertLessThanOrEqual(resized.maxX, visible.maxX + 0.5)
        XCTAssertGreaterThanOrEqual(resized.minY, visible.minY - 0.5)
    }

    func testADeviceWithNoSizeIsLeftAlone() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        let session = DeviceResizeSession(
            corner: .bottomRight,
            initialFrame: frame,
            initialPointer: .zero,
            deviceSize: .zero,
            visibleFrame: visible,
            minimumSize: minimum
        )
        XCTAssertEqual(session.frame(at: CGPoint(x: 100, y: 100)), frame)
    }
}
