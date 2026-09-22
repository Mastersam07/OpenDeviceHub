import XCTest
import OpenDeviceHubEngine

final class DeviceNotifierTests: XCTestCase {
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

    /// Only a device this test booted itself is ever shut down.
    private func bootOne(_ adapter: any SimulatorAdapter) throws -> String {
        guard let udid = try adapter.devices()
            .first(where: { $0.isAvailable && $0.state == .shutdown })?.udid else {
            throw XCTSkip("needs a shut down simulator to boot")
        }
        try simctl.boot(udid: udid)
        bootedByTest.append(udid)
        try simctl.waitForBoot(udid: udid)
        return udid
    }

    private func waitForState(
        _ state: DeviceState,
        of udid: String,
        in notifier: any DeviceNotifier,
        timeout: TimeInterval
    ) {
        let reached = expectation(description: "\(udid) reaches \(state)")
        let watcher = Task {
            for await change in notifier.changes where change.udid.caseInsensitiveCompare(udid) == .orderedSame {
                if change.state == state {
                    reached.fulfill()
                    return
                }
            }
        }
        wait(for: [reached], timeout: timeout)
        watcher.cancel()
    }

    func testTheNotifierIsAvailable() throws {
        try IntegrationGate.requireEnabled()
        let adapter = try makeAdapter()
        XCTAssertTrue(adapter.capabilities.contains(.deviceNotifications))
        let notifier = try adapter.watchDeviceStates()
        notifier.close()
    }

    /// The whole point of the notifier: a change made by something else, here simctl, arrives
    /// without anything asking for it.
    func testAShutdownAndABootBothArrive() throws {
        try IntegrationGate.requireEnabled()

        let adapter = try makeAdapter()
        let udid = try bootOne(adapter)
        let notifier = try adapter.watchDeviceStates()
        defer { notifier.close() }

        try simctl.shutdown(udid: udid)
        waitForState(.shutdown, of: udid, in: notifier, timeout: 30)

        try simctl.boot(udid: udid)
        waitForState(.booted, of: udid, in: notifier, timeout: 60)

        XCTAssertEqual(try adapter.devices().first { $0.udid == udid }?.state, .booted)
    }

    /// A closed notifier stops delivering, so a viewer that has shut its windows is not woken by a
    /// device it no longer shows.
    func testClosingStopsTheStream() throws {
        try IntegrationGate.requireEnabled()

        let adapter = try makeAdapter()
        let notifier = try adapter.watchDeviceStates()
        let finished = expectation(description: "the stream finishes")
        let watcher = Task {
            for await _ in notifier.changes {}
            finished.fulfill()
        }
        notifier.close()
        wait(for: [finished], timeout: 10)
        watcher.cancel()
    }
}
