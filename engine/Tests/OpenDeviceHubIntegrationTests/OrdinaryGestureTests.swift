import Foundation
import XCTest
import OpenDeviceHubEngine

/// The edge gestures on a device with one screen, upright and turned, because the rule the foldable
/// needed changed the space the edge is read in for every device.
final class OrdinaryGestureTests: XCTestCase {
    private var udid = ""
    private var container = URL(fileURLWithPath: "/")
    private var mark = 0
    private var bootedHere = false

    override func tearDown() {
        if bootedHere { _ = try? run(["simctl", "shutdown", udid]) }
        super.tearDown()
    }

    func testTheEdgeGesturesOnAPhone() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        let devices = try adapter.devices()
        guard let phone = devices.first(where: { $0.name == "iPhone 17" && $0.isAvailable }) else {
            throw XCTSkip("no iPhone 17 in the set")
        }
        udid = phone.udid
        if phone.state != .booted {
            let simctl = SimctlService()
            try simctl.boot(udid: udid)
            try simctl.waitForBoot(udid: udid)
            bootedHere = true
        }

        try IntegrationHost.install(on: udid)
        _ = try run(["simctl", "launch", udid, IntegrationHost.bundleID])
        container = URL(fileURLWithPath: try run([
            "simctl", "get_app_container", udid, IntegrationHost.bundleID, "data",
        ]).trimmingCharacters(in: .whitespacesAndNewlines))
            .appending(path: "Documents").appending(path: "events.txt")
        try await settle(6)

        let session = try adapter.openInput(udid)
        var report: [String] = []

        for orientation in [DeviceOrientation.portrait, .landscapeLeft] {
            try adapter.setOrientation(orientation, udid: udid)
            try await settle(3)
            _ = try run(["simctl", "launch", udid, IntegrationHost.bundleID])
            try await settle(4)

            since()
            try await SystemGesture.home(on: session, turn: orientation)
            try await settle(3)
            let went = lines("SCENE").contains("SCENE BACKGROUND")
            report.append("home swipe in \(orientation.rawValue): \(went ? "arrives" : "MISSING")")
        }

        try adapter.setOrientation(.portrait, udid: udid)
        try await settle(2)
        _ = try run(["simctl", "launch", udid, IntegrationHost.bundleID])
        try await settle(4)
        since()
        try await SystemGesture.appSwitcher(on: session)
        try await settle(3)
        let left = lines("SCENE").contains("SCENE BACKGROUND")
        since()
        try await session.touch(TouchEvent(phase: .began, points: [CGPoint(x: 0.5, y: 0.5)]))
        try await Task.sleep(for: .milliseconds(80))
        try await session.touch(TouchEvent(phase: .ended, points: [CGPoint(x: 0.5, y: 0.5)]))
        try await settle(3)
        let cameBack = lines("SCENE").contains("SCENE FOREGROUND")
        report.append("app switcher in portrait: \(left && cameBack ? "arrives, its card is there" : "MISSING")")

        for line in report { print("RESULT \(line)") }
        session.close()
    }

    private func since() { mark = all().count }

    private func all() -> [String] {
        guard let text = try? String(contentsOf: container, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    private func lines(_ prefix: String) -> [String] {
        all().dropFirst(mark).filter { $0.hasPrefix(prefix) }
    }

    private func settle(_ seconds: Int) async throws {
        try await Task.sleep(for: .seconds(seconds))
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
