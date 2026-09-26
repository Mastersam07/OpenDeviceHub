import Foundation
import XCTest
import OpenDeviceHubEngine

/// The guest's own answers, checked against `devicectl`, which fronts the same features, and
/// against a fold.
final class CoreDeviceFeatureTests: XCTestCase {
    private var adapter: (any SimulatorAdapter)!
    private var udid = ""

    override func setUp() async throws {
        try IntegrationGate.requireEnabled()
        adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("no booted foldable") }
        udid = device.udid
    }

    func testTheHingeStreamReadsWhatDevicectlReads() async throws {
        let capabilities = try await adapter.motionCapabilities(udid)
        XCTAssertTrue(capabilities.hingeAngle, "a foldable reports a hinge")

        let control = try await IntegrationFoldable.shared.control(for: udid, adapter: adapter)
        try control.setHingeAngle(120)
        try await Task.sleep(for: .seconds(3))

        let stream = try adapter.openHingeStream(udid)
        defer { stream.close() }
        var first: HingeSample?
        for await sample in stream.samples {
            first = sample
            break
        }
        let sample = try XCTUnwrap(first, "no hinge reading arrived")
        print("RESULT hinge stream says \(sample.degrees)")
        let printed = try devicectlHingeAngle()
        print("RESULT devicectl says \(printed)")
        XCTAssertEqual(sample.degrees, printed, accuracy: 0.5)
        XCTAssertEqual(sample.degrees, 120, accuracy: 0.5, "the hinge is where it was put")

        try control.setHingeAngle(FoldableControl.openAngle)
        try await Task.sleep(for: .seconds(3))
    }

    func testEachTouchscreenNamesItsDisplay() async throws {
        let touchscreens = try await adapter.touchscreens(udid)
        let report = try await adapter.displayReport(udid)
        for touchscreen in touchscreens {
            print("RESULT touchscreen target \(touchscreen.target) on display \(touchscreen.displayUniqueID ?? "unnamed")")
        }
        XCTAssertGreaterThanOrEqual(touchscreens.count, 2, "a foldable has a touchscreen per panel")
        for display in report.integrated {
            let matching = touchscreens.first { $0.displayUniqueID == display.uniqueID }
            XCTAssertNotNil(matching, "no touchscreen for \(display.name)")
            // The plist screen ID, which the branch already sends, is the same number.
            XCTAssertEqual(matching?.target, display.displayID, display.name)
        }
    }

    func testTheWatcherFollowsTheGuestThroughAFold() async throws {
        let control = try await IntegrationFoldable.shared.control(for: udid, adapter: adapter)
        try control.setHingeAngle(FoldableControl.openAngle)
        try await Task.sleep(for: .seconds(4))

        let hinge = try adapter.openHingeStream(udid)
        let adapter = self.adapter!
        let udid = self.udid
        let watcher = ActivePanelWatcher(read: { try await adapter.displayReport(udid) }, hinge: hinge)
        defer {
            watcher.close()
            hinge.close()
        }

        let collector = Task { () -> [Int] in
            var seen: [Int] = []
            for await panel in watcher.changes {
                seen.append(panel.displayID)
                if seen.count == 3 { break }
            }
            return seen
        }

        try await Task.sleep(for: .seconds(3))
        try control.setHingeAngle(FoldableControl.closedAngle)
        watcher.poke()
        try await Task.sleep(for: .seconds(6))
        try control.setHingeAngle(FoldableControl.openAngle)
        watcher.poke()
        try await Task.sleep(for: .seconds(6))
        collector.cancel()
        let seen = await collector.value

        print("RESULT the watcher reported panels \(seen)")
        XCTAssertEqual(seen, [3, 1, 3], "open, shut, open")
    }

    private func devicectlHingeAngle() throws -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        // devicectl streams until its own timeout and then reports that as an error; the first
        // line it prints before that is the reading.
        process.arguments = ["devicectl", "device", "motion", "hinge-angle", "--device", udid, "--timeout", "8"]
        process.environment = ProcessInfo.processInfo.environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        // A line like "• +0.000s : Angle:120.0°  Mech:120.0°  ..."
        guard let range = text.range(of: "Angle:"),
              let value = Double(text[range.upperBound...].prefix { $0.isNumber || $0 == "." }) else {
            throw XCTSkip("devicectl printed no hinge angle: \(text.prefix(200))")
        }
        return value
    }
}
