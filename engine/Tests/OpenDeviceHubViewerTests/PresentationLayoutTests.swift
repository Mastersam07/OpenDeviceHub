import XCTest
@testable import OpenDeviceHubViewer

final class PresentationLayoutTests: XCTestCase {
    private let device = CGSize(width: 402, height: 874)

    func testTheBarFloatsInsetFromEveryEdgeItTouches() {
        let content = PresentationLayout.contentSize(forDevice: device)
        let layout = PresentationLayout(contentSize: content)
        // The bar sits exactly where AppKit puts the title bar, so the window's own buttons and the
        // toolbar items land on it without being moved.
        XCTAssertEqual(layout.bar.minX, 0)
        XCTAssertEqual(layout.bar.width, content.width)
        XCTAssertEqual(layout.bar.maxY, content.height)
        XCTAssertEqual(layout.bar.height, PresentationLayout.barHeight)
    }

    /// The device is what is inset, not the bar, so the window's clear background shows around it.
    func testTheDeviceIsInsetInsideTheWindow() {
        let content = PresentationLayout.contentSize(forDevice: device)
        let layout = PresentationLayout(contentSize: content)
        XCTAssertEqual(layout.bar.minY - layout.device.maxY, PresentationLayout.deviceTopMargin)
        XCTAssertEqual(layout.device.minY, PresentationLayout.deviceBottomMargin)
        XCTAssertEqual(layout.device.minX, PresentationLayout.deviceSideMargin)
        XCTAssertEqual(layout.device.size, device)
    }

    func testTheBarIsAPill() {
        let layout = PresentationLayout(contentSize: CGSize(width: 500, height: 900))
        XCTAssertEqual(layout.cornerRadius, PresentationLayout.barHeight / 2)
    }

    /// AppKit lays its toolbar items out in one 52 point band and will not restack them, so the bar
    /// keeps that height at every width and the device is what gives way.
    func testTheBarKeepsItsHeightHoweverNarrowTheWindowIs() {
        for width in [PresentationLayout.minimumWindowSize.width, 500, 1200] {
            let layout = PresentationLayout(contentSize: CGSize(width: width, height: 900))
            XCTAssertEqual(layout.bar.height, PresentationLayout.barHeight)
            XCTAssertEqual(layout.bar.width, width)
        }
    }

    /// The window stops at the bar's minimum while the device carries on shrinking, so a short
    /// window leaves the device smaller with space around it rather than refusing to resize.
    func testAShortWindowAtTheMinimumWidthStillShrinksTheDevice() {
        let minimum = PresentationLayout.minimumWindowSize
        let tall = PresentationLayout(contentSize: CGSize(width: minimum.width, height: 800))
        let short = PresentationLayout(contentSize: CGSize(width: minimum.width, height: 420))
        XCTAssertEqual(tall.bar.size, short.bar.size)
        XCTAssertLessThan(short.device.height, tall.device.height)
        XCTAssertGreaterThan(short.device.height, 0)
    }

    /// Full screen is AppKit's, and it puts its own chrome at the top, so the bar stops floating.
    func testFullScreenSquaresTheBarOffAgainstTheEdges() {
        let layout = PresentationLayout(contentSize: CGSize(width: 1512, height: 982), isFullScreen: true)
        XCTAssertEqual(layout.bar.minX, 0)
        XCTAssertEqual(layout.bar.width, 1512)
        XCTAssertEqual(layout.cornerRadius, 0)
        XCTAssertEqual(layout.bar.minY, layout.device.maxY, "no gap to show the desktop through")
        XCTAssertEqual(layout.device.minX, 0)
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
        // 949 less the bar and the margins above and below leaves exactly 861 points for the device.
        let available = CGSize(width: 1512, height: 949)
        XCTAssertEqual(
            PresentationLayout.deviceSize(fitting: CGSize(width: 402, height: 861), in: available),
            CGSize(width: 402, height: 861)
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
