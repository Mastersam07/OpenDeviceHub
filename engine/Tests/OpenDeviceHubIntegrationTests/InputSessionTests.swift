import CoreGraphics
import XCTest
import OpenDeviceHubEngine

final class InputSessionTests: XCTestCase {
    private func makeAdapter() throws -> any SimulatorAdapter {
        try AdapterFactory.make(for: XcodeLocator.locate())
    }

    private func bootedDevice() throws -> DeviceInfo {
        guard let booted = try makeAdapter().devices().first(where: { $0.state == .booted }) else {
            throw XCTSkip("no booted simulator, boot one to run this test")
        }
        return booted
    }

    func testOpensAnInputSessionOnABootedDevice() throws {
        try IntegrationGate.requireEnabled()
        let session = try makeAdapter().openInput(bootedDevice().udid)
        session.close()
    }

    func testRefusesAShutdownDevice() throws {
        try IntegrationGate.requireEnabled()
        let adapter = try makeAdapter()
        guard let shutdown = try adapter.devices().first(where: { $0.state == .shutdown }) else {
            throw XCTSkip("every simulator is booted")
        }
        XCTAssertThrowsError(try adapter.openInput(shutdown.udid)) { error in
            guard case EngineError.deviceNotBooted = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    func testSendsATapWithoutError() async throws {
        try IntegrationGate.requireEnabled()
        let session = try makeAdapter().openInput(try bootedDevice().udid)
        defer { session.close() }

        // The middle of the status bar, which is harmless wherever the device happens to be.
        let point = CGPoint(x: 0.5, y: 0.01)
        try await session.touch(TouchEvent(phase: .began, points: [point]))
        try await session.touch(TouchEvent(phase: .ended, points: [point]))
    }

    func testRejectsPhasesThatAreNotImplementedYet() async throws {
        try IntegrationGate.requireEnabled()
        let session = try makeAdapter().openInput(try bootedDevice().udid)
        defer { session.close() }

        for phase in [TouchEvent.Phase.moved, .cancelled] {
            do {
                try await session.touch(TouchEvent(phase: phase, points: [CGPoint(x: 0.5, y: 0.5)]))
                XCTFail("\(phase) should not be accepted yet")
            } catch EngineError.capabilityUnavailable {
                continue
            }
        }
    }

    func testRejectsMultipleContacts() async throws {
        try IntegrationGate.requireEnabled()
        let session = try makeAdapter().openInput(try bootedDevice().udid)
        defer { session.close() }

        do {
            try await session.touch(TouchEvent(
                phase: .began,
                points: [CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.7, y: 0.7)]
            ))
            XCTFail("two contacts should not be accepted yet")
        } catch EngineError.capabilityUnavailable {
        }
    }

    func testRejectsSendingOnAClosedSession() async throws {
        try IntegrationGate.requireEnabled()
        let session = try makeAdapter().openInput(try bootedDevice().udid)
        session.close()

        do {
            try await session.touch(TouchEvent(phase: .began, points: [CGPoint(x: 0.5, y: 0.5)]))
            XCTFail("a closed session should not send")
        } catch EngineError.capabilityUnavailable {
        }
    }
}
