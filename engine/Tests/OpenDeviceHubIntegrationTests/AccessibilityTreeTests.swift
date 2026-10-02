import XCTest
import OpenDeviceHubEngine

final class AccessibilityTreeTests: XCTestCase {
    private func makeAdapter() throws -> any SimulatorAdapter {
        try AdapterFactory.make(for: XcodeLocator.locate())
    }

    func testReadsTheFrontmostAppOfABootedDevice() throws {
        try IntegrationGate.requireEnabled()
        let adapter = try makeAdapter()
        guard let booted = try adapter.devices().first(where: { $0.state == .booted }) else {
            throw XCTSkip("no booted simulator, boot one to run this test")
        }
        let root = try adapter.accessibilityTree(booted.udid)
        XCTAssertEqual(root.role, "AXApplication")
        XCTAssertGreaterThan(root.frame.width, 0)
        XCTAssertFalse(root.children.isEmpty)
    }

    func testReadsFromTheMainThread() throws {
        try IntegrationGate.requireEnabled()
        XCTAssertTrue(Thread.isMainThread)
        let adapter = try makeAdapter()
        guard let booted = try adapter.devices().first(where: { $0.state == .booted }) else {
            throw XCTSkip("no booted simulator, boot one to run this test")
        }
        XCTAssertNoThrow(try adapter.accessibilityTree(booted.udid))
    }

    func testRefusesAShutdownDevice() throws {
        try IntegrationGate.requireEnabled()
        let adapter = try makeAdapter()
        guard let shutdown = try adapter.devices().first(where: { $0.state == .shutdown }) else {
            throw XCTSkip("every simulator is booted")
        }
        XCTAssertThrowsError(try adapter.accessibilityTree(shutdown.udid)) { error in
            XCTAssertEqual(error as? EngineError, .deviceNotBooted(udid: shutdown.udid))
        }
    }
}
