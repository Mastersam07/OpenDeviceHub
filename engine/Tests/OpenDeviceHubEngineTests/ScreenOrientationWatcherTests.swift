import CoreGraphics
import Foundation
import os
import XCTest
@testable import OpenDeviceHubEngine

final class ScreenOrientationWatcherTests: XCTestCase {
    /// The iPhone Duo's panels as its device type builds them in: the cover upright, the inner panel
    /// a quarter turn round.
    private static let duoAngles: @Sendable (Int) -> Int = { $0 == 3 ? 270 : 0 }

    private static func report(active displayID: Int, rotation: Int, settled: Bool = true) -> DisplayReport {
        DisplayReport(displays: [1, 3].map { id in
            DisplayReport.Display(
                uniqueID: "panel-\(id)", name: id == 1 ? "LCD" : "LCD-1", displayID: id,
                isActive: id == displayID,
                backlight: id == displayID ? (settled ? .activeOn : .inactiveOn) : .off,
                isPrimary: id == 1, isIntegrated: true,
                pixelSize: CGSize(width: 1000, height: 2000), pointScale: 3,
                currentRotation: id == displayID ? rotation : 0, nativeRotation: 0, chromeIdentifier: nil
            )
        })
    }

    func testAnOrientationFromDegreesWrapsRound() {
        XCTAssertEqual(DeviceOrientation(degrees: 0), .portrait)
        XCTAssertEqual(DeviceOrientation(degrees: 90), .landscapeLeft)
        XCTAssertEqual(DeviceOrientation(degrees: 450), .landscapeLeft)
        XCTAssertEqual(DeviceOrientation(degrees: -90), .landscapeRight)
        XCTAssertNil(DeviceOrientation(degrees: 45))
    }

    /// Measured on the Duo (27A9269): turned through its own control, the inner panel's layout read
    /// 0, 180, 90 and 270 degrees for landscape right, landscape left, portrait and upside down.
    func testTheInnerPanelReadsItsLayoutTurnedByItsAngle() {
        let measured: [(Int, DeviceOrientation)] = [
            (0, .landscapeRight), (180, .landscapeLeft), (90, .portrait), (270, .portraitUpsideDown),
        ]
        for (rotation, expected) in measured {
            let reading = ScreenOrientationWatcher.reading(from: Self.report(active: 3, rotation: rotation), nativeRotation: Self.duoAngles)
            XCTAssertEqual(reading, OrientationSettler.Reading(orientation: expected, panel: 3), "inner panel at \(rotation)")
        }
    }

    /// The cover, and an iPhone's only panel, sit upright, so the layout is the orientation.
    func testAnUprightPanelReadsItsLayoutAsItIs() {
        let reading = ScreenOrientationWatcher.reading(from: Self.report(active: 1, rotation: 270), nativeRotation: Self.duoAngles)
        XCTAssertEqual(reading, OrientationSettler.Reading(orientation: .landscapeRight, panel: 1))
    }

    func testAReportStillChangingPanelsIsNoReading() {
        XCTAssertNil(ScreenOrientationWatcher.reading(from: Self.report(active: 1, rotation: 0, settled: false), nativeRotation: Self.duoAngles))
    }

    /// Unfolding, the report went on naming the cover for about a fifth of a second while already
    /// turning it by the inner panel's angle (27A9269): that is landscape for a moment, not a turn.
    func testAMomentOnTheWayThroughAFoldIsNotBelieved() {
        var settler = OrientationSettler()
        let start = ContinuousClock.now
        let hold = Duration.milliseconds(400)
        let portraitOnCover = OrientationSettler.Reading(orientation: .portrait, panel: 1)
        let passing = OrientationSettler.Reading(orientation: .landscapeLeft, panel: 1)
        let portraitInside = OrientationSettler.Reading(orientation: .portrait, panel: 3)
        XCTAssertNil(settler.observe(portraitOnCover, at: start, holdingFor: hold))
        XCTAssertEqual(settler.observe(portraitOnCover, at: start + .milliseconds(400), holdingFor: hold), .portrait)
        XCTAssertNil(settler.observe(passing, at: start + .milliseconds(500), holdingFor: hold))
        XCTAssertNil(settler.observe(passing, at: start + .milliseconds(700), holdingFor: hold))
        XCTAssertNil(settler.observe(portraitInside, at: start + .milliseconds(800), holdingFor: hold))
        XCTAssertNil(settler.observe(portraitInside, at: start + .milliseconds(1300), holdingFor: hold), "still portrait, nothing new to say")
    }

