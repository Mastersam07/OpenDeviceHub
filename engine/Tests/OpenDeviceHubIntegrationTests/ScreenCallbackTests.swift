import Foundation
import os
import XCTest
@testable import OpenDeviceHubEngine

/// A fold reaches the window through the screens' own announcements, not the clock.
final class ScreenCallbackTests: XCTestCase {
    func testAFoldReachesTheWatcherWithoutWaitingOnTheClock() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("no booted foldable") }
        let udid = device.udid
        let panels = try adapter.panels(udid)
        let sessions = try ["Unfolded", "Cover"].map { name in
            try adapter.openDisplay(udid, panel: XCTUnwrap(panels.first { $0.name == name }))
        }
        defer { sessions.forEach { $0.close() } }
        for session in sessions {
            XCTAssertTrue((session as? SimulatorDisplaySession)?.usesScreenCallbacks == true, "the port vends the screen callbacks")
        }

        let control = try await IntegrationFoldable.shared.control(for: udid, adapter: adapter)
        try control.setHingeAngle(FoldableControl.openAngle)
        try await Task.sleep(for: .seconds(4))

        let started = ContinuousClock.now
        let watcher = ActivePanelWatcher(read: { try await adapter.displayReport(udid) }, hinge: nil)
        defer { watcher.close() }
        let nudges = sessions.map { session in
            Task { for await _ in session.screenChanges { watcher.poke() } }
        }
        defer { nudges.forEach { $0.cancel() } }

        // When the report itself changed, read as fast as the guest answers.
        let reportChanges = OSAllocatedUnfairLock(initialState: [(Int, Duration)]())
        let reportWatch = Task {
            var last: Int?
            while !Task.isCancelled {
                if let report = try? await adapter.displayReport(udid), report.isSettled,
                   let active = report.activeIntegrated, active.displayID != last {
                    last = active.displayID
                    reportChanges.withLock { $0.append((active.displayID, ContinuousClock.now - started)) }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        defer { reportWatch.cancel() }
        let watcherChanges = OSAllocatedUnfairLock(initialState: [(Int, Duration)]())
        let collector = Task {
            for await panel in watcher.changes {
                watcherChanges.withLock { $0.append((panel.displayID, ContinuousClock.now - started)) }
            }
        }
        defer { collector.cancel() }

        try await Task.sleep(for: .seconds(2))
        try control.setHingeAngle(FoldableControl.closedAngle)
        try await Task.sleep(for: .seconds(7))
        try control.setHingeAngle(FoldableControl.openAngle)
        try await Task.sleep(for: .seconds(7))

        let reported = reportChanges.withLock { $0 }
        let seen = watcherChanges.withLock { $0 }
        func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }
        print("RESULT report: " + reported.map { "\($0.0)@\(String(format: "%.2f", seconds($0.1)))" }.joined(separator: " "))
        print("RESULT watcher: " + seen.map { "\($0.0)@\(String(format: "%.2f", seconds($0.1)))" }.joined(separator: " "))
        XCTAssertEqual(seen.map(\.0), [3, 1, 3], "open, shut, open")
        XCTAssertEqual(reported.map(\.0), [3, 1, 3])
        for (report, watch) in zip(reported.dropFirst(), seen.dropFirst()) {
            let delay = seconds(watch.1) - seconds(report.1)
            print("RESULT panel \(watch.0) reached the watcher \(String(format: "%.2f", delay))s after the report changed")
            XCTAssertLessThan(delay, 0.6, "the watcher waited on the clock")
        }
    }
}
