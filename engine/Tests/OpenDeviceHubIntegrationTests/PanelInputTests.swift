import Foundation
import XCTest
import OpenDeviceHubEngine

/// Does a tap aimed at a foldable's panel actually arrive? Read back from the test host's own log,
/// which records the coordinates the guest received.
final class PanelInputTests: XCTestCase {
    func testATapReachesTheUnfoldedPanel() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("no booted foldable") }

        // Unfolded, so the guest is drawing to the large panel.
        let control = try await IntegrationFoldable.shared.control(
            for: device.udid, adapter: adapter
        )
        try control.setHingeAngle(180)
        try await Task.sleep(for: .seconds(3))

        try IntegrationHost.install(on: device.udid)
        _ = try run(["simctl", "launch", device.udid, IntegrationHost.bundleID])
        try await Task.sleep(for: .seconds(5))

        let panels = try adapter.panels(device.udid)
        let unfolded = try XCTUnwrap(panels.first { $0.name == "Unfolded" })
        print("PANEL unfolded screenID=\(unfolded.screenID)")

        for (label, screenID) in [("targeted", unfolded.screenID), ("default", 0)] {
            let before = taps(device.udid).count
            let session = try adapter.openInput(device.udid, screenID: screenID)
            let point = CGPoint(x: 0.5, y: 0.7)
            try await session.touch(TouchEvent(phase: .began, points: [point]))
            try await Task.sleep(for: .milliseconds(80))
            try await session.touch(TouchEvent(phase: .ended, points: [point]))
            try await Task.sleep(for: .seconds(2))
            print("TAP \(label) screenID=\(screenID) arrived=\(taps(device.udid).count - before)")
            session.close()
        }
    }

    private func taps(_ udid: String) -> [String] {
        guard let container = try? run(["simctl", "get_app_container", udid, IntegrationHost.bundleID, "data"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let text = try? String(
                  contentsOf: URL(fileURLWithPath: container)
                      .appending(path: "Documents").appending(path: "events.txt"),
                  encoding: .utf8
              ) else { return [] }
        return text.split(separator: "\n").filter { $0.hasPrefix("TAP") }.map(String.init)
    }

    @discardableResult
    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
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
}
