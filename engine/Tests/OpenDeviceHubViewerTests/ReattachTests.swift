import AppKit
import XCTest
@testable import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

@MainActor
final class ReattachTests: XCTestCase {
    func testARestartReopensEverythingTheWindowWasGiven() async throws {
        let notifier = ScriptedNotifier()
        let manager = DeviceWindowManager(
            frameStore: WindowFrameStore(storage: InMemoryPreferences(), prefix: "test."),
            settings: ViewerSettings(storage: InMemoryPreferences(), prefix: "test."),
            shutdown: { _ in }
        )
        let device = DeviceInfo(
            udid: "restarting",
            name: "iPhone 17",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            runtimeName: "iOS 27.0",
            state: .booted,
            isAvailable: true
        )
        let controller = try manager.open(
            device: device,
            session: BlankSession(),
            input: nil,
            scaleMode: .fit,
            bezelEnabled: true,
            keepOnTop: false,
            showFPS: false
        )
        defer { manager.close(device.udid) }

        var attached = 0
        var retargeted: [Int] = []
        var reattached: [String] = []
        manager.onReattached = { reattached.append($0) }
        manager.follow(
            notifier,
            attach: { _ in
                attached += 1
                return DeviceAttachment(
                    session: BlankSession(),
                    input: nil,
                    retarget: { retargeted.append($0) }
                )
            },
            boot: { _ in }
        )

        notifier.send(device.udid, .shutdown, after: .booted)
        try await settle { controller.isDetached }
        XCTAssertTrue(controller.isDetached)

        notifier.send(device.udid, .booted, after: .booting)
        try await settle { !reattached.isEmpty }
        XCTAssertFalse(controller.isDetached, "the window stayed in its shut down state")
        XCTAssertEqual(attached, 1)
        XCTAssertEqual(retargeted, [0], "touches were not pointed at the screen in use")
        XCTAssertEqual(reattached, [device.udid], "nothing else was told the device came back")
    }

    private func settle(_ done: () -> Bool) async throws {
        for _ in 0..<50 where !done() {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private final class ScriptedNotifier: DeviceNotifier, @unchecked Sendable {
    let changes: AsyncStream<DeviceStateChange>
    private let continuation: AsyncStream<DeviceStateChange>.Continuation

    init() {
        var escaping: AsyncStream<DeviceStateChange>.Continuation!
        changes = AsyncStream { escaping = $0 }
        continuation = escaping
    }

    func send(_ udid: String, _ state: DeviceState, after previous: DeviceState) {
        continuation.yield(DeviceStateChange(udid: udid, state: state, previousState: previous))
    }

    func close() {
        continuation.finish()
    }
}

private final class BlankSession: DisplaySession, @unchecked Sendable {
    let frames = AsyncStream<DisplayFrame> { $0.finish() }
    let screenChanges = AsyncStream<ScreenProperties> { $0.finish() }
    let pixelSize = CGSize(width: 1206, height: 2622)
    let pointScale: CGFloat = 3
    let pixelsPerInch: CGFloat? = 460
    let supportsBezel = false
    func setBezelEnabled(_ enabled: Bool) {}
    func close() {}
}
