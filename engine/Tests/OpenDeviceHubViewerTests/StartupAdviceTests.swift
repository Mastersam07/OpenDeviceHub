import XCTest
@testable import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

final class StartupAdviceTests: XCTestCase {
    func testMissingXcodeOffersToInstallItAndNamesWhereItLooked() {
        let advice = StartupAdvice.forStartupFailure(
            EngineError.xcodeNotFound(searched: ["$DEVELOPER_DIR", "xcode-select -p"])
        )
        XCTAssertTrue(advice.offersXcode)
        XCTAssertTrue(advice.detail.contains("xcode-select -p"))
        XCTAssertFalse(advice.title.isEmpty)
    }

    func testAnXcodeTooOldOffersANewerOne() {
        let advice = StartupAdvice.forStartupFailure(
            EngineError.unsupportedXcode(version: "15.4", supported: "26 and 27", note: "")
        )
        XCTAssertTrue(advice.offersXcode)
        XCTAssertTrue(advice.detail.contains("26 and 27"))
    }

    func testAMissingFrameworkSaysToOpenXcodeRatherThanInstallIt() {
        let advice = StartupAdvice.forStartupFailure(
            EngineError.frameworkNotFound(name: "CoreSimulator", searched: ["/nope"])
        )
        XCTAssertFalse(advice.offersXcode)
        XCTAssertTrue(advice.detail.contains("CoreSimulator"))
        XCTAssertTrue(advice.detail.contains("/nope"))
    }

    func testAMissingSymbolNamesTheFramework() {
        let advice = StartupAdvice.forStartupFailure(
            EngineError.symbolNotFound(name: "SimDeviceLegacyHIDClient", framework: "SimulatorKit")
        )
        XCTAssertFalse(advice.offersXcode)
        XCTAssertTrue(advice.detail.contains("SimDeviceLegacyHIDClient"))
        XCTAssertTrue(advice.detail.contains("SimulatorKit"))
    }

    func testAnythingElseStillSaysSomethingUseful() {
        struct Odd: Error, LocalizedError {
            var errorDescription: String? { "the disk fell over" }
        }
        let advice = StartupAdvice.forStartupFailure(Odd())
        XCTAssertFalse(advice.offersXcode)
        XCTAssertEqual(advice.detail, "the disk fell over")
    }

    func testAVerifiedXcodeSaysNothing() {
        let notice = UnverifiedXcodeNotice(storage: InMemoryStorage(), key: "seen")
        XCTAssertNil(notice.pending(for: XcodeVersion(major: 27, minor: 0, patch: 0)))
    }

    func testAnUnverifiedXcodeIsMentionedOnceForThatMajor() {
        let notice = UnverifiedXcodeNotice(storage: InMemoryStorage(), key: "seen")
        let next = XcodeVersion(major: 28, minor: 0, patch: 0)
        XCTAssertNotNil(notice.pending(for: next))

        notice.recordShown(for: next)
        XCTAssertNil(notice.pending(for: next))
        XCTAssertNil(notice.pending(for: XcodeVersion(major: 28, minor: 3, patch: 0)))
        XCTAssertNotNil(notice.pending(for: XcodeVersion(major: 29, minor: 0, patch: 0)))
    }
}

private final class InMemoryStorage: PreferenceStorage, @unchecked Sendable {
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
