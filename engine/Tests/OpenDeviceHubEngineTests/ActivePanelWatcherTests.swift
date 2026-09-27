import CoreGraphics
import Foundation
import os
import XCTest
@testable import OpenDeviceHubEngine

final class ActivePanelWatcherTests: XCTestCase {
    private static func report(active displayID: Int) -> DisplayReport {
        DisplayReport(displays: [1, 3].map { id in
            DisplayReport.Display(
                uniqueID: "panel-\(id)", name: id == 1 ? "LCD" : "LCD-1", displayID: id,
                isActive: id == displayID, backlight: id == displayID ? .activeOn : .off,
                isPrimary: id == 1, isIntegrated: true,
                pixelSize: CGSize(width: 1000, height: 2000), pointScale: 3,
                currentRotation: 0, nativeRotation: 0, chromeIdentifier: nil
            )
        })
    }

    private func firstChange(of watcher: ActivePanelWatcher, within seconds: Double) async -> Int? {
        await withTaskGroup(of: Int?.self) { group in
            group.addTask {
                for await panel in watcher.changes { return panel.displayID }
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

    /// The screens announce a fold before the report names the new panel, so a poke has to keep
    /// looking for a moment rather than glance once and go back to the clock.
    func testAPokeFindsAChangeThatArrivesJustAfterIt() async throws {
        let active = OSAllocatedUnfairLock(initialState: 3)
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let watcher = ActivePanelWatcher(read: {
            reads.withLock { $0 += 1 }
            return Self.report(active: active.withLock { $0 })
        }, hinge: nil)
        defer { watcher.close() }
        let first = await firstChange(of: watcher, within: 2)
        XCTAssertEqual(first, 3, "the first settled reading")

        let poked = ContinuousClock.now
        watcher.poke()
        try await Task.sleep(for: .milliseconds(400))
        active.withLock { $0 = 1 }
        let changed = await firstChange(of: watcher, within: 3)
        let elapsed = ContinuousClock.now - poked
        XCTAssertEqual(changed, 1)
        XCTAssertLessThan(elapsed, .seconds(1.5), "found within the burst, not on the five second clock")
        XCTAssertGreaterThan(reads.withLock { $0 }, 3, "it looked more than once")
    }

    func testAPokeWithoutAChangeStopsLooking() async throws {
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let watcher = ActivePanelWatcher(read: {
            reads.withLock { $0 += 1 }
            return Self.report(active: 3)
        }, hinge: nil)
        defer { watcher.close() }
        let first = await firstChange(of: watcher, within: 2)
        XCTAssertEqual(first, 3)
        let before = reads.withLock { $0 }
        watcher.poke()
        try await Task.sleep(for: .seconds(3.5))
        let during = reads.withLock { $0 } - before
        XCTAssertGreaterThanOrEqual(during, ActivePanelWatcher.burstReads - 1, "it kept looking through the burst")
        XCTAssertLessThanOrEqual(during, ActivePanelWatcher.burstReads + 1, "and then stopped; the clock is five seconds")
    }
}
