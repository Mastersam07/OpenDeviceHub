import AppKit
import XCTest
@testable import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// A view that outlives its window keeps its drawables and its device's input session with it,
/// about 4 MB for every window opened.
@MainActor
final class WindowReleaseTests: XCTestCase {
    func testAClosedWindowFreesItsControllerWindowAndScreen() async throws {
        let manager = DeviceWindowManager(
            frameStore: WindowFrameStore(storage: InMemoryPreferences(), prefix: "test."),
            settings: ViewerSettings(storage: InMemoryPreferences(), prefix: "test."),
            shutdown: { _ in }
        )
        weak var controller: DeviceWindowController?
        weak var window: NSWindow?
        weak var screen: DeviceScreenView?
        do {
            let opened = try manager.open(
                device: DeviceInfo(
                    udid: "released",
                    name: "iPhone 17",
                    deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                    runtimeName: "iOS 27.0",
                    state: .booted,
                    isAvailable: true
                ),
                session: EmptySession(),
                input: NoInput(),
                scaleMode: .fit,
                bezelEnabled: true,
                keepOnTop: false,
                showFPS: false
            )
            controller = opened
            window = opened.window
            screen = opened.window.flatMap { Self.screen(in: $0) }
            XCTAssertNotNil(screen)
            manager.close("released")
        }
        for _ in 0..<20 where controller != nil || window != nil || screen != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNil(controller, "the controller outlived its window")
        XCTAssertNil(window, "the window outlived being closed")
        XCTAssertNil(screen, "the screen view outlived its window")
    }

    private static func screen(in window: NSWindow) -> DeviceScreenView? {
        func search(_ view: NSView) -> DeviceScreenView? {
            if let found = view as? DeviceScreenView { return found }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return window.contentView.flatMap(search)
    }
}

/// Clicks are only wired up for a window that can send them.
private final class NoInput: InputSession, @unchecked Sendable {
    func touch(_ event: TouchEvent) async throws {}
    func key(_ event: KeyEvent) async throws {}
    func button(_ button: HardwareButton, phase: ButtonPhase) async throws {}
    func close() {}
}

private final class EmptySession: DisplaySession, @unchecked Sendable {
    let frames = AsyncStream<DisplayFrame> { $0.finish() }
    let screenChanges = AsyncStream<ScreenProperties> { $0.finish() }
    let pixelSize = CGSize(width: 1206, height: 2622)
    let pointScale: CGFloat = 3
    let pixelsPerInch: CGFloat? = 460
    let supportsBezel = false
    func setBezelEnabled(_ enabled: Bool) {}
    func close() {}
}
