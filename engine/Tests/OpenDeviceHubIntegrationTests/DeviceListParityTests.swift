import XCTest
import OpenDeviceHubEngine

final class DeviceListParityTests: XCTestCase {
    private func makeAdapter() throws -> any SimulatorAdapter {
        try AdapterFactory.make(for: XcodeLocator.locate())
    }

    func testBothSourcesReportTheSameDeviceSet() throws {
        try IntegrationGate.requireEnabled()

        let adapterDevices = try makeAdapter().devices()
        let simctlDevices = try SimctlService().listDevices()

        let adapterUDIDs = Set(adapterDevices.map(\.udid))
        let simctlUDIDs = Set(simctlDevices.map(\.udid))

        XCTAssertFalse(adapterUDIDs.isEmpty, "no devices on this machine, nothing to compare")
        XCTAssertEqual(
            adapterUDIDs.subtracting(simctlUDIDs), [],
            "the adapter reported devices simctl did not"
        )
        XCTAssertEqual(
            simctlUDIDs.subtracting(adapterUDIDs), [],
            "simctl reported devices the adapter did not"
        )
    }

    func testBothSourcesAgreeOnEachDevice() throws {
        try IntegrationGate.requireEnabled()

        let adapterDevices = Dictionary(
            uniqueKeysWithValues: try makeAdapter().devices().map { ($0.udid, $0) }
        )
        for expected in try SimctlService().listDevices() {
            let actual = try XCTUnwrap(adapterDevices[expected.udid], "missing \(expected.udid)")
            XCTAssertEqual(actual.name, expected.name, expected.udid)
            XCTAssertEqual(actual.runtimeIdentifier, expected.runtimeIdentifier, expected.udid)
            XCTAssertEqual(actual.runtimeName, expected.runtimeName, expected.udid)
            XCTAssertEqual(actual.deviceTypeIdentifier, expected.deviceTypeIdentifier, expected.udid)
            XCTAssertEqual(actual.state, expected.state, expected.udid)
            XCTAssertEqual(actual.isAvailable, expected.isAvailable, expected.udid)
        }
    }

    func testAdapterReportsDisplayAndMemoryWarningCapabilities() throws {
        try IntegrationGate.requireEnabled()

        let capabilities = try makeAdapter().capabilities
        XCTAssertTrue(capabilities.contains(.display), "display capability missing")
        XCTAssertTrue(capabilities.contains(.memoryWarning), "memory warning capability missing")
    }
}
