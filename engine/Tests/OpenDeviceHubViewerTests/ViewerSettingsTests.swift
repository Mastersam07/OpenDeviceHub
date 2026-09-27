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
        XCTAssertFalse(settings.savesScreenshotsToClipboard)
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

    func testSaveScreenshotsToClipboardPreferenceSurvivesBeingTurnedOn() {
        let settings = settings()
        settings.savesScreenshotsToClipboard = true
        XCTAssertTrue(settings.savesScreenshotsToClipboard)
    }

    func testBothFoldersStartAtTheSharedFolderOlderVersionsSaved() {
        let storage = InMemoryPreferences()
        let shared = URL(fileURLWithPath: "/Users/someone/Captures", isDirectory: true)
        ViewerSettings(storage: storage, prefix: "test.").captureDirectory = shared

        let settings = ViewerSettings(storage: storage, prefix: "test.")
        XCTAssertEqual(settings.screenshotDirectory, shared)
        XCTAssertEqual(settings.recordingDirectory, shared)
    }

    func testChoosingOneFolderLeavesTheOtherAlone() {
        let storage = InMemoryPreferences()
        let shared = URL(fileURLWithPath: "/Users/someone/Captures", isDirectory: true)
        let stills = URL(fileURLWithPath: "/Users/someone/Stills", isDirectory: true)
        let settings = ViewerSettings(storage: storage, prefix: "test.")
        settings.captureDirectory = shared

        settings.screenshotDirectory = stills

        XCTAssertEqual(settings.screenshotDirectory, stills)
        XCTAssertEqual(settings.recordingDirectory, shared)
    }

    func testUsingTheDesktopForOneFolderOverridesTheSharedOne() {
        let storage = InMemoryPreferences()
        let settings = ViewerSettings(storage: storage, prefix: "test.")
        settings.captureDirectory = URL(fileURLWithPath: "/Users/someone/Captures", isDirectory: true)

        settings.recordingDirectory = nil

        XCTAssertNil(ViewerSettings(storage: storage, prefix: "test.").recordingDirectory)
        XCTAssertNotNil(ViewerSettings(storage: storage, prefix: "test.").screenshotDirectory)
    }

    func testAFolderIsStoredWithoutATrailingSlash() {
        let storage = InMemoryPreferences()
        ViewerSettings(storage: storage, prefix: "test.").screenshotDirectory =
            URL(fileURLWithPath: "/Users/someone/Stills/", isDirectory: true)
        XCTAssertEqual(storage.text(forKey: "test.screenshotDirectory"), "/Users/someone/Stills")
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

    func testLocationFavoritesRoundTripInOrder() {
        let storage = InMemoryPreferences()
        let settings = ViewerSettings(storage: storage, prefix: "test.")
        let favorites = [
            LocationFavorite(name: "Cupertino", latitude: 37.3349, longitude: -122.0090),
            LocationFavorite(name: "London", latitude: 51.5072, longitude: -0.1276),
        ]

        settings.locationFavorites = favorites

        XCTAssertEqual(ViewerSettings(storage: storage, prefix: "test.").locationFavorites, favorites)
    }

    func testMissingOrMalformedLocationFavoritesReadAsEmpty() {
        let storage = InMemoryPreferences()
        let settings = ViewerSettings(storage: storage, prefix: "test.")
        XCTAssertTrue(settings.locationFavorites.isEmpty)

        storage.setText("not json", forKey: "test.locationFavorites")
        XCTAssertTrue(settings.locationFavorites.isEmpty)
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

    func keys(withPrefix prefix: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return values.keys.filter { $0.hasPrefix(prefix) }
    }
}
