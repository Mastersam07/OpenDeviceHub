import XCTest
@testable import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

final class StartupDevicesTests: XCTestCase {
    func testShowsEveryBootedDevice() {
        let plan = StartupDevices.plan(
            devices: [
                device("a", name: "iPhone 17", runtime: "iOS 27.0", state: .booted),
                device("b", name: "iPad Air", runtime: "iOS 27.0", state: .shutdown),
                device("c", name: "iPhone 16", runtime: "iOS 26.5", state: .booted),
            ],
            remembered: nil
        )
        XCTAssertEqual(Set(plan.udids), ["a", "c"])
        XCTAssertFalse(plan.boot)
    }

    func testBootedDevicesWinOverTheRememberedOne() {
        let plan = StartupDevices.plan(
            devices: [
                device("a", name: "iPhone 17", runtime: "iOS 27.0", state: .booted),
                device("b", name: "iPhone 16", runtime: "iOS 27.0", state: .shutdown),
            ],
            remembered: "b"
        )
        XCTAssertEqual(plan.udids, ["a"])
    }

    func testFallsBackToTheRememberedDevice() {
        let plan = StartupDevices.plan(
            devices: [
                device("a", name: "iPhone 17", runtime: "iOS 27.0", state: .shutdown),
                device("b", name: "iPhone 16", runtime: "iOS 26.5", state: .shutdown),
            ],
            remembered: "b"
        )
        XCTAssertEqual(plan.udids, ["b"])
        XCTAssertTrue(plan.boot)
    }

    func testIgnoresARememberedDeviceThatIsGone() {
        let plan = StartupDevices.plan(
            devices: [device("a", name: "iPhone 17", runtime: "iOS 27.0", state: .shutdown)],
            remembered: "deleted"
        )
        XCTAssertEqual(plan.udids, ["a"])
        XCTAssertTrue(plan.boot)
    }

    func testIgnoresARememberedDeviceWhoseRuntimeIsNoLongerAvailable() {
        let plan = StartupDevices.plan(
            devices: [
                device("a", name: "iPhone 17", runtime: "iOS 27.0", state: .shutdown),
                device("b", name: "iPhone 12", runtime: "iOS 18.1", state: .shutdown, available: false),
            ],
            remembered: "b"
        )
        XCTAssertEqual(plan.udids, ["a"])
    }

    func testWithNoHistoryPicksAPhoneOnTheNewestRuntime() {
        let plan = StartupDevices.plan(
            devices: [
                device("pad", name: "iPad Pro 13-inch", runtime: "iOS 27.0", state: .shutdown),
                device("old", name: "iPhone 17", runtime: "iOS 26.5", state: .shutdown),
                device("new", name: "iPhone 17", runtime: "iOS 27.0", state: .shutdown),
            ],
            remembered: nil
        )
        XCTAssertEqual(plan.udids, ["new"])
        XCTAssertTrue(plan.boot)
    }

    func testPrefersThePlainPhoneOverAVariantOrAHandNamedDevice() {
        let plan = StartupDevices.plan(
            devices: [
                device("named", name: "iPhone Duo", runtime: "iOS 27.0", state: .shutdown),
                device("pro", name: "iPhone 17 Pro Max", runtime: "iOS 27.0", state: .shutdown),
                device("plain", name: "iPhone 17", runtime: "iOS 27.0", state: .shutdown),
                device("older", name: "iPhone 16", runtime: "iOS 27.0", state: .shutdown),
            ],
            remembered: nil
        )
        XCTAssertEqual(plan.udids, ["plain"])
    }

    func testWithBootingTurnedOffNothingIsStarted() {
        let plan = StartupDevices.plan(
            devices: [
                device("a", name: "iPhone 17", runtime: "iOS 27.0", state: .shutdown),
                device("b", name: "iPhone 16", runtime: "iOS 26.5", state: .shutdown),
            ],
            remembered: "b",
            bootsMostRecent: false
        )
        XCTAssertTrue(plan.udids.isEmpty)
        XCTAssertFalse(plan.boot)
    }

    /// The setting governs starting a simulator, not hiding one. Anything already running is still
    /// shown, which is the difference between "do not boot for me" and "show me nothing".
    func testWhatIsAlreadyRunningIsShownEvenWithBootingTurnedOff() {
        let plan = StartupDevices.plan(
            devices: [
                device("a", name: "iPhone 17", runtime: "iOS 27.0", state: .booted),
                device("b", name: "iPhone 16", runtime: "iOS 26.5", state: .shutdown),
            ],
            remembered: "b",
            bootsMostRecent: false
        )
        XCTAssertEqual(plan.udids, ["a"])
        XCTAssertFalse(plan.boot)
    }

    func testAnEmptyMachineAsksForNothing() {
        let plan = StartupDevices.plan(devices: [], remembered: "a")
        XCTAssertTrue(plan.udids.isEmpty)
        XCTAssertFalse(plan.boot)
    }

    func testRuntimeGroupsAreNewestFirstAndSortedInside() {
        let groups = runtimeGroups(from: [
            device("a", name: "iPhone 16", runtime: "iOS 26.5", state: .shutdown),
            device("b", name: "iPhone 17 Pro", runtime: "iOS 27.0", state: .shutdown),
            device("c", name: "iPhone 17", runtime: "iOS 27.0", state: .shutdown),
            device("d", name: "iPhone 9", runtime: "iOS 27.0", state: .shutdown),
        ])
        XCTAssertEqual(groups.map(\.runtimeName), ["iOS 27.0", "iOS 26.5"])
        XCTAssertEqual(groups[0].devices.map(\.name), ["iPhone 9", "iPhone 17", "iPhone 17 Pro"])
        XCTAssertEqual(groups[1].devices.map(\.name), ["iPhone 16"])
    }

    func testRuntimeGroupsLeaveOutUnavailableDevices() {
        let groups = runtimeGroups(from: [
            device("a", name: "iPhone 12", runtime: "iOS 18.1", state: .shutdown, available: false),
            device("b", name: "iPhone 17", runtime: "iOS 27.0", state: .shutdown),
        ])
        XCTAssertEqual(groups.map(\.runtimeName), ["iOS 27.0"])
    }

    func testRemembersTheDeviceItWasGiven() {
        let store = RecentDeviceStore(storage: InMemoryPreferenceStorage(), key: "recent")
        XCTAssertNil(store.udid)
        store.remember("a")
        XCTAssertEqual(store.udid, "a")
    }

    private func device(
        _ udid: String,
        name: String,
        runtime: String,
        state: DeviceState,
        available: Bool = true
    ) -> DeviceInfo {
        DeviceInfo(
            udid: udid,
            name: name,
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.\(name.replacingOccurrences(of: " ", with: "-"))",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.\(runtime.replacingOccurrences(of: " ", with: "-"))",
            runtimeName: runtime,
            state: state,
            isAvailable: available
        )
    }
}

private final class InMemoryPreferenceStorage: PreferenceStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func text(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func setText(_ text: String, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = text
    }

    func removeText(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}
