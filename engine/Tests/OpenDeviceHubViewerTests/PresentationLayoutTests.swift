import XCTest
@testable import OpenDeviceHubViewer

final class PresentationLayoutTests: XCTestCase {
    private let device = CGSize(width: 402, height: 874)

    func testTheBarFloatsInsetFromEveryEdgeItTouches() {
        let content = PresentationLayout.contentSize(forDevice: device)
        let layout = PresentationLayout(contentSize: content)
        XCTAssertEqual(layout.bar.minX, PresentationLayout.sideMargin)
        XCTAssertEqual(layout.bar.maxX, content.width - PresentationLayout.sideMargin)
        XCTAssertEqual(layout.bar.maxY, content.height - PresentationLayout.sideMargin)
        XCTAssertEqual(layout.bar.height, PresentationLayout.barHeight)
    }

    func testTheDeviceHangsBelowTheBarWithAGap() {
        let content = PresentationLayout.contentSize(forDevice: device)
        let layout = PresentationLayout(contentSize: content)
        XCTAssertEqual(layout.bar.minY - layout.device.maxY, PresentationLayout.deviceGap)
        XCTAssertEqual(layout.device.height, device.height)
    }

    func testTheBarIsAPill() {
        let layout = PresentationLayout(contentSize: CGSize(width: 500, height: 900))
        XCTAssertEqual(layout.cornerRadius, PresentationLayout.barHeight / 2)
    }

    func testANarrowWindowStacksTheBarIntoTwoRows() {
        let wide = PresentationLayout(contentSize: CGSize(width: 500, height: 900))
        let narrow = PresentationLayout(contentSize: CGSize(width: 280, height: 900))
        XCTAssertFalse(wide.isCompact)
        XCTAssertTrue(narrow.isCompact)
        XCTAssertEqual(narrow.bar.height, PresentationLayout.compactBarHeight)
    }

    /// Full screen is AppKit's, and it puts its own chrome at the top, so the bar stops floating.
    func testFullScreenSquaresTheBarOffAgainstTheEdges() {
        let layout = PresentationLayout(contentSize: CGSize(width: 1512, height: 982), isFullScreen: true)
        XCTAssertEqual(layout.bar.minX, 0)
        XCTAssertEqual(layout.bar.width, 1512)
        XCTAssertEqual(layout.cornerRadius, 0)
        XCTAssertFalse(layout.isCompact, "a full screen window is never treated as narrow")
        XCTAssertEqual(layout.bar.minY, layout.device.maxY, "no gap to show the desktop through")
    }

    func testAWindowThatFitsLeavesTheDeviceAlone() {
        let fitted = PresentationLayout.deviceSize(
            fitting: device,
            in: CGSize(width: 1512, height: 1200)
        )
        XCTAssertEqual(fitted, device)
    }

    /// A window taller than the display would put the bottom of the device out of the pointer's
    /// reach, and that is exactly where its system gestures start.
    func testATallDeviceIsScaledUntilTheWholeWindowFits() {
        // The iPhone 17 with its body around it, which is what overflows a 949 point high desktop.
        let withBody = CGSize(width: 456, height: 910)
        let available = CGSize(width: 1512, height: 949)
        let fitted = PresentationLayout.deviceSize(fitting: withBody, in: available)
        XCTAssertLessThan(fitted.height, withBody.height)

        let content = PresentationLayout.contentSize(forDevice: fitted)
        XCTAssertLessThanOrEqual(content.height, available.height)
        XCTAssertLessThanOrEqual(content.width, available.width)
    }

    func testADeviceThatJustFitsIsNotScaled() {
        // 949 less the bar, the top margin and the gap leaves exactly 875 points for the device.
        let available = CGSize(width: 1512, height: 949)
        XCTAssertEqual(
            PresentationLayout.deviceSize(fitting: CGSize(width: 402, height: 875), in: available),
            CGSize(width: 402, height: 875)
        )
    }

    func testFittingKeepsTheDevicesShape() {
        let fitted = PresentationLayout.deviceSize(
            fitting: device,
            in: CGSize(width: 1512, height: 700)
        )
        let before = device.width / device.height
        let after = fitted.width / fitted.height
        XCTAssertEqual(before, after, accuracy: 0.01)
    }

    func testNothingBreaksOnAnEmptyWindow() {
        let layout = PresentationLayout(contentSize: .zero)
        XCTAssertEqual(layout.device.height, 0)
        XCTAssertGreaterThanOrEqual(layout.bar.minY, 0)
        XCTAssertEqual(PresentationLayout.deviceSize(fitting: .zero, in: .zero), .zero)
    }
}
