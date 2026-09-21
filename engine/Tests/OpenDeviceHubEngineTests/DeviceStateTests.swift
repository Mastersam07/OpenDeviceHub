import XCTest
@testable import OpenDeviceHubEngine

final class DeviceStateNumberTests: XCTestCase {
    func testMapsTheNumbersObservedOnXcode26() {
        XCTAssertEqual(DeviceState.from(state: 1, stateString: ""), .shutdown)
        XCTAssertEqual(DeviceState.from(state: 2, stateString: ""), .booting)
        XCTAssertEqual(DeviceState.from(state: 3, stateString: ""), .booted)
        XCTAssertEqual(DeviceState.from(state: 4, stateString: ""), .shuttingDown)
    }

    func testFallsBackToTheStateStringForUnknownNumbers() {
        XCTAssertEqual(DeviceState.from(state: 0, stateString: "Booted"), .booted)
        XCTAssertEqual(DeviceState.from(state: 99, stateString: "Shutting Down"), .shuttingDown)
    }

    func testUnknownNumberAndUnknownStringIsUnknown() {
        XCTAssertEqual(DeviceState.from(state: 0, stateString: "Creating"), .unknown)
        XCTAssertEqual(DeviceState.from(state: 77, stateString: ""), .unknown)
    }
}

final class DeviceStateStringTests: XCTestCase {
    func testMatchesTheStringsSimctlReports() {
        XCTAssertEqual(DeviceState.from(stateString: "Shutdown"), .shutdown)
        XCTAssertEqual(DeviceState.from(stateString: "Booted"), .booted)
        XCTAssertEqual(DeviceState.from(stateString: "Booting"), .booting)
    }

    func testIgnoresCaseAndTheSpaceInShuttingDown() {
        XCTAssertEqual(DeviceState.from(stateString: "Shutting Down"), .shuttingDown)
        XCTAssertEqual(DeviceState.from(stateString: "shuttingdown"), .shuttingDown)
        XCTAssertEqual(DeviceState.from(stateString: "BOOTED"), .booted)
    }

    func testUnrecognisedStringIsUnknown() {
        XCTAssertEqual(DeviceState.from(stateString: ""), .unknown)
        XCTAssertEqual(DeviceState.from(stateString: "Creating"), .unknown)
    }
}

final class AdapterSelectionTests: XCTestCase {
    func testXcode26SelectsTheXcode26Adapter() throws {
        XCTAssertEqual(try AdapterFactory.kind(for: XcodeVersion(major: 26, minor: 5)), .xcode26)
        XCTAssertEqual(try AdapterFactory.kind(for: XcodeVersion(major: 26)), .xcode26)
    }

    func testXcode27IsRejectedWhileItsAdapterIsMissing() {
        XCTAssertThrowsError(try AdapterFactory.kind(for: XcodeVersion(major: 27))) { error in
            guard case EngineError.unsupportedXcode(let version, let supported, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(version, "27.0")
            XCTAssertEqual(supported, "26")
        }
    }

    func testANewerMajorIsAlsoRejectedForNow() {
        XCTAssertThrowsError(try AdapterFactory.kind(for: XcodeVersion(major: 28)))
    }

    func testOlderXcodeIsRejected() {
        XCTAssertThrowsError(try AdapterFactory.kind(for: XcodeVersion(major: 25, minor: 3)))
    }
}
