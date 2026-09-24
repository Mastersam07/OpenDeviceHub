import XCTest
@testable import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

final class ViewerSettingsTests: XCTestCase {
    private func settings() -> ViewerSettings {
        ViewerSettings(storage: InMemoryPreferences(), prefix: "test.")
    }

    func testTheDefaultsAreWhatTheAppAlreadyDid() {
        let settings = settings()
        XCTAssertTrue(settings.shutsDownOnWindowClose)
        XCTAssertTrue(settings.bootsMostRecentOnStart)
        XCTAssertNil(settings.captureDirectory)
    }

    func testAFlagSurvivesBeingTurnedOff() {
        let settings = settings()
        settings.shutsDownOnWindowClose = false
        XCTAssertFalse(settings.shutsDownOnWindowClose)
        settings.shutsDownOnWindowClose = true
        XCTAssertTrue(settings.shutsDownOnWindowClose)
    }

    /// Off has to be stored, not inferred from the absence of a value, or turning something off
    /// would be indistinguishable from never having touched it.
    func testOffIsStoredRatherThanLeftBlank() {
        let storage = InMemoryPreferences()
        let settings = ViewerSettings(storage: storage, prefix: "test.")
        settings.bootsMostRecentOnStart = false
        XCTAssertEqual(storage.text(forKey: "test.bootMostRecentOnStart"), "false")
        XCTAssertFalse(ViewerSettings(storage: storage, prefix: "test.").bootsMostRecentOnStart)
    }

    func testTheTwoFlagsDoNotShareAKey() {
        let settings = settings()
        settings.shutsDownOnWindowClose = false
        XCTAssertTrue(settings.bootsMostRecentOnStart)
    }

    func testTheCaptureDirectoryRoundTrips() {
        let settings = settings()
        let chosen = URL(fileURLWithPath: "/Users/someone/My Captures", isDirectory: true)
        settings.captureDirectory = chosen
        XCTAssertEqual(settings.captureDirectory, chosen)
        settings.captureDirectory = nil
        XCTAssertNil(settings.captureDirectory)
    }

    /// The stored string is what a person sees if they ever look in the plist, so it keeps the shape
    /// they typed rather than the trailing slash a directory URL carries.
    func testTheStoredPathHasNoTrailingSlash() {
        let storage = InMemoryPreferences()
        let settings = ViewerSettings(storage: storage, prefix: "test.")
        settings.captureDirectory = URL(fileURLWithPath: "/Users/someone/My Captures", isDirectory: true)
        XCTAssertEqual(storage.text(forKey: "test.captureDirectory"), "/Users/someone/My Captures")
    }

    func testAnEmptyStoredPathReadsAsNoChoice() {
        let storage = InMemoryPreferences()
        storage.setText("", forKey: "test.captureDirectory")
        XCTAssertNil(ViewerSettings(storage: storage, prefix: "test.").captureDirectory)
    }
}

final class InMemoryPreferences: PreferenceStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func text(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func setText(_ text: String, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = text
    }

    func removeText(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}
