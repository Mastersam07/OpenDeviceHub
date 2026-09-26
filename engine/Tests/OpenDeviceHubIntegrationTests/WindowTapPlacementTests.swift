import AppKit
import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// Where a click on a foldable's window lands on the guest, driven as a real mouse event and read
/// back out of the guest's own log.
///
/// The whole path is in this: the ray against the posed mesh, the panel's build angle, and the
/// coordinates the digitizer is addressed in. A stray flip in any of them still puts every click on
/// the screen, so only the quadrant a click arrives in shows it up.
@MainActor
final class WindowTapPlacementTests: XCTestCase {
    func testEachCornerOfTheWindowLandsOnTheMatchingCornerOfTheGuest() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("no booted foldable") }
        let udid = device.udid

        let control = try await IntegrationFoldable.shared.control(for: udid, adapter: adapter)
        try control.setHingeAngle(FoldableControl.openAngle)
        try control.setOrientation(.portrait)
        try await Task.sleep(for: .seconds(4))

        let panels = try adapter.panels(udid)
        guard let unfolded = panels.first(where: { $0.name == "Unfolded" }) else {
            throw XCTSkip("not a foldable")
        }
        try IntegrationHost.install(on: udid)
        _ = try run(["simctl", "launch", udid, IntegrationHost.bundleID])
        let log = URL(fileURLWithPath: try run([
            "simctl", "get_app_container", udid, IntegrationHost.bundleID, "data",
        ]).trimmingCharacters(in: .whitespacesAndNewlines))
            .appending(path: "Documents").appending(path: "events.txt")
        try await Task.sleep(for: .seconds(6))

        // Closing the window must leave the device running rather than shut it down as a real
        // window would under the user's own setting.
        let manager = DeviceWindowManager(shutdown: { _ in })
        let controller = try manager.open(
            device: device,
            session: try adapter.openDisplay(udid, panel: unfolded),
            input: try adapter.openInput(udid, screenID: unfolded.screenID),
            scaleMode: .fit,
            bezelEnabled: false,
            keepOnTop: false,
            showFPS: false,
            foldsAtHinge: true,
            panelNativeRotation: unfolded.nativeRotation
        )
        defer { manager.close(udid) }
        let window = try XCTUnwrap(controller.window)
        let model = try XCTUnwrap(Self.modelView(in: window))
        model.setHingeAngle(FoldableControl.openAngle)
        window.layoutIfNeeded()
        try await Task.sleep(for: .seconds(1))

        // The first contact pays for turning the input feature on, so it is not one of the readings.
        try await click(model, in: window, at: CGPoint(x: model.bounds.midX, y: model.bounds.midY))
        try await Task.sleep(for: .seconds(2))

        let box = model.bounds
        let quarter = CGSize(width: box.width * 0.2, height: box.height * 0.2)
        // AppKit counts up the window and the guest counts down its screen, so the higher click is
        // the one expected to come back with the smaller y.
        let corners: [(String, CGPoint, (x: Bool, y: Bool))] = [
            ("upper left", CGPoint(x: box.midX - quarter.width, y: box.midY + quarter.height), (false, false)),
            ("upper right", CGPoint(x: box.midX + quarter.width, y: box.midY + quarter.height), (true, false)),
            ("lower left", CGPoint(x: box.midX - quarter.width, y: box.midY - quarter.height), (false, true)),
            ("lower right", CGPoint(x: box.midX + quarter.width, y: box.midY - quarter.height), (true, true)),
        ]

        for (name, spot, expected) in corners {
            let before = lastTap(log)
            try await click(model, in: window, at: spot)
            try await Task.sleep(for: .seconds(2))
            let landed = lastTap(log)
            XCTAssertNotEqual(landed, before, "the \(name) of the window reached nothing at all")
            guard let point = Self.point(from: landed) else { continue }
            XCTAssertEqual(
                point.x > 0.5, expected.x,
                "the \(name) of the window arrived at \(point), which is the wrong side"
            )
            XCTAssertEqual(
                point.y > 0.5, expected.y,
                "the \(name) of the window arrived at \(point), which is the wrong half"
            )
        }
    }

    private func click(_ model: DuoModelView, in window: NSWindow, at spot: CGPoint) async throws {
        let inWindow = model.convert(spot, to: nil)
        model.mouseDown(with: try Self.mouse(.leftMouseDown, at: inWindow, in: window))
        try await Task.sleep(for: .milliseconds(80))
        model.mouseUp(with: try Self.mouse(.leftMouseUp, at: inWindow, in: window))
    }

    private func lastTap(_ log: URL) -> String {
        (try? String(contentsOf: log, encoding: .utf8))?
            .split(separator: "\n").last { $0.hasPrefix("TAP") }.map(String.init) ?? "nothing"
    }

    private static func point(from line: String) -> CGPoint? {
        let parts = line.split(separator: " ")
        guard parts.count == 3, let x = Double(parts[1]), let y = Double(parts[2]) else { return nil }
        return CGPoint(x: x, y: y)
    }

    private static func modelView(in window: NSWindow) -> DuoModelView? {
        func search(_ view: NSView) -> DuoModelView? {
            if let found = view as? DuoModelView { return found }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return window.contentView.flatMap(search)
    }

    private static func mouse(
        _ type: NSEvent.EventType,
        at point: CGPoint,
        in window: NSWindow
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
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
