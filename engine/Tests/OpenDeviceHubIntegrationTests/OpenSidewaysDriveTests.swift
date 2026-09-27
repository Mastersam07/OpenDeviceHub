import AppKit
import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

@MainActor
final class OpenSidewaysDriveTests: XCTestCase {
    func testASidewaysDeviceOpensSidewaysAndOneTurnBringsItBack() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.name.hasPrefix("iPhone") && ((try? adapter.panels($0.udid).count) ?? 0) < 2
        }) else { throw XCTSkip("boot an ordinary iPhone to run this test") }
        let udid = device.udid

        try IntegrationHost.install(on: udid)
        _ = try run(["simctl", "launch", udid, IntegrationHost.bundleID])
        let log = URL(fileURLWithPath: try run([
            "simctl", "get_app_container", udid, IntegrationHost.bundleID, "data",
        ]).trimmingCharacters(in: .whitespacesAndNewlines))
            .appending(path: "Documents").appending(path: "events.txt")
        try await Task.sleep(for: .seconds(4))

        try adapter.setOrientation(.landscapeLeft, udid: udid)
        defer { try? adapter.setOrientation(.portrait, udid: udid) }
        try await Task.sleep(for: .seconds(3))

        let orientation = try XCTUnwrap(DevicectlService().orientation(udid: udid), "devicectl did not say how the device is turned")
        XCTAssertEqual(orientation, .landscapeLeft)

        let manager = DeviceWindowManager(shutdown: { _ in })
        let controller = try manager.open(
            device: device,
            session: try adapter.openDisplay(udid, panel: nil),
            input: try adapter.openInput(udid),
            scaleMode: .fit,
            bezelEnabled: false,
            keepOnTop: false,
            showFPS: false,
            orientation: orientation
        )
        defer { manager.close(udid) }
        let window = try XCTUnwrap(controller.window)
        let screen = try XCTUnwrap(Self.screenView(in: window))
        window.layoutIfNeeded()

        let opened = window.contentLayoutRect.size
        print("RESULT opened \(controller.currentOrientation.rawValue), content \(Int(opened.width))x\(Int(opened.height))")
        XCTAssertEqual(controller.currentOrientation, .landscapeLeft)
        XCTAssertGreaterThan(opened.width, opened.height, "the window opened portrait around a sideways device")
        try await click(screen, in: window, at: CGPoint(x: screen.bounds.midX, y: screen.bounds.midY))
        try await Task.sleep(for: .seconds(2))
        try await checkQuadrants(screen, in: window, log: log, shown: "sideways")

        let back = controller.currentOrientation.rotatedLeft
        XCTAssertEqual(back, .portrait, "one turn does not lead back upright")
        try adapter.setOrientation(back, udid: udid)
        controller.setOrientation(back)
        window.layoutIfNeeded()
        try await Task.sleep(for: .seconds(3))
        let turned = window.contentLayoutRect.size
        print("RESULT after one turn \(controller.currentOrientation.rawValue), content \(Int(turned.width))x\(Int(turned.height))")
        XCTAssertGreaterThan(turned.height, turned.width, "the turn back left the window sideways")
        try await checkQuadrants(screen, in: window, log: log, shown: "upright")
    }

    func testAFoldableSaysHowItIsTurned() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("no booted foldable") }
        let control = try await IntegrationFoldable.shared.control(for: device.udid, adapter: adapter)
        defer { try? control.setOrientation(.portrait) }

        for orientation in [DeviceOrientation.landscapeRight, .landscapeLeft, .portrait] {
            try control.setOrientation(orientation)
            try await Task.sleep(for: .seconds(3))
            let read = DevicectlService().orientation(udid: device.udid)
            print("RESULT foldable turned \(orientation.rawValue), read back \(read?.rawValue ?? "nothing")")
            XCTAssertEqual(read, orientation)
        }
    }

    /// AppKit counts y up the window and the guest counts it down its screen.
    private func checkQuadrants(_ screen: NSView, in window: NSWindow, log: URL, shown: String) async throws {
        let box = screen.bounds
        let quarter = CGSize(width: box.width * 0.2, height: box.height * 0.2)
        let corners: [(String, CGPoint, (x: Bool, y: Bool))] = [
            ("upper left", CGPoint(x: box.midX - quarter.width, y: box.midY + quarter.height), (false, false)),
            ("upper right", CGPoint(x: box.midX + quarter.width, y: box.midY + quarter.height), (true, false)),
            ("lower left", CGPoint(x: box.midX - quarter.width, y: box.midY - quarter.height), (false, true)),
            ("lower right", CGPoint(x: box.midX + quarter.width, y: box.midY - quarter.height), (true, true)),
        ]
        for (name, spot, expected) in corners {
            let before = lastTap(log)
            try await click(screen, in: window, at: spot)
            try await Task.sleep(for: .seconds(2))
            let landed = lastTap(log)
            print("RESULT \(shown), the \(name) of the window: \(landed)")
            XCTAssertNotEqual(landed, before, "\(shown), the \(name) of the window reached nothing at all")
            guard let point = Self.point(from: landed) else { continue }
            XCTAssertEqual(point.x > 0.5, expected.x, "\(shown), the \(name) of the window arrived at \(point)")
            XCTAssertEqual(point.y > 0.5, expected.y, "\(shown), the \(name) of the window arrived at \(point)")
        }
    }

    private func click(_ view: NSView, in window: NSWindow, at spot: CGPoint) async throws {
        let inWindow = view.convert(spot, to: nil)
        view.mouseDown(with: try Self.mouse(.leftMouseDown, at: inWindow, in: window))
        try await Task.sleep(for: .milliseconds(80))
        view.mouseUp(with: try Self.mouse(.leftMouseUp, at: inWindow, in: window))
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

    private static func screenView(in window: NSWindow) -> DeviceScreenView? {
        func search(_ view: NSView) -> DeviceScreenView? {
            if let found = view as? DeviceScreenView { return found }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return window.contentView.flatMap(search)
    }

    private static func mouse(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) throws -> NSEvent {
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
