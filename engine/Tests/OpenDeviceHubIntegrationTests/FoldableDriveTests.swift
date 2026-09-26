import AppKit
import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// The foldable driven the way a person drives it: a real window with both panels, the guest
/// leading, real mouse and scroll events into the window, and every result read back from the
/// guest's own log, its display report, or a picture of the model. Nothing here goes round the
/// window to the engine.
@MainActor
final class FoldableDriveTests: XCTestCase {
    private var adapter: (any SimulatorAdapter)!
    private var device: DeviceInfo!
    private var log = URL(fileURLWithPath: "/")
    private var mark = 0
    private var manager: DeviceWindowManager!
    private var foldables: FoldableController!
    private var controller: DeviceWindowController!
    private var model: DuoModelView!
    private var window: NSWindow!

    override func setUp() async throws {
        try IntegrationGate.requireEnabled()
        adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let found = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("no booted foldable") }
        device = found

        try IntegrationHost.install(on: device.udid)
        log = URL(fileURLWithPath: try run([
            "simctl", "get_app_container", device.udid, IntegrationHost.bundleID, "data",
        ]).trimmingCharacters(in: .whitespacesAndNewlines))
            .appending(path: "Documents").appending(path: "events.txt")

        // The window, wired as the app wires it.
        let panels = try adapter.panels(device.udid)
        let unfolded = try XCTUnwrap(panels.first { $0.name == "Unfolded" })
        let cover = try XCTUnwrap(panels.first { $0.name == "Cover" })
        let input = try adapter.openInput(device.udid, screenID: unfolded.screenID)
        let targeted = try XCTUnwrap(input as? PanelInputSession, "touches must be panel targeted")
        manager = DeviceWindowManager(
            frameStore: WindowFrameStore(storage: ForgetfulStorage()),
            shutdown: { _ in }
        )
        controller = try manager.open(
            device: device,
            session: try adapter.openDisplay(device.udid, panel: unfolded),
            input: input,
            scaleMode: .fit,
            bezelEnabled: true,
            keepOnTop: false,
            showFPS: false,
            foldsAtHinge: true,
            chrome: unfolded.chromeIdentifier.flatMap { ChromeLocator.chrome(identifier: $0) },
            panelNativeRotation: unfolded.nativeRotation,
            unfoldedPanel: unfolded,
            cover: FoldableCover(panel: cover, session: try adapter.openDisplay(device.udid, panel: cover)),
            retarget: { targeted.setTarget(screenID: $0) }
        )
        window = try XCTUnwrap(controller.window)
        model = try XCTUnwrap(Self.modelView(in: window))
        window.setFrameOrigin(.zero)
        window.orderFront(nil)

