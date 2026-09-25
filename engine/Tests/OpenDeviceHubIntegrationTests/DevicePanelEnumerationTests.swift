import CoreGraphics
import XCTest
import OpenDeviceHubEngine

final class DevicePanelEnumerationTests: XCTestCase {
    private func makeAdapter() throws -> any SimulatorAdapter {
        try AdapterFactory.make(for: XcodeLocator.locate())
    }

    private func bootedDevice() throws -> DeviceInfo {
        guard let booted = try makeAdapter().devices().first(where: { $0.state == .booted }) else {
            throw XCTSkip("no booted simulator, boot one to run this test")
        }
        return booted
    }

    func testEveryBootedDeviceReportsAtLeastOnePanel() throws {
        try IntegrationGate.requireEnabled()
        let panels = try makeAdapter().panels(bootedDevice().udid)
        XCTAssertFalse(panels.isEmpty)
        for panel in panels {
            XCTAssertGreaterThan(panel.pixelSize.width, 0, "\(panel.name) reported no width")
            XCTAssertGreaterThan(panel.pixelSize.height, 0, "\(panel.name) reported no height")
        }
        XCTAssertEqual(Set(panels.map(\.id)).count, panels.count, "panel identifiers repeat")
    }

    /// A foldable is the only device with two, and the point of the change: the old code returned
    /// the first and the second was unreachable.
    func testAFoldableReportsBothPanels() throws {
        try IntegrationGate.requireEnabled()
        let adapter = try makeAdapter()
        guard let foldable = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else {
            throw XCTSkip("no booted foldable, boot an iPhone Duo to run this test")
        }

        let panels = try adapter.panels(foldable.udid)
        XCTAssertEqual(panels.count, 2)
        XCTAssertEqual(Set(panels.map(\.name)), ["Unfolded", "Cover"])
        XCTAssertEqual(panels.filter(\.isMainScreen).count, 1, "exactly one panel is the main screen")

        // The device type calls the smaller panel its main screen, which is why the opener cannot
        // just take the largest or the first.
        let main = try XCTUnwrap(panels.first(where: \.isMainScreen))
        XCTAssertEqual(main.name, "Cover")
    }

    /// Each panel opens on its own surface, at its own size, rather than every choice landing on one.
    func testEachPanelOpensAtItsOwnSize() throws {
        try IntegrationGate.requireEnabled()
        let adapter = try makeAdapter()
        guard let foldable = try adapter.devices().first(where: {
            $0.state == .booted && $0.deviceTypeIdentifier.contains("Duo")
        }) else {
            throw XCTSkip("no booted foldable, boot an iPhone Duo to run this test")
        }

        for panel in try adapter.panels(foldable.udid) {
            let session = try adapter.openDisplay(foldable.udid, panel: panel)
            defer { session.close() }
            XCTAssertEqual(session.pixelSize, panel.pixelSize, "\(panel.name) opened at the wrong size")
        }
    }

    func testNamingNoPanelOpensTheMainScreen() throws {
        try IntegrationGate.requireEnabled()
        let adapter = try makeAdapter()
        let udid = try bootedDevice().udid
        let panels = try adapter.panels(udid)
        let session = try adapter.openDisplay(udid)
        defer { session.close() }

        let expected = panels.first(where: \.isMainScreen) ?? panels[0]
        XCTAssertEqual(session.pixelSize, expected.pixelSize)
    }
}
