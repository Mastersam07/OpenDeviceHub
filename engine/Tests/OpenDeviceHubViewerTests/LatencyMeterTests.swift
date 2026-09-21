import XCTest
@testable import OpenDeviceHubViewer

final class LatencyMeterTests: XCTestCase {
    /// One millisecond expressed in mach ticks on this machine.
    private var oneMillisecond: UInt64 {
        let info = LatencyMeter.timebase
        return UInt64(1_000_000 * Double(info.denom) / Double(info.numer))
    }

    func testAFrameAfterAClickProducesAReading() throws {
        let meter = LatencyMeter()
        meter.clickSent(at: 0)
        let reading = try XCTUnwrap(meter.frameDrawn(at: oneMillisecond * 12))
        XCTAssertEqual(reading.lastMilliseconds, 12, accuracy: 0.5)
        XCTAssertEqual(reading.sampleCount, 1)
    }

    func testAFrameWithNoClickIsNotTimed() {
        XCTAssertNil(LatencyMeter().frameDrawn(at: oneMillisecond))
    }

    func testOnlyTheFirstClickOfADragIsTimed() throws {
        let meter = LatencyMeter()
        meter.clickSent(at: 0)
        meter.clickSent(at: oneMillisecond * 5)
        let reading = try XCTUnwrap(meter.frameDrawn(at: oneMillisecond * 10))
        XCTAssertEqual(reading.lastMilliseconds, 10, accuracy: 0.5, "timed from the first click")
    }

    func testTheAverageCoversEverySample() throws {
        let meter = LatencyMeter()
        for (index, delay) in [10.0, 20.0, 30.0].enumerated() {
            let base = UInt64(index) * oneMillisecond * 1000
            meter.clickSent(at: base)
            _ = meter.frameDrawn(at: base + UInt64(delay) * oneMillisecond)
        }
        let reading = try XCTUnwrap(meter.reading)
        XCTAssertEqual(reading.averageMilliseconds, 20, accuracy: 0.5)
        XCTAssertEqual(reading.sampleCount, 3)
    }

    func testOldSamplesFallOutOfTheWindow() throws {
        let meter = LatencyMeter(capacity: 2)
        for index in 0..<4 {
            let base = UInt64(index) * oneMillisecond * 1000
            meter.clickSent(at: base)
            _ = meter.frameDrawn(at: base + oneMillisecond * 10)
        }
        XCTAssertEqual(try XCTUnwrap(meter.reading).sampleCount, 2)
    }

    func testAFrameBeforeTheClickIsIgnored() {
        let meter = LatencyMeter()
        meter.clickSent(at: oneMillisecond * 10)
        XCTAssertNil(meter.frameDrawn(at: oneMillisecond * 5))
    }

    func testThereIsNoReadingBeforeAnythingIsMeasured() {
        XCTAssertNil(LatencyMeter().reading)
    }

    /// A click that draws no frame must not be closed by some unrelated frame seconds later.
    func testAStaleClickIsDiscardedRatherThanReported() {
        let meter = LatencyMeter(staleAfterMilliseconds: 500)
        meter.clickSent(at: 0)
        XCTAssertNil(meter.frameDrawn(at: oneMillisecond * 8000))
        XCTAssertNil(meter.reading, "a nonsense value must not reach the overlay")
    }

    func testAClickJustInsideTheWindowIsStillReported() throws {
        let meter = LatencyMeter(staleAfterMilliseconds: 500)
        meter.clickSent(at: 0)
        let reading = try XCTUnwrap(meter.frameDrawn(at: oneMillisecond * 400))
        XCTAssertEqual(reading.lastMilliseconds, 400, accuracy: 1)
    }

    func testAStaleClickDoesNotBlockTheNextMeasurement() throws {
        let meter = LatencyMeter(staleAfterMilliseconds: 500)
        meter.clickSent(at: 0)
        XCTAssertNil(meter.frameDrawn(at: oneMillisecond * 8000))
        let base = oneMillisecond * 9000
        meter.clickSent(at: base)
        let reading = try XCTUnwrap(meter.frameDrawn(at: base + oneMillisecond * 15))
        XCTAssertEqual(reading.lastMilliseconds, 15, accuracy: 1)
    }
}
