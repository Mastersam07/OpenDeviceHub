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

    /// Which panel the guest is actually drawing to.
    ///
    /// Both panels stay powered with a live surface whatever the hinge is doing, so neither the
    /// power state nor the surface says which is in use. What does say it is the picture: the panel
    /// being drawn carries a screen full of detail and the other is close to blank, which shows up
    /// as an order of magnitude difference in how well the capture compresses.
    private func drawnPanel(udid: String, among panels: [DevicePanel]) throws -> DevicePanel? {
        var best: (panel: DevicePanel, density: Double)?
        for panel in panels {
            let file = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "odh-panel-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: file) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "simctl", "io", udid, "screenshot",
                "--display", panel.id,
                file.path(percentEncoded: false),
            ]
            process.environment = ProcessInfo.processInfo.environment
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()

            let size = (try? FileManager.default.attributesOfItem(
                atPath: file.path(percentEncoded: false)
            )[.size] as? Int) ?? 0
            let pixels = panel.pixelSize.width * panel.pixelSize.height
            guard pixels > 0 else { continue }
            let density = Double(size ?? 0) / Double(pixels)
            if best == nil || density > best!.density { best = (panel, density) }
        }
        // A clear winner only. Two panels showing the same amount of detail would mean this measure
        // has stopped working, and a wrong answer is worse than none.
        guard let best, best.density > 0.1 else { return nil }
        return best.panel
    }

    private func settle(_ seconds: TimeInterval = 3) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
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

    /// The whole feature in one measurement: fold it open, and the guest starts drawing the larger
    /// panel. Read back through simctl, which reports whichever panel the guest is actually using.
    func testTheHingeMovesTheGuest() async throws {
        try IntegrationGate.requireEnabled()
        let udid = try foldable().udid
        let control = try makeAdapter().openFoldableControl(udid)
        try await control.activate()

        let panels = try makeAdapter().panels(udid)

        try control.setHingeAngle(FoldableControl.closedAngle)
        settle()
        XCTAssertEqual(
            try drawnPanel(udid: udid, among: panels)?.name, "Cover",
            "closed should leave the cover in use"
        )

        try control.setHingeAngle(FoldableControl.openAngle)
        settle()
        XCTAssertEqual(
            try drawnPanel(udid: udid, among: panels)?.name, "Unfolded",
            "opening should hand over to the unfolded panel"
        )

        // Left as it was found.
        try control.setHingeAngle(FoldableControl.closedAngle)
        settle()
    }

    /// The orientation the guest says it is in, read out of the test host's own log.
    ///
    /// A rotation does not change the framebuffer's shape, since it stays portrait native and the
    /// picture turns inside it, so the only honest readback is asking the guest.
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

    /// A foldable takes its orientation from the same provider as its hinge. This checks both halves
    /// of that: the ordinary rotation this app uses everywhere else does nothing here, and the
    /// foldable one works.
    func testOnlyTheFoldableRouteTurnsAFoldable() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try makeAdapter()
        let udid = try foldable().udid

        try IntegrationHost.install(on: udid)
        try run("/usr/bin/xcrun", ["simctl", "launch", udid, IntegrationHost.bundleID])
        settle(4)

        let control = try adapter.openFoldableControl(udid)
        try await control.activate()

        try control.setOrientation(.portrait)
        settle(3)
        XCTAssertEqual(try reportedOrientation(udid: udid), "PORTRAIT")

        // The route used for every other device, which the provider republishes over.
        try? adapter.setOrientation(.landscapeLeft, udid: udid)
        settle(3)
        XCTAssertEqual(
            try reportedOrientation(udid: udid), "PORTRAIT",
            "the ordinary rotation is expected to do nothing on a foldable"
        )

        try control.setOrientation(.landscapeLeft)
        settle(3)
        XCTAssertEqual(try reportedOrientation(udid: udid), "LANDSCAPELEFT")

        try control.setOrientation(.portrait)
        settle(3)
    }
}
