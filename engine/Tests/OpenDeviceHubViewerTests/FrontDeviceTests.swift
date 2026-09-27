import AppKit
import XCTest
@testable import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

@MainActor
final class FrontDeviceTests: XCTestCase {
    private var manager: DeviceWindowManager!

    override func setUp() async throws {
        manager = DeviceWindowManager(
            frameStore: WindowFrameStore(storage: InMemoryPreferences(), prefix: "test."),
            settings: ViewerSettings(storage: InMemoryPreferences(), prefix: "test."),
            shutdown: { _ in }
        )
    }

    override func tearDown() async throws {
        for udid in manager.openUDIDs { manager.close(udid) }
        manager = nil
    }

    func testWithSettingsInFrontTheHighestDeviceWindowIsTheDeviceInFront() throws {
        let first = try open("first")
        let second = try open("second")
        let settings = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        settings.isReleasedWhenClosed = false
        settings.makeKeyAndOrderFront(nil)
        defer { settings.close() }

        first.window?.orderFront(nil)
        settings.orderFront(nil)
        XCTAssertEqual(manager.frontmostUDID, "first")

        second.window?.orderFront(nil)
        settings.orderFront(nil)
        XCTAssertEqual(manager.frontmostUDID, "second")
    }

    private func open(_ udid: String) throws -> DeviceWindowController {
        try manager.open(
            device: DeviceInfo(
                udid: udid,
                name: "iPhone 17",
                deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                runtimeName: "iOS 27.0",
                state: .booted,
                isAvailable: true
            ),
            session: QuietSession(),
            input: nil,
            scaleMode: .fit,
            bezelEnabled: true,
            keepOnTop: false,
            showFPS: false
        )
    }
}

private final class QuietSession: DisplaySession, @unchecked Sendable {
    let frames = AsyncStream<DisplayFrame> { $0.finish() }
    let screenChanges = AsyncStream<ScreenProperties> { $0.finish() }
    let pixelSize = CGSize(width: 1206, height: 2622)
    let pointScale: CGFloat = 3
    let pixelsPerInch: CGFloat? = 460
    let supportsBezel = false
    func setBezelEnabled(_ enabled: Bool) {}
    func close() {}
}