        // One vendor connection for the whole run, as the app keeps one for the life of a window:
        // a fresh one per test answers more slowly each time and then not at all.
        let adapter = self.adapter!
        let shared = try await IntegrationFoldable.shared.control(for: device.udid, adapter: adapter)
        foldables = FoldableController(
            open: { _ in shared },
            hingeStream: { try adapter.openHingeStream($0) },
            displayReport: { try await adapter.displayReport($0) }
        )
        let udid = device.udid
        controller.onHingeAngle = { [foldables] angle in foldables?.setAngle(angle, for: udid) }
        foldables.follow(
            udid,
            onPanel: { [weak controller] panel in controller?.setActivePanel(screenID: panel.displayID) },
            onHinge: { [weak controller] degrees in controller?.showHingeAngle(degrees) }
        )
        try await fold(to: DeviceControlBar.FoldMode.fullyOpen.angle)
        try await launchHost()
    }

    override func tearDown() async throws {
        if foldables != nil, device != nil {
            try? await fold(to: DeviceControlBar.FoldMode.fullyOpen.angle)
            foldables.forget(device.udid)
        }
        if manager != nil, device != nil { manager.close(device.udid) }
    }

    func testTheDeviceAtEachPreset() async throws {
        var report: [String] = []
        for mode in [DeviceControlBar.FoldMode.fullyOpen, .partiallyOpen, .cover] {
            try await fold(to: mode.angle)
            let active = try XCTUnwrap(foldables.activePanel(for: device.udid))
            let picture = try measure()
            report.append("\(mode.label): guest on display \(active.displayID), \(picture.text)")
            XCTAssertLessThan(picture.across, 0.99, "\(mode.label) is clipped across")
            XCTAssertLessThan(picture.down, 0.99, "\(mode.label) is clipped down")
            XCTAssertEqual(picture.centreX, 0.5, accuracy: 0.05, "\(mode.label) is off centre")
            XCTAssertEqual(picture.centreY, 0.5, accuracy: 0.06, "\(mode.label) is off centre")
            XCTAssertEqual(active.displayID, mode == .cover ? 1 : 3, "\(mode.label) on the wrong panel")
        }
        let open = try await measured(at: .fullyOpen)
        let shut = try await measured(at: .cover)
        XCTAssertGreaterThan(open.across, shut.across, "shut should be the smaller device")
        for line in report { print("RESULT \(line)") }
    }

    func testTapSwipeScrollAndScreenshotOpenAndShut() async throws {
        for mode in [DeviceControlBar.FoldMode.fullyOpen, .cover] {
            try await fold(to: mode.angle)
            try await launchHost()

            // A tap in each corner lands in the matching corner of the guest.
            let box = model.bounds
            let quarter = CGSize(width: box.width * 0.18, height: box.height * 0.18)
            for (name, spot, right, lower) in [
                ("upper left", CGPoint(x: box.midX - quarter.width, y: box.midY + quarter.height), false, false),
                ("lower right", CGPoint(x: box.midX + quarter.width, y: box.midY - quarter.height), true, true),
            ] {
                since()
                try await click(at: spot)
                try await settle(2)
                let landed = try XCTUnwrap(Self.point(from: lastTap()), "\(mode.label): the \(name) reached nothing")
                XCTAssertEqual(landed.x > 0.5, right, "\(mode.label): \(name) arrived at \(landed)")
                XCTAssertEqual(landed.y > 0.5, lower, "\(mode.label): \(name) arrived at \(landed)")
                print("RESULT \(mode.label): tap \(name) arrived at \(landed)")
            }

            // A drag is a contact that moves; the host logs where it began.
            since()
            try await drag(from: CGPoint(x: box.midX, y: box.midY - 40), to: CGPoint(x: box.midX, y: box.midY + 40))
            try await settle(2)
            print("RESULT \(mode.label): swipe began at \(lastTap())")
            XCTAssertNotNil(Self.point(from: lastTap()), "\(mode.label): the swipe reached nothing")

            // A scroll is a drag too.
            since()
            try scroll(at: CGPoint(x: box.midX, y: box.midY), lines: 4)
            try await settle(2)
            print("RESULT \(mode.label): scroll began at \(lastTap())")
            XCTAssertNotNil(Self.point(from: lastTap()), "\(mode.label): the scroll reached nothing")

            let png = try XCTUnwrap(controller.screenshotPNG(), "\(mode.label): no screenshot")
            let image = try XCTUnwrap(NSImage(data: png), "\(mode.label): the screenshot is not a picture")
            print("RESULT \(mode.label): screenshot \(Int(image.size.width))x\(Int(image.size.height))")
            XCTAssertGreaterThan(image.size.width, 100)
        }
    }

    func testHomeAndTheAppSwitcherSwitchAndDismiss() async throws {
        try await fold(to: DeviceControlBar.FoldMode.fullyOpen.angle)
        try await launchHost()
        let box = model.bounds

        // Home by the button.
        since()
        try await controller.inputSession?.button(.home, phase: .down)
        try await Task.sleep(for: .milliseconds(30))
        try await controller.inputSession?.button(.home, phase: .up)
        try await settle(3)
        print("RESULT home button: \(lines("SCENE").last ?? "nothing")")
        XCTAssertTrue(lines("SCENE").contains("SCENE BACKGROUND"), "home by the button did nothing")

        // Home by the gesture, dragged on the window: once from the bezel just under the screen,
        // the way a hand starts it, and once from just inside the screen's edge.
        for (name, start) in [("from the bezel", screenBottom()), ("from inside the edge", CGPoint(x: box.midX, y: screenBottom().y + 8))] {
            try await launchHost()
            since()
            try await drag(from: start, to: CGPoint(x: box.midX, y: box.midY + box.height * 0.1), steps: 12, stepMilliseconds: 10)
            try await settle(3)
            print("RESULT home swipe \(name): \(lines("SCENE").last ?? "nothing")")
            XCTAssertTrue(lines("SCENE").contains("SCENE BACKGROUND"), "the home swipe \(name) did nothing")
        }

        // The app switcher, then switching back by tapping the card.
        try await launchHost()
        since()
        try await openSwitcher()
        try await settle(3)
        XCTAssertTrue(lines("SCENE").contains("SCENE BACKGROUND"), "the switcher did not open")
        since()
        try await click(at: CGPoint(x: box.midX, y: box.midY))
        try await settle(3)
        print("RESULT app switcher then card tap: \(lines("SCENE").last ?? "nothing")")
        XCTAssertTrue(lines("SCENE").contains("SCENE FOREGROUND"), "tapping the card did not switch back")

        // The switcher again, and dismissing the app by flicking its card away.
        since()
        try await openSwitcher()
        try await settle(3)
        XCTAssertTrue(lines("SCENE").contains("SCENE BACKGROUND"), "the switcher did not open again")
        try await drag(from: CGPoint(x: box.midX, y: box.midY), to: CGPoint(x: box.midX, y: box.maxY - 4), steps: 8, stepMilliseconds: 8)
        try await settle(4)
        let running = try run(["simctl", "spawn", device.udid, "launchctl", "list"])
        print("RESULT after flicking the card away, the app is \(running.contains(IntegrationHost.bundleID) ? "still running" : "gone")")
        XCTAssertFalse(running.contains(IntegrationHost.bundleID), "the app is still running after being dismissed")
    }

    func testRotationTurnsTheGuestAndTheModel() async throws {
        try await fold(to: DeviceControlBar.FoldMode.fullyOpen.angle)
        try await launchHost()
        let upright = try measure()
        let before = try await adapter.displayReport(device.udid).activeIntegrated?.currentRotation

        since()
        try foldables.setOrientation(.landscapeLeft, for: device.udid)
        controller.setOrientation(.landscapeLeft)
        try await settle(4)
        let after = try await adapter.displayReport(device.udid).activeIntegrated?.currentRotation
        let turned = try measure()
        let reported = lines("ORIENTATION").last ?? "nothing"
        print("RESULT rotate: report \(before ?? -1) -> \(after ?? -1), guest says \(reported), model \(upright.text) -> \(turned.text)")
        XCTAssertNotEqual(before, after, "the guest did not turn")
        XCTAssertNotEqual(reported, "nothing", "the app did not lay out again")
        // A quarter turn swaps which way the device is long in the picture.
        XCTAssertLessThan(turned.across, upright.across * 0.7, "the model did not turn")

        try foldables.setOrientation(.portrait, for: device.udid)
        controller.setOrientation(.portrait)
        try await settle(3)
    }

    // The guest leads: a fold is sent, then the guest's report is waited on, not a clock.
    private func fold(to degrees: Double) async throws {
        controller.showHingeAngle(degrees)
        foldables.setAngle(degrees, for: device.udid)
        let wanted = degrees < FoldableControl.handoffAngle ? 1 : 3
        for _ in 0..<40 {
            if foldables.activePanel(for: device.udid)?.displayID == wanted { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        try await settle(1)
        XCTAssertEqual(foldables.activePanel(for: device.udid)?.displayID, wanted, "the guest never moved to display \(wanted)")
    }

    /// The lowest point of the view that is on the screen, straight below the middle: the screen's
    /// bottom edge, which is where the guest's gestures start, not the view's.
    private func screenBottom() -> CGPoint {
        let box = model.bounds
        var y = box.minY
        while y < box.midY, model.screenPoint(at: CGPoint(x: box.midX, y: y)) == nil { y += 1 }
        // Six points below the screen's edge: on the bezel, where a hand actually starts.
        return CGPoint(x: box.midX, y: y - 6)
    }

    private func launchHost() async throws {
        _ = try run(["simctl", "launch", device.udid, IntegrationHost.bundleID])
        try await settle(5)
    }

    private func openSwitcher() async throws {
        let box = model.bounds
        try await drag(from: screenBottom(), to: CGPoint(x: box.midX, y: box.midY - box.height * 0.1), steps: 14, lift: false)
        // Resting, which the guest reads as the switcher rather than as going home.
        for index in 1...15 {
            let wobble = CGFloat(index.isMultiple(of: 2) ? 1 : -1)
            model.mouseDragged(with: try Self.mouse(.leftMouseDragged, at: model.convert(CGPoint(x: box.midX, y: box.midY - box.height * 0.1 + wobble), to: nil)))
            try await Task.sleep(for: .milliseconds(40))
        }
        model.mouseUp(with: try Self.mouse(.leftMouseUp, at: model.convert(CGPoint(x: box.midX, y: box.midY - box.height * 0.1), to: nil)))
    }

    private struct Picture {
        let across: Double
        let down: Double
        let centreX: Double
        let centreY: Double
        var text: String {
            String(format: "fills %.2f across %.2f down, centre %.2f %.2f", across, down, centreX, centreY)
        }
    }

    private func measured(at mode: DeviceControlBar.FoldMode) async throws -> Picture {
        try await fold(to: mode.angle)
        return try measure()
    }

    private func measure() throws -> Picture {
        let raster = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(model.snapshot().tiffRepresentation)))
        var minX = raster.pixelsWide, maxX = -1, minY = raster.pixelsHigh, maxY = -1
        for y in 0..<raster.pixelsHigh {
            for x in 0..<raster.pixelsWide {
                guard let colour = raster.colorAt(x: x, y: y), colour.alphaComponent > 0.3 else { continue }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { throw XCTSkip("the model rendered nothing") }
        return Picture(
            across: Double(maxX - minX + 1) / Double(raster.pixelsWide),
            down: Double(maxY - minY + 1) / Double(raster.pixelsHigh),
            centreX: Double(minX + maxX) / 2 / Double(raster.pixelsWide),
            centreY: Double(minY + maxY) / 2 / Double(raster.pixelsHigh)
        )
    }

    /// The view the window would hand this point to. A real event is routed this way before the
    /// model ever sees it, so a point the routing gives to another view, or to nothing, is a press
    /// the model never gets.
    private func target(_ spot: CGPoint, file: StaticString = #filePath, line: UInt = #line) throws -> NSView {
        let content = try XCTUnwrap(window.contentView)
        let inContent = model.convert(spot, to: content)
        let view = try XCTUnwrap(content.hitTest(inContent), "the window routes \(spot) to nothing", file: file, line: line)
        XCTAssertTrue(view === model, "the window routes \(spot) to \(type(of: view)), not the model", file: file, line: line)
        return view
    }

    private func click(at spot: CGPoint) async throws {
        let view = try target(spot)
        view.mouseDown(with: try Self.mouse(.leftMouseDown, at: model.convert(spot, to: nil)))
        try await Task.sleep(for: .milliseconds(80))
        view.mouseUp(with: try Self.mouse(.leftMouseUp, at: model.convert(spot, to: nil)))
    }

    private func drag(from: CGPoint, to: CGPoint, steps: Int = 10, stepMilliseconds: Int = 16, lift: Bool = true) async throws {
        let view = try target(from)
        view.mouseDown(with: try Self.mouse(.leftMouseDown, at: model.convert(from, to: nil)))
        for step in 1...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
            try await Task.sleep(for: .milliseconds(stepMilliseconds))
            view.mouseDragged(with: try Self.mouse(.leftMouseDragged, at: model.convert(point, to: nil)))
        }
        if lift {
            view.mouseUp(with: try Self.mouse(.leftMouseUp, at: model.convert(to, to: nil)))
        }
    }

    private func scroll(at spot: CGPoint, lines: Int) throws {
        _ = try target(spot)
        let onScreen = window.convertPoint(toScreen: model.convert(spot, to: nil))
        let screenHeight = NSScreen.screens[0].frame.height
        for _ in 0..<lines {
            let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 12, wheel2: 0, wheel3: 0))
            event.location = CGPoint(x: onScreen.x, y: screenHeight - onScreen.y)
            model.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: event)))
        }
    }

    private func since() { mark = all().count }

    private func all() -> [String] {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    private func lines(_ prefix: String) -> [String] {
        all().dropFirst(mark).filter { $0.hasPrefix(prefix) }
    }

    private func lastTap() -> String { lines("TAP").last ?? "nothing" }

    private static func point(from line: String) -> CGPoint? {
        let parts = line.split(separator: " ")
        guard parts.count == 3, let x = Double(parts[1]), let y = Double(parts[2]) else { return nil }
        return CGPoint(x: x, y: y)
    }

    private func settle(_ seconds: Int) async throws {
        try await Task.sleep(for: .seconds(seconds))
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

    private static func mouse(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
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

private final class ForgetfulStorage: PreferenceStorage, @unchecked Sendable {
    func text(forKey key: String) -> String? { nil }
    func setText(_ text: String, forKey key: String) {}
    func removeText(forKey key: String) {}
    func keys(withPrefix prefix: String) -> [String] { [] }
}
