import XCTest
@testable import OpenDeviceHubEngine

private let phone = CGSize(width: 1206, height: 2622)

final class FittedRectTests: XCTestCase {
    func testFillsExactlyWhenTheAspectRatioMatches() {
        let rect = CoordinateMapper.fittedRect(viewSize: CGSize(width: 402, height: 874), pixelSize: phone)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 402, height: 874))
    }

    func testPillarboxesAWideView() {
        let rect = CoordinateMapper.fittedRect(viewSize: CGSize(width: 1000, height: 874), pixelSize: phone)
        XCTAssertEqual(rect.height, 874, accuracy: 0.001)
        XCTAssertEqual(rect.width, 402, accuracy: 0.001)
        XCTAssertEqual(rect.minX, 299, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.001)
    }

    func testLetterboxesATallView() {
        let rect = CoordinateMapper.fittedRect(viewSize: CGSize(width: 402, height: 1000), pixelSize: phone)
        XCTAssertEqual(rect.width, 402, accuracy: 0.001)
        XCTAssertEqual(rect.height, 874, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 63, accuracy: 0.001)
    }

    func testDegenerateSizesProduceAnEmptyRect() {
        XCTAssertEqual(CoordinateMapper.fittedRect(viewSize: .zero, pixelSize: phone), .zero)
        XCTAssertEqual(CoordinateMapper.fittedRect(viewSize: CGSize(width: 100, height: 100), pixelSize: .zero), .zero)
    }
}

final class NormalizeTests: XCTestCase {
    private let view = CGSize(width: 402, height: 874)

    func testCentreMapsToTheCentre() {
        let point = CoordinateMapper.normalize(
            viewPoint: CGPoint(x: 201, y: 437), viewSize: view, pixelSize: phone
        )
        XCTAssertEqual(point?.x ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(point?.y ?? -1, 0.5, accuracy: 0.0001)
    }

    func testTheYAxisIsFlipped() {
        let top = CoordinateMapper.normalize(
            viewPoint: CGPoint(x: 201, y: 874), viewSize: view, pixelSize: phone
        )
        XCTAssertEqual(top?.y ?? -1, 0, accuracy: 0.0001)

        let bottom = CoordinateMapper.normalize(
            viewPoint: CGPoint(x: 201, y: 0), viewSize: view, pixelSize: phone
        )
        XCTAssertEqual(bottom?.y ?? -1, 1, accuracy: 0.0001)
    }

    func testCornersMapToTheUnitSquare() {
        let topLeft = CoordinateMapper.normalize(
            viewPoint: CGPoint(x: 0, y: 874), viewSize: view, pixelSize: phone
        )
        XCTAssertEqual(topLeft?.x ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(topLeft?.y ?? -1, 0, accuracy: 0.0001)
    }

    func testAccountsForPillarboxOffset() {
        let wide = CGSize(width: 1000, height: 874)
        let point = CoordinateMapper.normalize(
            viewPoint: CGPoint(x: 500, y: 437), viewSize: wide, pixelSize: phone
        )
        XCTAssertEqual(point?.x ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(point?.y ?? -1, 0.5, accuracy: 0.0001)
    }

    func testAPointOnALetterboxBarIsRejected() {
        let tall = CGSize(width: 402, height: 1000)
        XCTAssertNil(CoordinateMapper.normalize(
            viewPoint: CGPoint(x: 201, y: 10), viewSize: tall, pixelSize: phone
        ))
        XCTAssertNil(CoordinateMapper.normalize(
            viewPoint: CGPoint(x: 201, y: 990), viewSize: tall, pixelSize: phone
        ))
    }

    func testAPointOutsideTheViewIsRejected() {
        XCTAssertNil(CoordinateMapper.normalize(
            viewPoint: CGPoint(x: -5, y: 437), viewSize: view, pixelSize: phone
        ))
    }

    func testTheSettingsIconRoundTripsToTheVerifiedRatio() {
        // The point that launched Settings during the touch investigation, in view coordinates.
        let point = CoordinateMapper.normalize(
            viewPoint: CGPoint(x: 0.8447 * 402, y: 874 - 0.4857 * 874),
            viewSize: view,
            pixelSize: phone
        )
        XCTAssertEqual(point?.x ?? -1, 0.8447, accuracy: 0.0001)
        XCTAssertEqual(point?.y ?? -1, 0.4857, accuracy: 0.0001)
    }
}
