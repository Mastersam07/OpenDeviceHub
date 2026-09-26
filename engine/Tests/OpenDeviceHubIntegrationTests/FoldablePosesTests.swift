import Foundation
import XCTest
import OpenDeviceHubEngine

/// What each of the three positions in the bar actually does to the device, measured rather than
/// assumed, because two of them are expected to look the same to the guest.
final class FoldablePosesTests: XCTestCase {
    func testWhatEachPositionDoes() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else {
            throw XCTSkip("no booted foldable")
        }
        let control = try await IntegrationFoldable.shared.control(
            for: device.udid, adapter: adapter
        )
        let panels = try adapter.panels(device.udid)

        for (name, angle) in [("Cover", 0.0), ("Partially Open", 120.0), ("Fully Open", 180.0)] {
            try control.setHingeAngle(angle)
            try await Task.sleep(for: .seconds(3))
            print("POSE \(name) at \(Int(angle)) degrees -> guest draws \(drawn(device.udid, panels) ?? "nothing")")
        }
        try control.setHingeAngle(180)
    }

    private func drawn(_ udid: String, _ panels: [DevicePanel]) -> String? {
        var best: (String, Double)?
        for panel in panels {
            let file = "/tmp/odh-pose-\(panel.index).png"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "io", udid, "screenshot", "--display", panel.id, file]
            process.environment = ProcessInfo.processInfo.environment
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            let size = ((try? FileManager.default.attributesOfItem(atPath: file)[.size]) as? Int) ?? 0
            let pixels = panel.pixelSize.width * panel.pixelSize.height
            try? FileManager.default.removeItem(atPath: file)
            guard pixels > 0 else { continue }
            let density = Double(size) / Double(pixels)
            if best == nil || density > best!.1 { best = (panel.name, density) }
        }
        return best?.0
    }
}
