import XCTest
@testable import OpenDeviceHubEngine

final class ScreenRecorderArgumentTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/capture.mov")

    func testArgumentsMatchTheDocumentedSyntax() {
        XCTAssertEqual(
            ScreenRecorder.arguments(udid: "ABC", url: url, codec: .h264, mask: .black),
            ["simctl", "io", "ABC", "recordVideo", "--codec=h264", "--mask=black", "--force", "/tmp/capture.mov"]
        )
    }

    func testTheCodecAndMaskAreCarriedThrough() {
        let arguments = ScreenRecorder.arguments(udid: "ABC", url: url, codec: .hevc, mask: .ignored)
        XCTAssertTrue(arguments.contains("--codec=hevc"))
        XCTAssertTrue(arguments.contains("--mask=ignored"))
    }

    func testTheFileIsTheLastArgument() {
        let arguments = ScreenRecorder.arguments(udid: "ABC", url: url, codec: .h264, mask: .black)
        XCTAssertEqual(arguments.last, "/tmp/capture.mov")
    }

    func testAPathWithSpacesIsPassedWhole() {
        let spaced = URL(fileURLWithPath: "/tmp/iPhone 17 Pro capture.mov")
        let arguments = ScreenRecorder.arguments(udid: "ABC", url: spaced, codec: .h264, mask: .black)
        XCTAssertEqual(arguments.last, "/tmp/iPhone 17 Pro capture.mov")
    }
}
