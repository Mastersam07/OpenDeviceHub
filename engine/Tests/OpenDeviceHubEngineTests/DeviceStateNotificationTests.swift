import XCTest
@testable import OpenDeviceHubEngine

/// The payload shape was read off a real boot and shutdown on Xcode 27 (27A266a): keys
/// `notification`, `device`, `new_state` and `prev_state`, with the states numbered the same way a
/// device listing numbers them.
final class DeviceStateNotificationTests: XCTestCase {
    private let device = NSObject()

    private func change(_ payload: Any?) -> DeviceStateChange? {
        DeviceStateNotification.change(from: payload) { _ in "UDID-1" }
    }

    func testReadsAShutdown() {
        let result = change([
            "notification": "device_state",
            "device": device,
            "new_state": NSNumber(value: 1),
            "prev_state": NSNumber(value: 4),
        ])
        XCTAssertEqual(result?.udid, "UDID-1")
        XCTAssertEqual(result?.state, .shutdown)
        XCTAssertEqual(result?.previousState, .shuttingDown)
    }

    func testReadsABoot() {
        let result = change([
            "notification": "device_state",
            "device": device,
            "new_state": NSNumber(value: 3),
            "prev_state": NSNumber(value: 2),
        ])
        XCTAssertEqual(result?.state, .booted)
        XCTAssertEqual(result?.previousState, .booting)
    }

    func testIgnoresNil() {
        XCTAssertNil(change(nil))
    }

    func testIgnoresSomethingThatIsNotADictionary() {
        XCTAssertNil(change("device_state"))
        XCTAssertNil(change(NSNumber(value: 3)))
    }

    func testIgnoresOtherNotifications() {
        XCTAssertNil(change([
            "notification": "availableDevices_changed",
            "device": device,
            "new_state": NSNumber(value: 3),
        ]))
    }

    func testIgnoresAPayloadWithNoDevice() {
        XCTAssertNil(change([
            "notification": "device_state",
            "new_state": NSNumber(value: 3),
        ]))
    }

    func testIgnoresADeviceThatCannotBeNamed() {
        let result = DeviceStateNotification.change(from: [
            "notification": "device_state",
            "device": device,
            "new_state": NSNumber(value: 3),
        ]) { _ in nil }
        XCTAssertNil(result)
    }

    func testIgnoresANonNumericState() {
        XCTAssertNil(change([
            "notification": "device_state",
            "device": device,
            "new_state": "Booted",
        ]))
    }

    func testAnUnknownStateNumberIsReportedAsUnknown() {
        let result = change([
            "notification": "device_state",
            "device": device,
            "new_state": NSNumber(value: 99),
        ])
        XCTAssertEqual(result?.state, .unknown)
        XCTAssertEqual(result?.previousState, .unknown, "a missing prev_state is not a failure")
    }
}
