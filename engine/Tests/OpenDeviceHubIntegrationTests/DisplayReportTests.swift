import Foundation
import XCTest
import OpenDeviceHubEngine

/// The guest's own account of its screens, read through the same feature `devicectl` fronts, and
/// checked against what `devicectl` prints for the same device at the same moment.
final class DisplayReportTests: XCTestCase {
    func testTheReportAgreesWithDevicectl() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("no booted foldable") }

        let report = try await adapter.displayReport(device.udid)
        for display in report.displays {
            print("RESULT sees \(display.name) id \(display.displayID) integrated \(display.isIntegrated) active \(display.isActive) backlight \(display.backlight.rawValue) \(Int(display.pixelSize.width))x\(Int(display.pixelSize.height))")
        }
        // devicectl prints the built in screens; the guest also lists its external and virtual ones.
        let printed = try devicectlDisplays(device.udid)
        XCTAssertEqual(report.integrated.count, printed.count, "a different number of built in displays")

        for display in report.integrated {
            guard let theirs = printed.first(where: { $0.uniqueID == display.uniqueID }) else {
                XCTFail("devicectl does not list \(display.uniqueID)")
                continue
            }
            XCTAssertEqual(display.displayID, theirs.displayID, display.name)
            XCTAssertEqual(display.isActive, theirs.isActive, display.name)
            XCTAssertEqual(display.pixelSize, theirs.pixelSize, display.name)
            XCTAssertEqual(display.currentRotation, theirs.currentRotation, display.name)
            XCTAssertEqual(display.nativeRotation, theirs.nativeRotation, display.name)
            XCTAssertEqual(display.chromeIdentifier, theirs.chromeIdentifier, display.name)
            XCTAssertTrue(display.isIntegrated, display.name)
        }

        let active = try XCTUnwrap(report.activeIntegrated, "the guest is laying out on no screen")
        print("RESULT active panel is display \(active.displayID) (\(active.name)), \(Int(active.pixelSize.width))x\(Int(active.pixelSize.height)), turned \(active.currentRotation)")
    }

    /// Fold it and the report follows the guest, whoever moved the hinge.
    func testTheReportFollowsTheFold() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("no booted foldable") }
        let control = try await IntegrationFoldable.shared.control(for: device.udid, adapter: adapter)

        try control.setHingeAngle(FoldableControl.openAngle)
        try await Task.sleep(for: .seconds(4))
        let open = try await adapter.displayReport(device.udid).activeIntegrated
        try control.setHingeAngle(FoldableControl.closedAngle)
        try await Task.sleep(for: .seconds(5))
        let shutReport = try await adapter.displayReport(device.udid)
        let shut = shutReport.activeIntegrated
        print("RESULT shut report settled: \(shutReport.isSettled)")
        try control.setHingeAngle(FoldableControl.openAngle)
        try await Task.sleep(for: .seconds(4))

        XCTAssertNotNil(open)
        XCTAssertNotNil(shut)
        XCTAssertNotEqual(open?.uniqueID, shut?.uniqueID, "folding did not move the guest")
        XCTAssertGreaterThan(open?.pixelSize.width ?? 0, shut?.pixelSize.width ?? 0, "open should be the larger panel")
        print("RESULT open on display \(open?.displayID ?? -1), shut on display \(shut?.displayID ?? -1)")
    }

    private struct Printed {
        let uniqueID: String
        let displayID: Int
        let isActive: Bool
        let pixelSize: CGSize
        let currentRotation: Int
        let nativeRotation: Int
        let chromeIdentifier: String?
    }

    private func devicectlDisplays(_ udid: String) throws -> [Printed] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "devicectl", "device", "info", "displays", "--device", udid,
            "--timeout", "15", "--quiet", "--json-output", "-",
        ]
        process.environment = ProcessInfo.processInfo.environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let displays = (json?["result"] as? [String: Any])?["displays"] as? [[String: Any]] ?? []
        return displays.compactMap { record in
            guard let uniqueID = record["uniqueId"] as? String else { return nil }
            let bounds = record["bounds"] as? [[Double]] ?? []
            let size = bounds.count == 2
                ? CGSize(width: bounds[1][0] - bounds[0][0], height: bounds[1][1] - bounds[0][1])
                : .zero
            func degrees(_ text: Any?) -> Int {
                Int((text as? String)?.dropFirst(3) ?? "") ?? 0
            }
            return Printed(
                uniqueID: uniqueID,
                displayID: record["displayId"] as? Int ?? 0,
                isActive: record["active"] as? Bool ?? false,
                pixelSize: size,
                currentRotation: degrees(record["currentOrientation"]),
                nativeRotation: degrees(record["nativeOrientation"]),
                chromeIdentifier: record["chromeIdentifier"] as? String
            )
        }
    }
}
