import Foundation
import XCTest
import OpenDeviceHubEngine

/// Drives every action a foldable window offers and reports which of them the guest actually
/// received, reading back only what the test host appended for that one action.
final class FoldableActionsTests: XCTestCase {
    private var udid = ""
    private var container = URL(fileURLWithPath: "/")
    private var mark = 0

    func testWhatWorksOnAFoldable() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("no booted foldable") }
        udid = device.udid

        let control = try await IntegrationFoldable.shared.control(for: udid, adapter: adapter)
        try control.setHingeAngle(FoldableControl.openAngle)
        try await settle(3)

        let panels = try adapter.panels(udid)
        let unfolded = try XCTUnwrap(panels.first { $0.name == "Unfolded" })
        try IntegrationHost.install(on: udid)
        _ = try run(["simctl", "launch", udid, IntegrationHost.bundleID])
        container = URL(fileURLWithPath: try run([
            "simctl", "get_app_container", udid, IntegrationHost.bundleID, "data",
        ]).trimmingCharacters(in: .whitespacesAndNewlines))
            .appending(path: "Documents").appending(path: "events.txt")
        try await settle(6)

        let input = try adapter.openInput(udid, screenID: unfolded.screenID)
        var report: [String] = []

        // How far the guest's own layout is turned from the space the digitizer takes, measured at
        // each quarter turn of the device so the rule that composes the two is read off rather than
        // assumed.
        for quarterTurn in 0..<4 {
            try control.setOrientation(DeviceOrientation.allCases[quarterTurn])
            try await settle(3)
            let turn = try await measureTurn(input)
            report.append("device at \(DeviceOrientation.allCases[quarterTurn].rawValue):"
                + " layout is turned \(turn?.rawValue ?? "unreadable")")
        }
        try control.setOrientation(.portrait)
        try await settle(3)

        since()
        try await tap(input, at: CGPoint(x: 0.5, y: 0.5))
        try await settle(2)
        report.append("tap: \(taps().isEmpty ? "MISSING" : "arrives")")

        since()
        try await input.touch(TouchEvent(phase: .began, points: [CGPoint(x: 0.5, y: 0.8)]))
        for step in 1...8 {
            let point = CGPoint(x: 0.5, y: 0.8 - 0.07 * Double(step))
            try await input.touch(TouchEvent(phase: .moved, points: [point]))
            try await Task.sleep(for: .milliseconds(25))
        }
        try await input.touch(TouchEvent(phase: .ended, points: [CGPoint(x: 0.5, y: 0.24)]))
        try await settle(2)
        report.append("swipe: \(taps().isEmpty ? "MISSING" : "arrives")")

        // Every quarter turn, so the enum the guest wants is read off rather than assumed.
        for orientation in DeviceOrientation.allCases {
            since()
            try control.setOrientation(orientation)
            try await settle(3)
            let reported = lines("ORIENTATION").last?
                .replacingOccurrences(of: "ORIENTATION ", with: "") ?? "nothing"
            report.append("asked \(orientation.rawValue) -> guest says \(reported)")
        }
        try control.setOrientation(.portrait)
        try await settle(3)

        let turn = try await measureTurn(input) ?? .portrait
        report.append("using layout turn \(turn.rawValue) for the edge gestures")

        since()
        try await input.button(.home, phase: .down)
        try await Task.sleep(for: .milliseconds(30))
        try await input.button(.home, phase: .up)
        try await settle(3)
        report.append("home button: \(lines("SCENE").contains("SCENE BACKGROUND") ? "arrives" : "MISSING")")

        _ = try run(["simctl", "launch", udid, IntegrationHost.bundleID])
        try await settle(4)
        since()
        try await SystemGesture.home(on: input, turn: turn)
        try await settle(3)
        report.append("home swipe: \(lines("SCENE").contains("SCENE BACKGROUND") ? "arrives" : "MISSING")")

        _ = try run(["simctl", "launch", udid, IntegrationHost.bundleID])
        try await settle(4)
        since()
        try await SystemGesture.appSwitcher(on: input, turn: turn)
        try await settle(3)
        let left = lines("SCENE").contains("SCENE BACKGROUND")
        // Going home and opening the switcher both put the app behind, so the two are told apart by
        // what a tap in the middle does next: the switcher has the app's own card there.
        since()
        try await tap(input, at: CGPoint(x: 0.5, y: 0.5))
        try await settle(3)
        let cameBack = lines("SCENE").contains("SCENE FOREGROUND")
        report.append("app switcher: \(left && cameBack ? "arrives, its card is there" : "MISSING")")

        for line in report { print("RESULT \(line)") }
        input.close()
        // Left as it was found: shut, which is where the rest of these tests expect a foldable.
        try control.setHingeAngle(FoldableControl.closedAngle)
        try await settle(3)
    }

    private func native(_ path: [CGPoint], _ turn: DeviceOrientation) -> [CGPoint] {
        path.map { CoordinateMapper.portraitNativePoint(from: $0, orientation: turn) }
    }

    /// Taps two known native points and works out which quarter turn maps them onto where the guest
    /// says they landed.
    private func measureTurn(_ input: any InputSession) async throws -> DeviceOrientation? {
        var pairs: [(CGPoint, CGPoint)] = []
        for sent in [CGPoint(x: 0.25, y: 0.1), CGPoint(x: 0.75, y: 0.1)] {
            since()
            try await tap(input, at: sent)
            try await settle(2)
            guard let line = taps().last else { return nil }
            let parts = line.split(separator: " ")
            guard parts.count == 3, let x = Double(parts[1]), let y = Double(parts[2]) else { return nil }
            pairs.append((sent, CGPoint(x: x, y: y)))
        }
        return DeviceOrientation.allCases.first { candidate in
            pairs.allSatisfy { sent, got in
                let undone = CoordinateMapper.portraitNativePoint(from: got, orientation: candidate)
                return abs(undone.x - sent.x) < 0.02 && abs(undone.y - sent.y) < 0.02
            }
        }
    }

    private func stroke(
        _ input: any InputSession,
        along path: [CGPoint],
        edge: TouchEvent.Edge,
        lift: Bool = true
    ) async throws {
        guard let first = path.first else { return }
        try await input.touch(TouchEvent(phase: .began, points: [first], edge: edge))
        for point in path.dropFirst() {
            try await input.touch(TouchEvent(phase: .moved, points: [point], edge: edge))
            try await Task.sleep(for: .milliseconds(16))
        }
        if lift {
            try await input.touch(TouchEvent(phase: .ended, points: [path[path.count - 1]], edge: edge))
        }
    }

    private func tap(_ input: any InputSession, at point: CGPoint) async throws {
        try await input.touch(TouchEvent(phase: .began, points: [point]))
        try await Task.sleep(for: .milliseconds(80))
        try await input.touch(TouchEvent(phase: .ended, points: [point]))
    }

    private func text(_ point: CGPoint) -> String {
        String(format: "%.2f,%.2f", point.x, point.y)
    }

    private func text(_ line: String) -> String {
        let parts = line.split(separator: " ")
        guard parts.count == 3 else { return line }
        return "\(Double(parts[1]) ?? 0),\(Double(parts[2]) ?? 0)"
    }

    /// Everything the host has written so far is old news. Only what comes after this call counts.
    private func since() {
        mark = all().count
    }

    private func all() -> [String] {
        guard let text = try? String(contentsOf: container, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    private func lines(_ prefix: String) -> [String] {
        all().dropFirst(mark).filter { $0.hasPrefix(prefix) }
    }

    private func taps() -> [String] { lines("TAP") }

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
