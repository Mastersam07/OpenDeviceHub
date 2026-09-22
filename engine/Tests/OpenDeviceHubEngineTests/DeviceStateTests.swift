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
    func testTheVerifiedMajorsUseTheOneAdapter() throws {
        for version in [XcodeVersion(major: 26), XcodeVersion(major: 26, minor: 5), XcodeVersion(major: 27)] {
            XCTAssertEqual(try AdapterFactory.kind(for: version), .coreSimulator, "\(version)")
            XCTAssertNil(AdapterFactory.advisory(for: version), "\(version) is verified")
        }
    }

    func testANewerMajorRunsWithAnAdvisory() throws {
        let version = XcodeVersion(major: 28)
        XCTAssertEqual(try AdapterFactory.kind(for: version), .coreSimulator)
        let advisory = try XCTUnwrap(AdapterFactory.advisory(for: version))
        XCTAssertTrue(advisory.contains("28"))
        XCTAssertTrue(advisory.contains("27"), "it should name what was actually verified")
    }

    func testAnOlderMajorFailsAndSaysWhat() {
        XCTAssertThrowsError(try AdapterFactory.kind(for: XcodeVersion(major: 25))) { error in
            guard case EngineError.unsupportedXcode(let version, let supported, let note) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(version, "25.0")
            XCTAssertEqual(supported, "26 and 27")
            XCTAssertTrue(note.contains("oldest"))
        }
    }
}

