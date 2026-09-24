import XCTest
@testable import OpenDeviceHubViewer

/// Real files in a temporary directory, because the whole point of this type is what happens on
/// disk, and a mocked file system would test the mock.
final class PendingCaptureTests: XCTestCase {
    private var root: URL!
    private let filer = CaptureFiler()

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "odh-capture-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func pending(named name: String = "shot.png") throws -> PendingCapture {
        let temporary = root.appending(path: "tmp-\(name)")
        try Data("image".utf8).write(to: temporary)
        return PendingCapture(
            temporary: temporary,
            destination: root.appending(path: "Captures")
        )
    }

    func testSettlingMovesItIntoTheCaptureFolder() throws {
        let capture = try pending()
        let landed = try filer.settle(capture)
        XCTAssertTrue(FileManager.default.fileExists(atPath: landed.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.temporary.path(percentEncoded: false)))
        XCTAssertEqual(landed.deletingLastPathComponent().lastPathComponent, "Captures")
    }

    func testSettlingCreatesTheFolderIfItIsNotThere() throws {
        let capture = try pending()
        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.destination.path(percentEncoded: false)))
        _ = try filer.settle(capture)
        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.destination.path(percentEncoded: false)))
    }

    /// Two captures in the same second must not become one file.
    func testASecondCaptureWithTheSameNameDoesNotOverwriteTheFirst() throws {
        let first = try pending()
        let firstURL = try filer.settle(first)
        try Data("first".utf8).write(to: firstURL)

        let second = try pending()
        let secondURL = try filer.settle(second)

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), "first")
        XCTAssertTrue(secondURL.lastPathComponent.contains("2"))
    }

    func testDiscardingLeavesNothingBehind() throws {
        let capture = try pending()
        filer.discard(capture)
        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.temporary.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.settled.path(percentEncoded: false)))
    }

    func testSavingSomewhereElseReplacesWhatIsThere() throws {
        let capture = try pending()
        let chosen = root.appending(path: "chosen.png")
        try Data("old".utf8).write(to: chosen)
        let landed = try filer.save(capture, to: chosen)
        XCTAssertEqual(landed, chosen)
        XCTAssertEqual(try String(contentsOf: chosen, encoding: .utf8), "image")
    }

    func testNothingIsWrittenToTheCaptureFolderUntilItSettles() throws {
        let capture = try pending()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: capture.settled.path(percentEncoded: false)),
            "the capture folder must stay empty while the preview is up"
        )
    }
}
