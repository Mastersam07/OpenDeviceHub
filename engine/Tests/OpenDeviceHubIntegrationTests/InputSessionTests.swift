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

    func testRejectsOnlyTheCancelledPhase() async throws {
        try IntegrationGate.requireEnabled()
        let session = try makeAdapter().openInput(try bootedDevice().udid)
        defer { session.close() }

        // Moved is supported now, so only cancelled is refused. Nothing in the Indigo surface
        // corresponds to a cancelled contact.
        try await session.touch(TouchEvent(phase: .moved, points: [CGPoint(x: 0.5, y: 0.01)]))
        do {
            try await session.touch(TouchEvent(phase: .cancelled, points: [CGPoint(x: 0.5, y: 0.5)]))
            XCTFail("cancelled should not be accepted")
        } catch EngineError.capabilityUnavailable {
        }
    }

    func testAcceptsTwoContactsAndRefusesThree() async throws {
        try IntegrationGate.requireEnabled()
        let session = try makeAdapter().openInput(try bootedDevice().udid)
        defer { session.close() }

        let pair = [CGPoint(x: 0.4, y: 0.02), CGPoint(x: 0.6, y: 0.02)]
        try await session.touch(TouchEvent(phase: .began, points: pair))
        try await session.touch(TouchEvent(phase: .ended, points: pair))

        do {
            try await session.touch(TouchEvent(
                phase: .began,
                points: pair + [CGPoint(x: 0.5, y: 0.5)]
            ))
            XCTFail("three contacts should not be accepted")
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

extension InputSessionTests {
    /// Cross checks the table against the simulator's own naming, so a wrong usage shows up as a
    /// mismatch rather than as text that silently types the wrong character.
    func testUsagesMatchTheSimulatorsOwnKeyNames() throws {
        try IntegrationGate.requireEnabled()

        let install = try XcodeLocator.locate()
        let simulatorKit = try FrameworkLoader.load(.simulatorKit, from: install)
        guard let symbol = simulatorKit.symbol(named: "IndigoHIDStringForKeyUsageCode") else {
            throw XCTSkip("IndigoHIDStringForKeyUsageCode is not exported on this Xcode")
        }
        typealias NameFunction = @convention(c) (Int32) -> Unmanaged<CFString>?
        let name = unsafeBitCast(symbol, to: NameFunction.self)

        let expected: [UInt32: String] = [0x04: "A", 0x05: "B", 0x1D: "Z", 0x2C: "space"]
        for (usage, text) in expected {
            let reported = name(Int32(usage))?.takeUnretainedValue() as String?
            XCTAssertEqual(reported, text, "usage \(usage)")
        }
    }

    func testSendingAKeyDoesNotError() async throws {
        try IntegrationGate.requireEnabled()
        let session = try makeAdapter().openInput(try bootedDevice().udid)
        defer { session.close() }
        // Escape is harmless wherever the device happens to be.
        try await session.key(KeyEvent(phase: .down, usage: 0x29))
        try await session.key(KeyEvent(phase: .up, usage: 0x29))
    }
}
