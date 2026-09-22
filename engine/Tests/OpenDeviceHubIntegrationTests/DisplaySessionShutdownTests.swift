import CoreGraphics
import XCTest
import OpenDeviceHubEngine

/// A device that shuts down under an open display session used to take the whole process with it:
/// CoreSimulator invokes the registered callback with nil, the header said it never would, and
/// binding nil trapped in `swift_getObjectType`. One device going away killed every window.
final class DisplaySessionShutdownTests: XCTestCase {
    private let simctl = SimctlService()
    private var bootedByTest: [String] = []

    override func tearDownWithError() throws {
        for udid in bootedByTest {
            try? simctl.shutdown(udid: udid)
        }
        bootedByTest = []
    }

    private func makeAdapter() throws -> any SimulatorAdapter {
        try AdapterFactory.make(for: XcodeLocator.locate())
    }

    /// Only devices this test booted itself are ever shut down, so a session running beside somebody
    /// else's work leaves it alone.
    private func bootDevices(_ count: Int, _ adapter: any SimulatorAdapter) throws -> [String] {
        let candidates = try adapter.devices()
            .filter { $0.isAvailable && $0.state == .shutdown }
            .prefix(count)
            .map(\.udid)
        try XCTSkipUnless(candidates.count == count, "needs \(count) shut down simulators to boot")

        for udid in candidates {
            try simctl.boot(udid: udid)
            bootedByTest.append(udid)
            try simctl.waitForBoot(udid: udid)
        }
        return candidates
    }

    private func awaitFrame(
        from session: any DisplaySession,
        _ description: String,
        timeout: TimeInterval
    ) {
        let arrived = expectation(description: description)
        let watcher = Task {
            for await _ in session.frames {
                arrived.fulfill()
                return
            }
        }
        wait(for: [arrived], timeout: timeout)
        watcher.cancel()
    }

    func testOneDeviceShuttingDownLeavesTheOtherSessionAlive() throws {
        try IntegrationGate.requireEnabled()

        let adapter = try makeAdapter()
        let devices = try bootDevices(2, adapter)
        let doomed = devices[0]
        let survivor = devices[1]

        let doomedSession = try adapter.openDisplay(doomed)
        let survivorSession = try adapter.openDisplay(survivor)
        defer {
            doomedSession.close()
            survivorSession.close()
        }

        awaitFrame(from: survivorSession, "a frame before the shutdown", timeout: 30)

        try simctl.shutdown(udid: doomed)

        // Reaching this line at all is most of the test: the crash took the process down before any
        // assertion could run.
        let nudge = try adapter.openInput(survivor)
        defer { nudge.close() }
        let tapping = Task {
            // The surviving device only redraws on damage, so it is nudged into producing one.
            for _ in 0..<20 {
                let point = CGPoint(x: 0.5, y: 0.01)
                try? await nudge.touch(TouchEvent(phase: .began, points: [point]))
                try? await nudge.touch(TouchEvent(phase: .ended, points: [point]))
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        awaitFrame(from: survivorSession, "a frame after the shutdown", timeout: 30)
        tapping.cancel()

        XCTAssertEqual(
            try adapter.devices().first { $0.udid == doomed }?.state,
            .shutdown
        )
        XCTAssertEqual(
            try adapter.devices().first { $0.udid == survivor }?.state,
            .booted
        )
    }

    func testASessionSurvivesItsOwnDeviceShuttingDown() throws {
        try IntegrationGate.requireEnabled()

        let adapter = try makeAdapter()
        let udid = try bootDevices(1, adapter)[0]

        let session = try adapter.openDisplay(udid)
        defer { session.close() }
        awaitFrame(from: session, "a frame before the shutdown", timeout: 30)

        try simctl.shutdown(udid: udid)
        Thread.sleep(forTimeInterval: 5)

        XCTAssertEqual(
            try adapter.devices().first { $0.udid == udid }?.state,
            .shutdown,
            "the device really did shut down, so the callback path was exercised"
        )
    }
}
