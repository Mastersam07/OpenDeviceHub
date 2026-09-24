import XCTest
@testable import OpenDeviceHubEngine

/// Every argument list here was checked against `simctl help` on Xcode 27 before it was written.
/// The tests pin the shapes, because a wrong verb does not fail loudly: it does something else to
/// somebody's device.
final class SimctlDeviceControlTests: XCTestCase {
    private let udid = "60944F68-2A87-4EE5-AED5-BC08BFADF42A"

    func testEraseNamesTheDevice() {
        XCTAssertEqual(SimctlService.eraseArguments(udid: udid), ["simctl", "erase", udid])
    }

    func testICloudSync() {
        XCTAssertEqual(SimctlService.iCloudSyncArguments(udid: udid), ["simctl", "icloud_sync", udid])
    }

    func testContentSizeStepsBothWays() {
        XCTAssertEqual(
            SimctlService.contentSizeArguments(udid: udid, step: .increment),
            ["simctl", "ui", udid, "content_size", "increment"]
        )
        XCTAssertEqual(
            SimctlService.contentSizeArguments(udid: udid, step: .decrement),
            ["simctl", "ui", udid, "content_size", "decrement"]
        )
    }

    /// The words are `enabled` and `disabled`, not `on` and `off` or `true` and `false`.
    func testIncreaseContrastUsesSimctlsOwnWords() {
        XCTAssertEqual(
            SimctlService.increaseContrastArguments(udid: udid, enabled: true),
            ["simctl", "ui", udid, "increase_contrast", "enabled"]
        )
        XCTAssertEqual(
            SimctlService.increaseContrastArguments(udid: udid, enabled: false),
            ["simctl", "ui", udid, "increase_contrast", "disabled"]
        )
    }

    func testReadingContrastPassesNoValue() {
        XCTAssertEqual(
            SimctlService.readIncreaseContrastArguments(udid: udid),
            ["simctl", "ui", udid, "increase_contrast"]
        )
    }

    /// The scenario names are what `simctl location list` prints, spaces included.
    func testEveryScenarioIsPassedByItsOwnName() {
        XCTAssertEqual(SimctlService.LocationScenario.allCases.count, 4)
        for scenario in SimctlService.LocationScenario.allCases {
            XCTAssertEqual(
                SimctlService.locationScenarioArguments(udid: udid, scenario: scenario),
                ["simctl", "location", udid, "run", scenario.rawValue]
            )
        }
        XCTAssertEqual(SimctlService.LocationScenario.cityBicycleRide.rawValue, "City Bicycle Ride")
    }

    /// One argument, comma separated, which is the shape simctl documents.
    func testACustomLocationIsOneCommaSeparatedArgument() {
        XCTAssertEqual(
            SimctlService.locationSetArguments(udid: udid, latitude: 37.3349, longitude: -122.0090),
            ["simctl", "location", udid, "set", "37.3349,-122.009"]
        )
    }

    func testClearingTakesNoCoordinates() {
        XCTAssertEqual(
            SimctlService.locationClearArguments(udid: udid),
            ["simctl", "location", udid, "clear"]
        )
    }
}