    func testATurnThatHoldsIsBelievedOnceAndAnotherAfterIt() {
        var settler = OrientationSettler()
        let start = ContinuousClock.now
        let hold = Duration.milliseconds(400)
        let right = OrientationSettler.Reading(orientation: .landscapeRight, panel: 3)
        let left = OrientationSettler.Reading(orientation: .landscapeLeft, panel: 3)
        XCTAssertNil(settler.observe(right, at: start, holdingFor: hold))
        XCTAssertEqual(settler.observe(right, at: start + .milliseconds(450), holdingFor: hold), .landscapeRight)
        XCTAssertNil(settler.observe(right, at: start + .milliseconds(900), holdingFor: hold))
        XCTAssertNil(settler.observe(nil, at: start + .milliseconds(1000), holdingFor: hold))
        XCTAssertNil(settler.observe(left, at: start + .milliseconds(1100), holdingFor: hold))
        XCTAssertEqual(settler.observe(left, at: start + .milliseconds(1500), holdingFor: hold), .landscapeLeft)
    }

    func testAPokeReportsTheScreenOnceItHasSettled() async throws {
        let rotation = OSAllocatedUnfairLock(initialState: 90)
        let watcher = ScreenOrientationWatcher(
            read: { Self.report(active: 3, rotation: rotation.withLock { $0 }) },
            nativeRotation: Self.duoAngles
        )
        defer { watcher.close() }
        watcher.poke()
        let first = await Self.firstChange(of: watcher, within: 2)
        XCTAssertEqual(first, .turned(.portrait))

        rotation.withLock { $0 = 180 }
        watcher.poke()
        let second = await Self.firstChange(of: watcher, within: 3)
        XCTAssertEqual(second, .turned(.landscapeLeft))
    }

