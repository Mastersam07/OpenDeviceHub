import XCTest
@testable import OpenDeviceHubEngine

final class CameraControlDeviceTests: XCTestCase {
    private func requireDeviceType(_ identifier: String) throws {
        try XCTSkipIf(
            DeviceTypeProfile.modelIdentifier(forDeviceType: identifier) == nil,
            "\(identifier) is not installed here"
        )
    }

    func testReadsTheModelADeviceTypeStandsFor() throws {
        let identifier = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
        try requireDeviceType(identifier)
        XCTAssertEqual(DeviceTypeProfile.modelIdentifier(forDeviceType: identifier), "iPhone18,3")
    }

    func testPhonesWithTheButtonHaveIt() throws {
        var checked = 0
        for name in [
            "iPhone-16", "iPhone-16-Pro-Max", "iPhone-17", "iPhone-17-Pro", "iPhone-Air",
            "iPhone-18-Pro", "iPhone-18-Pro-Max",
        ] {
            let identifier = "com.apple.CoreSimulator.SimDeviceType.\(name)"
            guard DeviceTypeProfile.modelIdentifier(forDeviceType: identifier) != nil else { continue }
            checked += 1
            XCTAssertTrue(DeviceTypeProfile.hasCameraControl(deviceType: identifier), name)
        }
        try XCTSkipIf(checked == 0, "none of these device types is installed here")
    }

    func testPhonesAndTabletsWithoutTheButtonDoNot() throws {
        var checked = 0
        for name in ["iPhone-16e", "iPhone-17e", "iPhone-15-Pro", "iPad-Air-11-inch-M4"] {
            let identifier = "com.apple.CoreSimulator.SimDeviceType.\(name)"
            guard DeviceTypeProfile.modelIdentifier(forDeviceType: identifier) != nil else { continue }
            checked += 1
            XCTAssertFalse(DeviceTypeProfile.hasCameraControl(deviceType: identifier), name)
        }
        try XCTSkipIf(checked == 0, "none of these device types is installed here")
    }

    func testAnUnknownDeviceTypeHasNone() {
        XCTAssertNil(DeviceTypeProfile.modelIdentifier(forDeviceType: "com.example.not-a-device"))
        XCTAssertFalse(DeviceTypeProfile.hasCameraControl(deviceType: "com.example.not-a-device"))
    }
}
