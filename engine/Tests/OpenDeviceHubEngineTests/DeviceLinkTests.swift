import XCTest
@testable import OpenDeviceHubEngine

/// A link this app takes over has to be sorted into three piles: one it can show, one only Device
/// Hub understands, and one that is not a device link at all. Getting the middle pile wrong means
/// swallowing links that then do nothing.
final class DeviceLinkTests: XCTestCase {
    private let udid = "60944F68-2A87-4EE5-AED5-BC08BFADF42A"

    private func destination(_ string: String) -> DeviceLink.Destination {
        guard let url = URL(string: string) else { return .notADeviceLink }
        return DeviceLink.destination(for: url)
    }

    func testDeviceHubOpenNamesASimulator() {
        XCTAssertEqual(destination("devices://device/open?id=\(udid)"), .simulator(udid: udid))
    }

    func testDeviceHubSelectNamesASimulator() {
        XCTAssertEqual(destination("devices://manage/select?id=\(udid)"), .simulator(udid: udid))
    }

    func testOurOwnSchemeNamesASimulator() {
        XCTAssertEqual(destination("odhub://open?udid=\(udid)"), .simulator(udid: udid))
    }

    func testTheUdidIsNormalisedToUppercase() {
        XCTAssertEqual(
            destination("devices://device/open?id=\(udid.lowercased())"),
            .simulator(udid: udid)
        )
    }

    /// The pile that matters. Anything on the scheme that is not understood goes back to Device Hub
    /// whole, rather than being dropped.
    func testAnUnknownRouteGoesToDeviceHub() {
        XCTAssertEqual(destination("devices://something/else?id=\(udid)"), .deviceHub)
    }

    func testALinkWithNoIdentifierGoesToDeviceHub() {
        XCTAssertEqual(destination("devices://device/open"), .deviceHub)
    }

    /// A physical device's identifier is not a UUID, so it is not ours to show.
    func testAPhysicalDeviceGoesToDeviceHub() {
        XCTAssertEqual(destination("devices://device/open?id=00008120-001A2B3C4D5E6F00"), .deviceHub)
    }

    /// Extra parameters mean the link is asking for something beyond "open this", which only Device
    /// Hub knows how to honour.
    func testExtraParametersGoToDeviceHub() {
        XCTAssertEqual(
            destination("devices://device/open?id=\(udid)&action=install"),
            .deviceHub
        )
    }

    func testCredentialsOrPortsAreNotTrusted() {
        XCTAssertEqual(destination("devices://user:pw@device/open?id=\(udid)"), .deviceHub)
        XCTAssertEqual(destination("devices://device/open?id=\(udid)#fragment"), .deviceHub)
    }

    func testAnotherAppsSchemeIsNotOurs() {
        XCTAssertEqual(destination("https://example.com/device/open?id=\(udid)"), .notADeviceLink)
        XCTAssertEqual(destination("simulator://open?udid=\(udid)"), .notADeviceLink)
    }

    func testOurSchemeWithoutAUdidIsNotALink() {
        XCTAssertEqual(destination("odhub://open"), .notADeviceLink)
        XCTAssertEqual(destination("odhub://elsewhere?udid=\(udid)"), .notADeviceLink)
    }
}
