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

final class OnScreenOriginTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)

    func testAFrameAlreadyOnScreenIsLeftAlone() {
        let frame = CGRect(x: 100, y: 100, width: 375, height: 699)
        XCTAssertEqual(
            DeviceGeometry.onScreenOrigin(frame: frame, visibleFrame: visible),
            frame.origin
        )
    }

    func testATallerShapeIsPulledDownSoItsTitleBarStaysReachable() {
        // A landscape window remembered at this origin becomes portrait on rotation, which would
        // push its title bar above the top of the screen.
        let frame = CGRect(x: 0, y: 504, width: 375, height: 699)
        let origin = DeviceGeometry.onScreenOrigin(frame: frame, visibleFrame: visible)
        XCTAssertEqual(origin.y, 944 - 699)
        XCTAssertEqual(origin.x, 0)
    }

    func testAFrameOffTheBottomIsPushedUp() {
        let frame = CGRect(x: 40, y: -300, width: 375, height: 400)
        XCTAssertEqual(
            DeviceGeometry.onScreenOrigin(frame: frame, visibleFrame: visible),
            CGPoint(x: 40, y: 0)
        )
    }

    func testAFrameOffTheRightIsPulledBack() {
        let frame = CGRect(x: 1400, y: 100, width: 375, height: 400)
        XCTAssertEqual(
            DeviceGeometry.onScreenOrigin(frame: frame, visibleFrame: visible),
            CGPoint(x: 1512 - 375, y: 100)
        )
    }

    func testAWindowTallerThanTheScreenHangsFromTheTop() {
        let frame = CGRect(x: 100, y: -400, width: 375, height: 1600)
        let origin = DeviceGeometry.onScreenOrigin(frame: frame, visibleFrame: visible)
        XCTAssertEqual(origin.x, 100)
        XCTAssertEqual(origin.y, 944 - 1600)
    }

    func testAWindowWiderThanTheScreenStaysWhereItIsWhileItCoversTheScreen() {
        let frame = CGRect(x: -200, y: 100, width: 2000, height: 400)
        XCTAssertEqual(
            DeviceGeometry.onScreenOrigin(frame: frame, visibleFrame: visible),
            CGPoint(x: -200, y: 100)
        )
    }

    func testAWindowWiderThanTheScreenIsPulledBackWhenItUncoversIt() {
        let frame = CGRect(x: 300, y: 100, width: 2000, height: 400)
        let origin = DeviceGeometry.onScreenOrigin(frame: frame, visibleFrame: visible)
        XCTAssertEqual(origin.x, 0)
        XCTAssertEqual(origin.y, 100)
    }

    func testAnEmptyScreenLeavesTheFrameAlone() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 100)
        XCTAssertEqual(
            DeviceGeometry.onScreenOrigin(frame: frame, visibleFrame: .zero),
            frame.origin
        )
    }
}

