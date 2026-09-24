import AppKit
import XCTest
import OpenDeviceHubEngine

final class PasteboardBridgeTests: XCTestCase {
    private func makeAdapter() throws -> any SimulatorAdapter {
        try AdapterFactory.make(for: XcodeLocator.locate())
    }

    private func bootedDevice() throws -> DeviceInfo {
        guard let booted = try makeAdapter().devices().first(where: { $0.state == .booted }) else {
            throw XCTSkip("no booted simulator, boot one to run this test")
        }
        return booted
    }

    /// The automatic direction only moves while the run loop turns, so a test that slept instead
    /// would report a working feature as broken.
    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func setMacClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func testOpensAPasteboardConnectionOnABootedDevice() throws {
        try IntegrationGate.requireEnabled()
        let session = try makeAdapter().openPasteboard(bootedDevice().udid)
        XCTAssertFalse(session.isAutomatic)
    }

    func testRefusesAShutdownDevice() throws {
        try IntegrationGate.requireEnabled()
        let adapter = try makeAdapter()
        guard let shutdown = try adapter.devices().first(where: { $0.state == .shutdown }) else {
            throw XCTSkip("every simulator is booted")
        }
        XCTAssertThrowsError(try adapter.openPasteboard(shutdown.udid)) { error in
            guard case EngineError.deviceNotBooted = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    /// Read back with `simctl pbpaste` rather than by trusting the call that wrote it.
    func testSendCarriesTheMacClipboardToTheDevice() throws {
        try IntegrationGate.requireEnabled()
        let udid = try bootedDevice().udid
        let session = try makeAdapter().openPasteboard(udid)

        let sent = "odhub-send-\(UUID().uuidString)"
        setMacClipboard(sent)
        session.send()
        spin(1)

        XCTAssertEqual(try simctlPaste(udid: udid), sent)
    }

    func testGetCarriesTheDeviceClipboardToTheMac() throws {
        try IntegrationGate.requireEnabled()
        let udid = try bootedDevice().udid
        let session = try makeAdapter().openPasteboard(udid)

        let copied = "odhub-get-\(UUID().uuidString)"
        setMacClipboard("something else")
        try simctlCopy(copied, udid: udid)
        session.get()
        spin(1)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), copied)
    }

    func testAutomaticSyncCarriesLaterMacCopies() throws {
        try IntegrationGate.requireEnabled()
        let udid = try bootedDevice().udid
        let session = try makeAdapter().openPasteboard(udid)
        session.setAutomatic(true)
        XCTAssertTrue(session.isAutomatic)
        defer { session.setAutomatic(false) }
        spin(1)

        // Copied after the syncing was turned on and never pushed by hand, so arriving proves the
        // sync is running rather than that a one off push happened.
        let copied = "odhub-auto-\(UUID().uuidString)"
        setMacClipboard(copied)
        spin(3)

        XCTAssertEqual(try simctlPaste(udid: udid), copied)
    }

    func testTurningTheSyncOffStopsIt() throws {
        try IntegrationGate.requireEnabled()
        let udid = try bootedDevice().udid
        let session = try makeAdapter().openPasteboard(udid)
        session.setAutomatic(true)
        spin(1)
        session.setAutomatic(false)
        XCTAssertFalse(session.isAutomatic)

        let ignored = "odhub-off-\(UUID().uuidString)"
        setMacClipboard(ignored)
        spin(3)

        XCTAssertNotEqual(try simctlPaste(udid: udid), ignored)
    }

    func testReconcileBringsTheDeviceClipboardBack() throws {
        try IntegrationGate.requireEnabled()
        let udid = try bootedDevice().udid
        let session = try makeAdapter().openPasteboard(udid)
        session.send()

        let onTheDevice = "odhub-back-\(UUID().uuidString)"
        try simctlCopy(onTheDevice, udid: udid)
        session.reconcile()
        spin(1)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), onTheDevice)
    }

    /// The guard that stops a pull from eating a copy the user made on the Mac a moment earlier.
    func testReconcileKeepsANewerMacCopy() throws {
        try IntegrationGate.requireEnabled()
        let udid = try bootedDevice().udid
        let session = try makeAdapter().openPasteboard(udid)

        try simctlCopy("older-on-the-device", udid: udid)
        let newerOnTheMac = "odhub-newer-\(UUID().uuidString)"
        setMacClipboard(newerOnTheMac)
        session.reconcile()
        spin(1)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), newerOnTheMac)
        XCTAssertEqual(try simctlPaste(udid: udid), newerOnTheMac)
    }

    private func simctlPaste(udid: String) throws -> String {
        try simctl(["pbpaste", udid])
    }

    private func simctlCopy(_ value: String, udid: String) throws {
        _ = try simctl(["pbcopy", udid], input: value)
    }

    @discardableResult
    private func simctl(_ arguments: [String], input: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        process.environment = ProcessInfo.processInfo.environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        if let input {
            let pipe = Pipe()
            process.standardInput = pipe
            try process.run()
            pipe.fileHandleForWriting.write(Data(input.utf8))
            pipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
