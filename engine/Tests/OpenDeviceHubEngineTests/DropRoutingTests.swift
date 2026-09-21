import XCTest
@testable import OpenDeviceHubEngine

private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

final class DropRoutingTests: XCTestCase {
    func testAnAppBundleIsInstalled() {
        XCTAssertEqual(DropRouting.actions(for: [url("/tmp/Thing.app")]), [.installApp(url("/tmp/Thing.app"))])
    }

    func testCertificatesGoToTheRootStore() {
        for ext in ["cer", "pem", "der", "crt"] {
            let file = url("/tmp/ca.\(ext)")
            XCTAssertEqual(DropRouting.actions(for: [file]), [.addRootCertificate(file)], ext)
        }
    }

    func testMediaIsGroupedIntoOneAction() {
        let files = [url("/tmp/a.png"), url("/tmp/b.mov")]
        XCTAssertEqual(DropRouting.actions(for: files), [.addMedia(files)])
    }

    func testMediaAndAnAppTogetherProduceBoth() {
        let actions = DropRouting.actions(for: [url("/tmp/a.png"), url("/tmp/Thing.app")])
        XCTAssertEqual(actions.count, 2)
        XCTAssertTrue(actions.contains(.addMedia([url("/tmp/a.png")])))
        XCTAssertTrue(actions.contains(.installApp(url("/tmp/Thing.app"))))
    }

    func testExtensionsAreMatchedRegardlessOfCase() {
        XCTAssertEqual(DropRouting.actions(for: [url("/tmp/A.PNG")]), [.addMedia([url("/tmp/A.PNG")])])
        XCTAssertEqual(DropRouting.actions(for: [url("/tmp/Thing.APP")]), [.installApp(url("/tmp/Thing.APP"))])
    }

    func testAnUnknownFileIsReportedRatherThanIgnored() {
        XCTAssertEqual(DropRouting.actions(for: [url("/tmp/notes.txt")]), [.unsupported(url("/tmp/notes.txt"))])
    }

    func testNothingDroppedProducesNoActions() {
        XCTAssertTrue(DropRouting.actions(for: []).isEmpty)
    }

    func testOnlyCertificatesNeedConfirmation() {
        XCTAssertTrue(DropAction.addRootCertificate(url("/tmp/ca.pem")).needsConfirmation)
        XCTAssertFalse(DropAction.installApp(url("/tmp/a.app")).needsConfirmation)
        XCTAssertFalse(DropAction.addMedia([url("/tmp/a.png")]).needsConfirmation)
        XCTAssertFalse(DropAction.openURL("https://example.com").needsConfirmation)
    }
}

final class DropArgumentTests: XCTestCase {
    func testTheArgumentsMatchTheDocumentedSyntax() {
        XCTAssertEqual(
            SimctlService.installArguments(udid: "ABC", app: url("/tmp/Thing.app")),
            ["simctl", "install", "ABC", "/tmp/Thing.app"]
        )
        XCTAssertEqual(
            SimctlService.addMediaArguments(udid: "ABC", files: [url("/tmp/a.png"), url("/tmp/b.mov")]),
            ["simctl", "addmedia", "ABC", "/tmp/a.png", "/tmp/b.mov"]
        )
        XCTAssertEqual(
            SimctlService.addRootCertificateArguments(udid: "ABC", certificate: url("/tmp/ca.pem")),
            ["simctl", "keychain", "ABC", "add-root-cert", "/tmp/ca.pem"]
        )
        XCTAssertEqual(
            SimctlService.openURLArguments(udid: "ABC", url: "https://example.com"),
            ["simctl", "openurl", "ABC", "https://example.com"]
        )
    }
}