/// AppKit's own constraining is bypassed so a Pixel Accurate window may exceed the display, which
/// also removed the guard against dragging a window away entirely.
final class ReachableFrameTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private let titleBar: CGFloat = 52

    private func reachable(_ frame: CGRect) -> CGRect {
        DeviceGeometry.reachableFrame(frame, in: visible, titleBarHeight: titleBar)
    }

    func testAWindowOnScreenIsLeftWhereItIs() {
        let frame = CGRect(x: 200, y: 100, width: 456, height: 700)
        XCTAssertEqual(reachable(frame), frame)
    }

    /// A window taller than the screen hangs off the bottom rather than losing its title bar.
    func testATallWindowHangsOffTheBottom() {
        let result = reachable(CGRect(x: 200, y: 100, width: 456, height: 962))
        XCTAssertEqual(result.maxY, 944)
        XCTAssertEqual(result.size, CGSize(width: 456, height: 962))
    }

    func testAWindowTallerThanTheScreenKeepsItsSize() {
        let frame = CGRect(x: 0, y: -400, width: 456, height: 1311)
        let result = reachable(frame)
        XCTAssertEqual(result.size, frame.size, "the whole point of the override is keeping the size")
    }

    func testAWindowDraggedOffTheLeftKeepsAStripOnScreen() {
        let result = reachable(CGRect(x: -900, y: 100, width: 456, height: 962))
        XCTAssertEqual(result.maxX, DeviceGeometry.minimumReachableWidth)
        XCTAssertEqual(result.width, 456)
    }

    func testAWindowDraggedOffTheRightKeepsAStripOnScreen() {
        let result = reachable(CGRect(x: 2000, y: 100, width: 456, height: 962))
        XCTAssertEqual(result.minX, 1512 - DeviceGeometry.minimumReachableWidth)
    }

    /// Hanging off an edge is allowed, so long as enough is left to grab.
    func testAWindowMostlyOffTheEdgeIsStillAllowed() {
        let frame = CGRect(x: -300, y: 100, width: 456, height: 700)
        XCTAssertEqual(reachable(frame), frame)
    }

    func testTheTitleBarIsNeverPushedAboveTheTop() {
        let result = reachable(CGRect(x: 100, y: 500, width: 456, height: 962))
        XCTAssertEqual(result.maxY, 944)
    }

    func testTheTitleBarIsNeverDraggedBelowTheBottom() {
        let result = reachable(CGRect(x: 100, y: -2000, width: 456, height: 962))
        XCTAssertEqual(result.maxY, titleBar, "a strip of title bar has to stay grabbable")
    }

    func testANarrowWindowIsNotForcedWiderThanItself() {
        let result = reachable(CGRect(x: -500, y: 100, width: 40, height: 200))
        XCTAssertEqual(result.maxX, 40)
    }

    func testAnEmptyScreenLeavesTheFrameAlone() {
        let frame = CGRect(x: -900, y: 100, width: 456, height: 962)
        XCTAssertEqual(
            DeviceGeometry.reachableFrame(frame, in: .zero, titleBarHeight: titleBar),
            frame
        )
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

private let iPhone17Pro = DeviceMetrics(
    pixelSize: CGSize(width: 1206, height: 2622),
    pointScale: 3,
    pixelsPerInch: 460
)
private let iPadMini = DeviceMetrics(
    pixelSize: CGSize(width: 1488, height: 2266),
    pointScale: 2,
    pixelsPerInch: 326
)
/// A retina Mac: two physical pixels per point at 254 pixels per inch.
private let retinaMac = ScreenMetrics(backingScaleFactor: 2, pixelsPerInch: 254)

final class ScaleModeGeometryTests: XCTestCase {
    func testFitHasNoFixedSize() {
        XCTAssertNil(DeviceGeometry.contentSize(for: .fit, device: iPhone17Pro, screen: retinaMac))
    }

    func testPointAccurateMatchesTheDevicesOwnPoints() {
        let size = DeviceGeometry.contentSize(for: .pointAccurate, device: iPhone17Pro, screen: retinaMac)
        XCTAssertEqual(size, CGSize(width: 402, height: 874))
    }

    func testPixelAccurateMapsOneDevicePixelToOneScreenPixel() {
        let size = DeviceGeometry.contentSize(for: .pixelAccurate, device: iPhone17Pro, screen: retinaMac)
        XCTAssertEqual(size, CGSize(width: 603, height: 1311))
    }

    func testPixelAccurateOnANonRetinaScreenUsesTheFullPixelCount() {
        let plainMac = ScreenMetrics(backingScaleFactor: 1, pixelsPerInch: 109)
        let size = DeviceGeometry.contentSize(for: .pixelAccurate, device: iPhone17Pro, screen: plainMac)
        XCTAssertEqual(size, CGSize(width: 1206, height: 2622))
    }

    func testPhysicalSizeReproducesTheDevicesRealWidth() throws {
        let size = try XCTUnwrap(
            DeviceGeometry.contentSize(for: .physicalSize, device: iPhone17Pro, screen: retinaMac)
        )
        // 1206 px at 460 ppi is 2.6217 inches, and the Mac shows 127 points per inch.
        XCTAssertEqual(size.width, 2.6217 * 127, accuracy: 0.05)
        XCTAssertEqual(size.height, 2622.0 / 460 * 127, accuracy: 0.05)
    }

    func testPhysicalSizeKeepsTwoDevicesInProportionToEachOther() throws {
        let phone = try XCTUnwrap(
            DeviceGeometry.contentSize(for: .physicalSize, device: iPhone17Pro, screen: retinaMac)
        )
        let pad = try XCTUnwrap(
            DeviceGeometry.contentSize(for: .physicalSize, device: iPadMini, screen: retinaMac)
        )
        // The iPad mini is physically wider than the iPhone, even though the iPhone has the taller
        // pixel count.
        XCTAssertGreaterThan(pad.width, phone.width)
        XCTAssertEqual(pad.width / phone.width, (1488.0 / 326) / (1206.0 / 460), accuracy: 0.001)
    }

    func testPhysicalSizeIsUnavailableWithoutBothDensities() {
        let unknownDevice = DeviceMetrics(
            pixelSize: CGSize(width: 1206, height: 2622), pointScale: 3, pixelsPerInch: nil
        )
        let unknownScreen = ScreenMetrics(backingScaleFactor: 2, pixelsPerInch: nil)
        XCTAssertNil(DeviceGeometry.contentSize(for: .physicalSize, device: unknownDevice, screen: retinaMac))
        XCTAssertNil(DeviceGeometry.contentSize(for: .physicalSize, device: iPhone17Pro, screen: unknownScreen))
    }

    func testEveryModeRejectsADeviceWithNoPixels() {
        let empty = DeviceMetrics(pixelSize: .zero, pointScale: 3, pixelsPerInch: 460)
        for mode in ScaleMode.allCases {
            XCTAssertNil(DeviceGeometry.contentSize(for: mode, device: empty, screen: retinaMac), "\(mode)")
        }
    }

    func testEveryModePreservesTheDevicesAspectRatio() throws {
        let expected = 1206.0 / 2622.0
        for mode in ScaleMode.allCases where mode != .fit {
            let size = try XCTUnwrap(
                DeviceGeometry.contentSize(for: mode, device: iPhone17Pro, screen: retinaMac), "\(mode)"
            )
            XCTAssertEqual(size.width / size.height, expected, accuracy: 0.0001, "\(mode)")
        }
    }
}

final class FitsOnScreenTests: XCTestCase {
    /// The built in display of the machine this was developed on, minus the menu bar.
    private let laptop = CGSize(width: 1512, height: 957)

    func testPointAccurateFitsOnALaptopScreen() {
        let size = DeviceGeometry.contentSize(for: .pointAccurate, device: iPhone17Pro, screen: retinaMac)!
        XCTAssertTrue(DeviceGeometry.fitsOnScreen(contentSize: size, visibleSize: laptop, titleBarHeight: 32))
    }

    func testPixelAccurateDoesNotFitOnALaptopScreen() {
        let size = DeviceGeometry.contentSize(for: .pixelAccurate, device: iPhone17Pro, screen: retinaMac)!
        XCTAssertEqual(size, CGSize(width: 603, height: 1311))
        XCTAssertFalse(DeviceGeometry.fitsOnScreen(contentSize: size, visibleSize: laptop, titleBarHeight: 32))
    }

    func testTheTitleBarCountsTowardsTheHeight() {
        let size = CGSize(width: 100, height: 950)
        XCTAssertTrue(DeviceGeometry.fitsOnScreen(contentSize: size, visibleSize: laptop, titleBarHeight: 0))
        XCTAssertFalse(DeviceGeometry.fitsOnScreen(contentSize: size, visibleSize: laptop, titleBarHeight: 32))
    }

    func testAnExactFitCounts() {
        XCTAssertTrue(DeviceGeometry.fitsOnScreen(
            contentSize: CGSize(width: 1512, height: 925), visibleSize: laptop, titleBarHeight: 32
        ))
    }
}
