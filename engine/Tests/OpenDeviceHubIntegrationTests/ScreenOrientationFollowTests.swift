import AppKit
import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// A window keeps up with its device's screen whoever turns the device. Device Hub turns an
/// ordinary device the way `devicectl device orientation set` does and a foldable through the
/// foldable's own control, so those stand in for it here.
@MainActor
final class ScreenOrientationFollowTests: XCTestCase {
    func testTheFoldableFollowsTurnsFromOutsideAndKeepsItsOwnThroughFolds() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("boot an iPhone Duo to run this test") }
        let udid = device.udid
        try IntegrationHost.install(on: udid)
        _ = try run(["simctl", "launch", udid, IntegrationHost.bundleID])
        try await Task.sleep(for: .seconds(3))

        let panels = try adapter.panels(udid)
        let unfolded = try XCTUnwrap(panels.first { $0.name == "Unfolded" })
        let cover = try XCTUnwrap(panels.first { $0.name == "Cover" })
        let found = DevicectlService().orientation(udid: udid) ?? .portrait
        let input = try adapter.openInput(udid, screenID: unfolded.screenID)
        let targeted = try XCTUnwrap(input as? PanelInputSession)
        let manager = DeviceWindowManager(shutdown: { _ in })
        let controller = try manager.open(
            device: device,
            session: try adapter.openDisplay(udid, panel: unfolded),
            input: input,
            scaleMode: .fit, bezelEnabled: true, keepOnTop: false, showFPS: false,
            foldsAtHinge: true,
            chrome: unfolded.chromeIdentifier.flatMap { ChromeLocator.chrome(identifier: $0) },
            panelNativeRotation: unfolded.nativeRotation,
            unfoldedPanel: unfolded,
            cover: FoldableCover(panel: cover, session: try adapter.openDisplay(udid, panel: cover)),
            retarget: { targeted.setTarget(screenID: $0) },
            orientation: found
        )
        let shared = try await IntegrationFoldable.shared.control(for: udid, adapter: adapter)
        let foldables = FoldableController(
            open: { _ in shared },
            hingeStream: { try adapter.openHingeStream($0) },
            displayReport: { try await adapter.displayReport($0) }
        )
        let orientations = ScreenOrientationFollower(
            read: { try await adapter.displayReport($0) },
            panels: { (try? adapter.panels($0)) ?? [] }
        )
        orientations.onScreenChange = { foldables.nudge($0) }
        orientations.follow(udid, controller: controller)
        foldables.onMove = { [weak controller] _, event in
            switch event {
            case .began(let target): controller?.beginFold(to: target)
            case .angle(let angle):
                controller?.showHingeAngle(angle)
                orientations.hingeMoved(udid, to: angle)
            case .ended: controller?.endFold()
            }
        }
        foldables.follow(
            udid,
            onPanel: { [weak controller] panel in controller?.setActivePanel(screenID: panel.displayID) },
            onHinge: { [weak controller] degrees in
                controller?.showHingeAngle(degrees)
                orientations.hingeMoved(udid, to: degrees)
            }
        )
        let open = DeviceControlBar.FoldMode.fullyOpen.angle
        controller.showHingeAngle(open)
        foldables.setAngle(open, for: udid)
        defer {
            foldables.setAngle(open, for: udid)
            try? shared.setOrientation(found)
            orientations.forget(udid)
            foldables.forget(udid)
            manager.close(udid)
        }
        try await Task.sleep(for: .seconds(3))

        for orientation in [DeviceOrientation.landscapeRight, .landscapeLeft, .portraitUpsideDown, .portrait] {
            let started = ContinuousClock.now
            try shared.setOrientation(orientation)
            let followed = await Self.wait(for: orientation, in: controller, within: 4)
            print("RESULT turned \(orientation.rawValue) from outside, window \(controller.currentOrientation.rawValue) after \(Self.milliseconds(since: started)) ms")
            XCTAssertTrue(followed, "the window did not follow a turn to \(orientation.rawValue) from outside")
        }

        for orientation in [DeviceOrientation.landscapeLeft, .portrait, .landscapeRight, .landscapeLeft] {
            try foldables.setOrientation(orientation, for: udid)
            controller.setOrientation(orientation)
            orientations.turned(udid, to: orientation)
            let shown = await Self.samples(of: controller, for: 3)
            let screen = await Self.screen(of: udid, adapter: adapter, panels: panels)
            print("RESULT turned \(orientation.rawValue) from the window, screen \(screen?.rawValue ?? "nothing"), window \(shown.map(\.rawValue).reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } })")
            XCTAssertEqual(controller.currentOrientation, screen, "the window and the screen disagree after the window's own turn")
            if screen == orientation {
                XCTAssertEqual(Set(shown), [orientation], "the window moved off a turn the screen took")
            }
        }
        if controller.currentOrientation != .landscapeLeft {
            try foldables.setOrientation(.landscapeLeft, for: udid)
            controller.setOrientation(.landscapeLeft)
            orientations.turned(udid, to: .landscapeLeft)
        }
        try await Task.sleep(for: .seconds(3))
        XCTAssertEqual(controller.currentOrientation, .landscapeLeft)
        for (name, angle) in [("shut", 0.0), ("open", open)] {
            foldables.setAngle(angle, for: udid, eased: true)
            let shown = await Self.samples(of: controller, for: 5)
            print("RESULT \(name) while held landscape left, window \(Set(shown).map(\.rawValue)) over \(shown.count) samples")
            XCTAssertEqual(Set(shown), [.landscapeLeft], "the window turned while the device was \(name == "shut" ? "shutting" : "opening")")
        }
    }

    func testAnIPhoneFollowsTurnsFromOutsideAndLeavesARefusedOneAlone() async throws {
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
        _ = try run(["devicectl", "device", "orientation", "set", "--device", udid, "portrait", "--timeout", "10", "--quiet"])
        try await Task.sleep(for: .seconds(3))
        let start = await Self.screen(of: udid, adapter: adapter, panels: [])
        XCTAssertEqual(start, .portrait, "the device did not start upright")

        let manager = DeviceWindowManager(shutdown: { _ in })
        let controller = try manager.open(
            device: device,
            session: try adapter.openDisplay(udid, panel: nil),
            input: try adapter.openInput(udid, screenID: 0),
            scaleMode: .fit, bezelEnabled: true, keepOnTop: false, showFPS: false,
            orientation: DevicectlService().orientation(udid: udid) ?? .portrait
        )
        let orientations = ScreenOrientationFollower(
            read: { try await adapter.displayReport($0) },
            panels: { (try? adapter.panels($0)) ?? [] }
        )
        orientations.follow(udid, controller: controller)
        defer {
            _ = try? run(["devicectl", "device", "orientation", "set", "--device", udid, "portrait", "--timeout", "10", "--quiet"])
            _ = try? run(["simctl", "launch", udid, IntegrationHost.bundleID])
            orientations.forget(udid)
            manager.close(udid)
        }
        let window = try XCTUnwrap(controller.window)
        let screen = try XCTUnwrap(Self.screenView(in: window))
        let upright = await Self.wait(for: .portrait, in: controller, within: 3)
        XCTAssertTrue(upright, "the window did not open upright")

        // devicectl names the side the device is turned towards; the viewer names the way the
        // picture turns, so the landscapes swap.
        for (asked, shown) in [("landscapeLeft", DeviceOrientation.landscapeRight), ("landscapeRight", .landscapeLeft)] {
            let started = ContinuousClock.now
            _ = try run(["devicectl", "device", "orientation", "set", "--device", udid, asked, "--timeout", "10", "--quiet"])
            let followed = await Self.wait(for: shown, in: controller, within: 4)
            window.layoutIfNeeded()
            let size = window.contentLayoutRect.size
            print("RESULT turned \(asked) from outside, window \(controller.currentOrientation.rawValue) \(Int(size.width))x\(Int(size.height)) after \(Self.milliseconds(since: started)) ms")
            XCTAssertTrue(followed, "the window did not follow a turn to \(asked) from outside")
            XCTAssertGreaterThan(size.width, size.height, "the window stayed upright around a sideways screen")
            try await Task.sleep(for: .seconds(1))
            let before = Self.taps(log).count
            try await Self.click(screen, in: window, at: CGPoint(x: screen.bounds.midX - screen.bounds.width * 0.2, y: screen.bounds.midY + screen.bounds.height * 0.2))
            try await Task.sleep(for: .seconds(1.5))
            let taps = Self.taps(log)
            let landed = taps.last ?? "nothing"
            print("RESULT the upper left of the window after \(asked): \(landed)")
            XCTAssertGreaterThan(taps.count, before, "the click reached nothing")
            if let point = Self.point(from: landed) {
                XCTAssertLessThan(point.x, 0.5, "the upper left of the window landed at \(point)")
                XCTAssertLessThan(point.y, 0.5, "the upper left of the window landed at \(point)")
            }
        }

        _ = try run(["devicectl", "device", "orientation", "set", "--device", udid, "portrait", "--timeout", "10", "--quiet"])
        let back = await Self.wait(for: .portrait, in: controller, within: 4)
        XCTAssertTrue(back, "the window did not come back upright")

        _ = try run(["devicectl", "device", "orientation", "set", "--device", udid, "portraitUpsideDown", "--timeout", "10", "--quiet"])
        let upsideDown = await Self.samples(of: controller, for: 3)
        print("RESULT held upside down from outside, which the screen refuses: window \(Set(upsideDown).map(\.rawValue))")
        XCTAssertEqual(Set(upsideDown), [.portrait], "the window turned although the screen did not")

        _ = try run(["devicectl", "device", "orientation", "set", "--device", udid, "portrait", "--timeout", "10", "--quiet"])
        let uprightAgain = await Self.wait(for: .portrait, in: controller, within: 4)
        XCTAssertTrue(uprightAgain)

        // The window's own turn to upside down, as its rotate asks for it after landscape right.
        try adapter.setOrientation(.portraitUpsideDown, udid: udid)
        controller.setOrientation(.portraitUpsideDown)
        orientations.turned(udid, to: .portraitUpsideDown)
        let refused = await Self.samples(of: controller, for: 3.5)
        print("RESULT the window turned upside down itself, which the screen refuses: window \(refused.map(\.rawValue).reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } })")
        XCTAssertEqual(refused.last, .portrait, "the window stayed upside down around an upright screen")
        let next = try XCTUnwrap(orientations.lastTurn(udid)).rotatedLeft
        XCTAssertEqual(next, .landscapeLeft, "the next rotate asks for the refused turn again")
        try adapter.setOrientation(next, udid: udid)
        controller.setOrientation(next)
        orientations.turned(udid, to: next)
        let passed = await Self.samples(of: controller, for: 3)
        print("RESULT the next rotate after it: window \(passed.map(\.rawValue).reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } })")
        XCTAssertEqual(Set(passed), [.landscapeLeft], "the next rotate did not turn past upside down")

        _ = try run(["devicectl", "device", "orientation", "set", "--device", udid, "portrait", "--timeout", "10", "--quiet"])
        _ = try run(["simctl", "terminate", udid, IntegrationHost.bundleID])
        try await Task.sleep(for: .seconds(2))
        _ = try run(["devicectl", "device", "orientation", "set", "--device", udid, "landscapeLeft", "--timeout", "10", "--quiet"])
        let home = await Self.samples(of: controller, for: 3)
        print("RESULT the home screen, held sideways from outside: window \(Set(home).map(\.rawValue))")
        XCTAssertEqual(Set(home), [.portrait], "the window turned around a home screen that stays upright")
    }

    private static func screen(of udid: String, adapter: any SimulatorAdapter, panels: [DevicePanel]) async -> DeviceOrientation? {
        let angles = Dictionary(panels.map { ($0.screenID, $0.nativeRotation) }, uniquingKeysWith: { first, _ in first })
        guard let report = try? await adapter.displayReport(udid) else { return nil }
        return ScreenOrientationWatcher.reading(from: report, nativeRotation: { angles[$0] ?? 0 })?.orientation
    }

    private static func wait(for expected: DeviceOrientation, in controller: DeviceWindowController, within seconds: Double) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if controller.currentOrientation == expected { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return controller.currentOrientation == expected
    }

    private static func samples(of controller: DeviceWindowController, for seconds: Double) async -> [DeviceOrientation] {
        var shown: [DeviceOrientation] = []
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            shown.append(controller.currentOrientation)
            try? await Task.sleep(for: .milliseconds(50))
        }
        return shown
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    private static func click(_ view: NSView, in window: NSWindow, at spot: CGPoint) async throws {
        let inWindow = view.convert(spot, to: nil)
        view.mouseDown(with: try mouse(.leftMouseDown, at: inWindow, in: window))
        try await Task.sleep(for: .milliseconds(80))
        view.mouseUp(with: try mouse(.leftMouseUp, at: inWindow, in: window))
    }

    private static func mouse(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    private static func taps(_ log: URL) -> [String] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "")
            .split(separator: "\n").filter { $0.hasPrefix("TAP") }.map(String.init)
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
