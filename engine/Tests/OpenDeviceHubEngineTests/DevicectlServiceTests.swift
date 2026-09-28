import XCTest
@testable import OpenDeviceHubEngine

final class DevicectlServiceTests: XCTestCase {
    private func report(_ nonFlat: String, flat: String = "unknown") -> Data {
        Data("""
        {
          "info" : { "commandType" : "devicectl.device.orientation.get", "outcome" : "success" },
          "result" : {
            "deviceIdentifier" : "60944F68-2A87-4EE5-AED5-BC08BFADF42A",
            "deviceIsOrientationLocked" : false,
            "deviceOrientation" : "\(flat)",
            "deviceOrientationNonFlat" : "\(nonFlat)"
          }
        }
        """.utf8)
    }

    func testAsksForJSONOnStandardOutput() {
        XCTAssertEqual(DevicectlService.orientationArguments(udid: "ABC"), [
            "devicectl", "device", "orientation", "get", "--device", "ABC",
            "--timeout", "5", "--quiet", "--json-output", "-",
        ])
    }

    func testReadsEachOrientationTheWayThePictureTurns() {
        XCTAssertEqual(DevicectlService.parseOrientation(report("portrait")), .portrait)
        XCTAssertEqual(DevicectlService.parseOrientation(report("portraitUpsideDown")), .portraitUpsideDown)
        XCTAssertEqual(DevicectlService.parseOrientation(report("landscapeRight")), .landscapeLeft)
        XCTAssertEqual(DevicectlService.parseOrientation(report("landscapeLeft")), .landscapeRight)
    }

    func testALyingFlatDeviceKeepsTheWayItWasHeld() {
        XCTAssertEqual(DevicectlService.parseOrientation(report("landscapeRight", flat: "faceUp")), .landscapeLeft)
    }

    func testKeepsTheSecondAnswerSinceAFoldableRepeatsItsLastOne() {
        let answers = Answers([report("portrait"), report("landscapeRight")])
        let service = DevicectlService { _ in answers.next() }
        XCTAssertEqual(service.orientation(udid: "ABC", foldable: true), .landscapeLeft)
        XCTAssertEqual(answers.asked, 2)
    }

    func testAsksAnOrdinaryDeviceOnce() {
        let answers = Answers([report("landscapeRight"), report("portrait")])
        let service = DevicectlService { _ in answers.next() }
        XCTAssertEqual(service.orientation(udid: "ABC", foldable: false), .landscapeLeft)
        XCTAssertEqual(answers.asked, 1)
    }

    func testNoAnswerWhenDevicectlCannotSeeTheDevice() {
        let service = DevicectlService { _ in nil }
        XCTAssertNil(service.orientation(udid: "ABC", foldable: true))
        XCTAssertNil(service.orientation(udid: "ABC", foldable: false))
    }

    func testAnythingElseIsNoAnswer() {
        XCTAssertNil(DevicectlService.parseOrientation(report("unknown")))
        XCTAssertNil(DevicectlService.parseOrientation(Data("{\"info\":{\"outcome\":\"failed\"}}".utf8)))
        XCTAssertNil(DevicectlService.parseOrientation(Data("not json".utf8)))
    }
}

private final class Answers: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [String]
    private(set) var asked = 0

    init(_ answers: [Data]) {
        queue = answers.map { String(decoding: $0, as: UTF8.self) }
    }

    func next() -> String? {
        lock.lock()
        defer { lock.unlock() }
        asked += 1
        return queue.isEmpty ? nil : queue.removeFirst()
    }
}
