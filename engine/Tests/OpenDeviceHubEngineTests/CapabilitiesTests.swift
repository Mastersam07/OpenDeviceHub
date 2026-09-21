import XCTest
import OpenDeviceHubEngine

final class CapabilitiesTests: XCTestCase {
    func testNamesIsEmptyWhenNothingIsSupported() {
        XCTAssertEqual(Capabilities([]).names, [])
    }

    func testNamesListsOnlyTheContainedCapabilities() {
        let capabilities: Capabilities = [.display, .touch, .memoryWarning]
        XCTAssertEqual(capabilities.names, ["display", "touch", "memoryWarning"])
    }

    func testEveryKnownCapabilityHasADistinctBit() {
        let bits = Capabilities.known.map(\.capability.rawValue)
        XCTAssertEqual(Set(bits).count, bits.count)
        XCTAssertFalse(bits.contains(0))
    }

    func testKnownCoversEveryBitUsedByNames() {
        let union = Capabilities.known.reduce(into: Capabilities()) { $0.insert($1.capability) }
        XCTAssertEqual(union.names.count, Capabilities.known.count)
    }
}
