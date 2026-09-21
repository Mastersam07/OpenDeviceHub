import IOSurface
import XCTest
@testable import OpenDeviceHubViewer

private func makeSurface(width: Int, height: Int) -> IOSurfaceRef? {
    IOSurfaceCreate([
        kIOSurfaceWidth: width,
        kIOSurfaceHeight: height,
        kIOSurfaceBytesPerElement: 4,
        kIOSurfacePixelFormat: Int(kCVPixelFormatType_32BGRA),
    ] as CFDictionary)
}

final class ScreenshotWriterTests: XCTestCase {
    func testProducesAnImageMatchingTheSurfaceSize() throws {
        let surface = try XCTUnwrap(makeSurface(width: 64, height: 128))
        let image = try XCTUnwrap(ScreenshotWriter.image(from: surface))
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 128)
    }

    func testProducesRealPNGBytes() throws {
        let surface = try XCTUnwrap(makeSurface(width: 32, height: 32))
        let data = try XCTUnwrap(ScreenshotWriter.pngData(from: surface))
        XCTAssertGreaterThan(data.count, 8)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "PNG signature")
    }

    func testTheFileNameCarriesTheDeviceAndTheTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 14, minute: 5, second: 9))!
        let name = ScreenshotWriter.fileName(deviceName: "iPhone 17 Pro", date: date, calendar: calendar)
        XCTAssertEqual(name, "iPhone 17 Pro 2026-09-21 at 14.05.09.png")
    }

    func testTheFileNameAvoidsPathSeparators() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5))!
        let name = ScreenshotWriter.fileName(deviceName: "iPad Pro 13/M5", date: date, calendar: calendar)
        XCTAssertFalse(name.contains("/"))
        XCTAssertTrue(name.hasSuffix(".png"))
    }

    func testTwoScreenshotsASecondApartDoNotCollide() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 14, minute: 5, second: 9))!
        let second = first.addingTimeInterval(1)
        XCTAssertNotEqual(
            ScreenshotWriter.fileName(deviceName: "A", date: first, calendar: calendar),
            ScreenshotWriter.fileName(deviceName: "A", date: second, calendar: calendar)
        )
    }
}
