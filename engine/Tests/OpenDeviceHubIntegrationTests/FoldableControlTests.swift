import Foundation
import XCTest
import OpenDeviceHubEngine

final class FoldableControlTests: XCTestCase {
    private func makeAdapter() throws -> any SimulatorAdapter {
        try AdapterFactory.make(for: XcodeLocator.locate())
    }

    private func foldable() throws -> DeviceInfo {
        guard let device = try makeAdapter().devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else {
            throw XCTSkip("no booted foldable, boot an iPhone Duo to run this test")
        }
        return device
    }

    /// Both panels hand over a frame, so only the picture says which is in use: on 27A266a, open
    /// lights the unfolded panel and shut lights the cover.
    private func drawnPanels(udid: String, among panels: [DevicePanel]) async throws -> [String] {
        var drawn: [String] = []
        for panel in panels where try await hasPicture(udid: udid, panel: panel) {
            drawn.append(panel.name)
        }
        return drawn
    }

    private func hasPicture(udid: String, panel: DevicePanel) async throws -> Bool {
        let session = try makeAdapter().openDisplay(udid, panel: panel)
        defer { session.close() }
        // Xcode 26.6's Swift cannot check a value returned from inside this loop, so the result is
        // stored and the loop left instead.
        let waited = Task { () -> Bool in
            var lit = false
            for await frame in session.frames {
                lit = Self.isLit(frame.surface)
                break
            }
            return lit
        }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(4))
            waited.cancel()
        }
        defer { timeout.cancel() }
        return await waited.value
    }

    private static func isLit(_ surface: IOSurfaceRef) -> Bool {
        IOSurfaceLock(surface, .readOnly, nil)
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }
        let base = IOSurfaceGetBaseAddress(surface)
        let rowBytes = IOSurfaceGetBytesPerRow(surface)
        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        var lit = 0
        for y in stride(from: 0, to: height, by: max(height / 20, 1)) {
            for x in stride(from: 0, to: width, by: max(width / 20, 1)) {
                let pixel = base.advanced(by: y * rowBytes + x * 4)
                    .assumingMemoryBound(to: UInt8.self)
                if Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) > 24 { lit += 1 }
            }
        }
        return lit > 40
    }

    /// A run loop spun inside an async test returns at once, so this sleeps instead.
    private func settle(_ seconds: Double = 3) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    func testOpeningTheControlOnABootedDevice() throws {
        try IntegrationGate.requireEnabled()
        _ = try makeAdapter().openFoldableControl(foldable().udid)
    }

    func testRefusesAShutdownDevice() throws {
        try IntegrationGate.requireEnabled()
        let adapter = try makeAdapter()
        guard let shutdown = try adapter.devices().first(where: { $0.state == .shutdown }) else {
            throw XCTSkip("every simulator is booted")
        }
        XCTAssertThrowsError(try adapter.openFoldableControl(shutdown.udid)) { error in
            guard case EngineError.deviceNotBooted = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    func testTheHingeMovesTheGuest() async throws {
        try IntegrationGate.requireEnabled()
        let udid = try foldable().udid
        let control = try await IntegrationFoldable.shared.control(for: udid, adapter: makeAdapter())
        let panels = try makeAdapter().panels(udid)

        try control.setHingeAngle(FoldableControl.closedAngle)
        await settle(6)
        var drawn = try await drawnPanels(udid: udid, among: panels)
        XCTAssertEqual(drawn, ["Cover"], "closed should leave the cover in use")

        try control.setHingeAngle(FoldableControl.openAngle)
        await settle(6)
        drawn = try await drawnPanels(udid: udid, among: panels)
        XCTAssertEqual(drawn, ["Unfolded"], "opening should hand over to the unfolded panel")

        try control.setHingeAngle(FoldableControl.closedAngle)
        await settle()
    }

    /// The framebuffer stays portrait native through a rotation, so only the guest knows its turn.
    private func reportedOrientation(udid: String) throws -> String? {
        let container = try run("/usr/bin/xcrun", [
            "simctl", "get_app_container", udid, IntegrationHost.bundleID, "data",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        let events = URL(fileURLWithPath: container)
            .appending(path: "Documents")
            .appending(path: "events.txt")
        guard let text = try? String(contentsOf: events, encoding: .utf8) else { return nil }
        return text
            .split(separator: "\n")
            .last { $0.hasPrefix("ORIENTATION") }
            .flatMap { $0.split(separator: " ").last.map(String.init) }
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// A foldable takes its orientation from the same provider as its hinge.
    func testOnlyTheFoldableRouteTurnsAFoldable() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try makeAdapter()
        let udid = try foldable().udid

        try IntegrationHost.install(on: udid)
        try run("/usr/bin/xcrun", ["simctl", "launch", udid, IntegrationHost.bundleID])
        await settle(4)

        let control = try await IntegrationFoldable.shared.control(for: udid, adapter: adapter)

        try control.setHingeAngle(FoldableControl.openAngle)
        await settle(4)
        try control.setOrientation(.portrait)
        await settle(3)
        // The guest reports its panel's orientation, not the device's, so this checks the change.
        let upright = try reportedOrientation(udid: udid)
        XCTAssertNotNil(upright)

        try? adapter.setOrientation(.landscapeLeft, udid: udid)
        await settle(3)
        XCTAssertEqual(
            try reportedOrientation(udid: udid), upright,
            "the ordinary rotation is expected to do nothing on a foldable"
        )

        try control.setOrientation(.landscapeLeft)
        await settle(3)
        XCTAssertNotEqual(
            try reportedOrientation(udid: udid), upright,
            "the foldable's own route is expected to turn it"
        )

        try control.setOrientation(.portrait)
        await settle(3)
    }
}
