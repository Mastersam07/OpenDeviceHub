import AppKit
import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// A click on a foldable's window, driven as a real mouse event, and what the device is sent for it.
@MainActor
final class WindowTapOrderTests: XCTestCase {
    private final class Recorder: InputSession, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [TouchEvent] = []

        var events: [TouchEvent] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func touch(_ event: TouchEvent) async throws {
            // Long enough that a contact coming up would overtake one going down, if they were not
            // held in order.
            try? await Task.sleep(for: .milliseconds(event.phase == .began ? 120 : 0))
            add(event)
        }

        private func add(_ event: TouchEvent) {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(event)
        }

        func key(_ event: KeyEvent) async throws {}
        func button(_ button: HardwareButton, phase: ButtonPhase) async throws {}
        func close() {}
    }

    func testATapArrivesDownThenUp() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else { throw XCTSkip("no booted foldable") }
        let panels = try adapter.panels(device.udid)
        guard let unfolded = panels.first(where: { $0.name == "Unfolded" }) else {
            throw XCTSkip("not a foldable")
        }

        let recorder = Recorder()
        let manager = DeviceWindowManager()
        let controller = try manager.open(
            device: device,
            session: try adapter.openDisplay(device.udid, panel: unfolded),
            input: recorder,
            scaleMode: .fit,
            bezelEnabled: false,
            keepOnTop: false,
            showFPS: false,
            foldsAtHinge: true,
            panelNativeRotation: unfolded.nativeRotation
        )
        let window = try XCTUnwrap(controller.window)
        let model = try XCTUnwrap(Self.modelView(in: window))
        model.setHingeAngle(FoldableControl.openAngle)
        window.layoutIfNeeded()

        let middle = model.convert(CGPoint(x: model.bounds.midX, y: model.bounds.midY), to: nil)
        model.mouseDown(with: try Self.click(.leftMouseDown, at: middle, in: window))
        model.mouseUp(with: try Self.click(.leftMouseUp, at: middle, in: window))
        try await Task.sleep(for: .seconds(1))

        let phases = recorder.events.map(\.phase)
        XCTAssertEqual(phases, [.began, .ended], "a tap is one contact down and then up")
        manager.close(device.udid)
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

    private static func click(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}
