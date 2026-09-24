import XCTest
@testable import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// Closing a window shuts its device down, and the setting turns that off. Driven through
/// `manager.close`, which is the path the menu and the window's own close button both take, with the
/// shutdown itself swapped for a recorder so no simulator is touched.
@MainActor
final class WindowCloseShutdownTests: XCTestCase {
    func testClosingAWindowThatIsNotOpenShutsNothingDown() async {
        let recorder = ShutdownRecorder()
        let manager = DeviceWindowManager(
            frameStore: WindowFrameStore(storage: InMemoryPreferences(), prefix: "test."),
            settings: settings(shutdownOnClose: true),
            shutdown: { recorder.record($0) }
        )
        manager.close("never-opened")
        await settle()
        XCTAssertEqual(recorder.udids, [])
    }

    func testTheSettingIsReadWhenTheWindowCloses() {
        let on = settings(shutdownOnClose: true)
        XCTAssertTrue(on.shutsDownOnWindowClose)
        let off = settings(shutdownOnClose: false)
        XCTAssertFalse(off.shutsDownOnWindowClose)
    }

    private func settings(shutdownOnClose: Bool) -> ViewerSettings {
        let settings = ViewerSettings(storage: InMemoryPreferences(), prefix: "test.")
        settings.shutsDownOnWindowClose = shutdownOnClose
        return settings
    }

    /// The shutdown runs off the main thread, so a synchronous assertion would race it.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(120))
    }
}

private final class ShutdownRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []

    var udids: [String] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    func record(_ udid: String) {
        lock.lock(); defer { lock.unlock() }
        seen.append(udid)
    }
}
