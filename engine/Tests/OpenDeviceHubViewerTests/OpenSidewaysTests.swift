import AppKit
import XCTest
@testable import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

@MainActor
final class OpenSidewaysTests: XCTestCase {
    private var manager: DeviceWindowManager!

    override func setUp() async throws {
        manager = DeviceWindowManager(
            frameStore: WindowFrameStore(storage: InMemoryPreferences(), prefix: "test."),
            settings: ViewerSettings(storage: InMemoryPreferences(), prefix: "test."),
            shutdown: { _ in }
        )
    }

    override func tearDown() async throws {
        for udid in manager.openUDIDs { manager.controller(for: udid)?.window?.close() }
        manager = nil
    }

    func testAWindowOpensTheWayTheDeviceIsTurned() throws {
        let upright = try open("upright", .portrait)
        let sideways = try open("sideways", .landscapeLeft)
        XCTAssertEqual(sideways.currentOrientation, .landscapeLeft)

        let tall = try XCTUnwrap(upright.window).contentLayoutRect.size
        let wide = try XCTUnwrap(sideways.window).contentLayoutRect.size
        XCTAssertGreaterThan(tall.height, tall.width, "an upright window is not portrait")
        XCTAssertGreaterThan(wide.width, wide.height, "a sideways device opened in a portrait window")
    }

    func testOneTurnBringsASidewaysWindowUpright() throws {
        let controller = try open("sideways", .landscapeRight)
        controller.setOrientation(controller.currentOrientation.rotatedRight)
        XCTAssertEqual(controller.currentOrientation, .portrait)
        let size = try XCTUnwrap(controller.window).contentLayoutRect.size
        XCTAssertGreaterThan(size.height, size.width, "the turn back left the window sideways")
    }

    private func open(_ udid: String, _ orientation: DeviceOrientation) throws -> DeviceWindowController {
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
            session: StillSession(),
            input: nil,
            scaleMode: .fit,
            bezelEnabled: true,
            keepOnTop: false,
            showFPS: false,
            orientation: orientation
        )
    }
}

private final class StillSession: DisplaySession, @unchecked Sendable {
    let frames = AsyncStream<DisplayFrame> { $0.finish() }
    let screenChanges = AsyncStream<ScreenProperties> { $0.finish() }
    let pixelSize = CGSize(width: 1206, height: 2622)
    let pointScale: CGFloat = 3
    let pixelsPerInch: CGFloat? = 460
    let supportsBezel = false
    func setBezelEnabled(_ enabled: Bool) {}
    func close() {}
}
