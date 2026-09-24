import XCTest
@testable import OpenDeviceHubViewer

/// Placement is the part that goes wrong silently: a preview off the edge of the display is
/// invisible, and one on top of the device hides what was captured.
final class CapturePreviewLayoutTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 900)
    private let card = CGSize(width: 120, height: 200)

    func testItSitsToTheRightWhenThereIsRoom() {
        let frame = CapturePreviewLayout.frame(
            size: card,
            beside: CGRect(x: 400, y: 100, width: 430, height: 700),
            visible: display
        )
        XCTAssertEqual(frame.minX, 830 + CapturePreviewLayout.gap)
    }

    func testItMovesToTheLeftWhenTheRightWouldRunOff() {
        let frame = CapturePreviewLayout.frame(
            size: card,
            beside: CGRect(x: 1300, y: 100, width: 200, height: 700),
            visible: display
        )
        XCTAssertEqual(frame.maxX, 1300 - CapturePreviewLayout.gap)
    }

    func testWithNeitherSideFittingItStaysOnTheDisplay() {
        let narrow = CGRect(x: 0, y: 0, width: 200, height: 900)
        let frame = CapturePreviewLayout.frame(
            size: card,
            beside: CGRect(x: 10, y: 100, width: 180, height: 700),
            visible: narrow
        )
        XCTAssertGreaterThanOrEqual(frame.minX, narrow.minX)
        XCTAssertLessThanOrEqual(frame.maxX, narrow.maxX)
    }

    func testPreviewsStackUpwardsWithoutOverlapping() {
        let window = CGRect(x: 400, y: 100, width: 430, height: 700)
        let first = CapturePreviewLayout.frame(size: card, beside: window, visible: display, index: 0)
        let second = CapturePreviewLayout.frame(size: card, beside: window, visible: display, index: 1)
        XCTAssertGreaterThanOrEqual(second.minY, first.maxY)
    }

    func testItNeverLeavesTheVisibleArea() {
        for y in [-500.0, 0.0, 400.0, 2000.0] {
            let frame = CapturePreviewLayout.frame(
                size: card,
                beside: CGRect(x: 400, y: y, width: 430, height: 700),
                visible: display,
                index: 3
            )
            XCTAssertGreaterThanOrEqual(frame.minY, display.minY, "y=\(y)")
            XCTAssertLessThanOrEqual(frame.maxY, display.maxY, "y=\(y)")
        }
    }

    func testTheCardKeepsTheDeviceShape() {
        let size = CapturePreviewLayout.size(for: CGSize(width: 1206, height: 2622), longestEdge: 200)
        XCTAssertEqual(size.height, 200)
        XCTAssertEqual(size.width, 92)
    }

    func testALandscapeCaptureIsWiderThanItIsTall() {
        let size = CapturePreviewLayout.size(for: CGSize(width: 2622, height: 1206), longestEdge: 200)
        XCTAssertEqual(size.width, 200)
        XCTAssertGreaterThan(size.width, size.height)
    }

    func testAnEmptyCaptureDoesNotProduceAnImpossibleCard() {
        let size = CapturePreviewLayout.size(for: .zero)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }
}