    /// A Face ID phone refuses upside down, and a foldable's turn can go unheard: either way the
    /// screen stays put and the watcher says so once it has had time to move.
    func testATurnTheScreenDidNotTakeIsSaidToBeStillWhereItWas() async throws {
        let watcher = ScreenOrientationWatcher(
            read: { Self.report(active: 1, rotation: 270) },
            nativeRotation: Self.duoAngles
        )
        defer { watcher.close() }
        watcher.poke()
        let first = await Self.firstChange(of: watcher, within: 2)
        XCTAssertEqual(first, .turned(.landscapeRight))
        try await Task.sleep(for: .seconds(3))

        let asked = ContinuousClock.now
        watcher.confirm()
        let answer = await Self.firstChange(of: watcher, within: 4)
        XCTAssertEqual(answer, .stillAt(.landscapeRight))
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - asked, ScreenOrientationWatcher.confirmDelay)
    }

    /// The report catches up with a turn a second or so after it was asked for; checking must not
    /// say the screen stayed put in the meantime.
    func testATurnTheScreenTakesLateIsATurnAndNothingElse() async throws {
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let turnedAfter = OSAllocatedUnfairLock(initialState: Int.max)
        let watcher = ScreenOrientationWatcher(
            read: {
                let count = reads.withLock { $0 += 1; return $0 }
                return Self.report(active: 3, rotation: count >= turnedAfter.withLock { $0 } ? 180 : 90)
            },
            nativeRotation: Self.duoAngles
        )
        defer { watcher.close() }
        watcher.poke()
        _ = await Self.firstChange(of: watcher, within: 2)
        try await Task.sleep(for: .seconds(3))

        turnedAfter.withLock { $0 = reads.withLock { $0 } + 12 }
        watcher.confirm()
        var seen: [ScreenOrientationWatcher.Event] = []
        let collector = Task {
            for await event in watcher.changes { seen.append(event) }
            return seen
        }
        try await Task.sleep(for: .seconds(3.5))
        watcher.close()
        let after = await collector.value
        XCTAssertEqual(after.first, .turned(.landscapeLeft))
        XCTAssertFalse(after.contains(.stillAt(.portrait)), "said to be still where it was while turning")
    }

    /// The report lags the screens' announcement, so a look after a turn first reads the orientation
    /// from before it, which must not turn the window back.
    func testAReportThatHasNotCaughtUpDoesNotTurnBack() async throws {
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let turnedAfter = OSAllocatedUnfairLock(initialState: Int.max)
        let watcher = ScreenOrientationWatcher(
            read: {
                let count = reads.withLock { $0 += 1; return $0 }
                return Self.report(active: 3, rotation: count >= turnedAfter.withLock { $0 } ? 180 : 90)
            },
            nativeRotation: Self.duoAngles
        )
        defer { watcher.close() }
        watcher.poke()
        let first = await Self.firstChange(of: watcher, within: 2)
        XCTAssertEqual(first, .turned(.portrait))
        try await Task.sleep(for: .seconds(3))

        turnedAfter.withLock { $0 = reads.withLock { $0 } + 7 }
        watcher.poke()
        var seen: [ScreenOrientationWatcher.Event] = []
        let collector = Task {
            for await orientation in watcher.changes { seen.append(orientation) }
            return seen
        }
        try await Task.sleep(for: .seconds(3))
        watcher.close()
        let after = await collector.value
        XCTAssertEqual(after, [.turned(.landscapeLeft)], "only the turn, never back to where it was")
    }

    /// Opening, the report named the cover for about a third of a second while it read upside down
    /// and then upright (27A9269), and at times longer than a reading takes to settle.
    func testWhatTheReportSaysWhileTheHingeMovesIsNotBelieved() async throws {
        let rotation = OSAllocatedUnfairLock(initialState: 90)
        let watcher = ScreenOrientationWatcher(
            read: { Self.report(active: 3, rotation: rotation.withLock { $0 }) },
            nativeRotation: Self.duoAngles
        )
        defer { watcher.close() }
        watcher.poke()
        let first = await Self.firstChange(of: watcher, within: 2)
        XCTAssertEqual(first, .turned(.portrait))
        try await Task.sleep(for: .seconds(3))

        watcher.holdStill()
        rotation.withLock { $0 = 180 }
        try await Task.sleep(for: .milliseconds(700))
        rotation.withLock { $0 = 90 }
        let during = await Self.firstChange(of: watcher, within: 3)
        XCTAssertNil(during, "a fold is not a turn")
    }

    func testATurnDuringAFoldStillComesThroughOnceTheHingeIsStill() async throws {
        let rotation = OSAllocatedUnfairLock(initialState: 90)
        let watcher = ScreenOrientationWatcher(
            read: { Self.report(active: 3, rotation: rotation.withLock { $0 }) },
            nativeRotation: Self.duoAngles
        )
        defer { watcher.close() }
        watcher.poke()
        _ = await Self.firstChange(of: watcher, within: 2)
        try await Task.sleep(for: .seconds(3))

        watcher.holdStill()
        rotation.withLock { $0 = 180 }
        let turned = await Self.firstChange(of: watcher, within: 3)
        XCTAssertEqual(turned, .turned(.landscapeLeft))
    }

    private static func firstChange(of watcher: ScreenOrientationWatcher, within seconds: Double) async -> ScreenOrientationWatcher.Event? {
        await withTaskGroup(of: ScreenOrientationWatcher.Event?.self) { group in
            group.addTask {
                for await event in watcher.changes { return event }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
