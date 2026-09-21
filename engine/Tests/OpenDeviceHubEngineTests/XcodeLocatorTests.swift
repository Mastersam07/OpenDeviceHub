import XCTest
@testable import OpenDeviceHubEngine

final class XcodeVersionParsingTests: XCTestCase {
    func testParsesMajorMinor() {
        let version = XcodeVersion(parsing: "26.5")
        XCTAssertEqual(version, XcodeVersion(major: 26, minor: 5))
        XCTAssertEqual(version?.description, "26.5")
    }

    func testParsesMajorOnly() {
        XCTAssertEqual(XcodeVersion(parsing: "27"), XcodeVersion(major: 27, minor: 0))
    }

    func testParsesMajorMinorPatch() {
        let version = XcodeVersion(parsing: "27.0.1")
        XCTAssertEqual(version, XcodeVersion(major: 27, minor: 0, patch: 1))
        XCTAssertEqual(version?.description, "27.0.1")
    }

    func testIgnoresSurroundingWhitespace() {
        XCTAssertEqual(XcodeVersion(parsing: "  26.5  "), XcodeVersion(major: 26, minor: 5))
    }

    func testRejectsMalformedInput() {
        XCTAssertNil(XcodeVersion(parsing: ""))
        XCTAssertNil(XcodeVersion(parsing: "beta"))
        XCTAssertNil(XcodeVersion(parsing: "26.5.1.2"))
        XCTAssertNil(XcodeVersion(parsing: "26.x"))
        XCTAssertNil(XcodeVersion(parsing: "-1.0"))
        XCTAssertNil(XcodeVersion(parsing: "26."))
    }
}

final class XcodeVersionOutputTests: XCTestCase {
    func testParsesRealOutput() throws {
        let output = """
        Xcode 26.5
        Build version 17F42
        """
        let parsed = try XcodeLocator.parseVersionOutput(output)
        XCTAssertEqual(parsed.version, XcodeVersion(major: 26, minor: 5))
        XCTAssertEqual(parsed.build, "17F42")
    }

    func testToleratesExtraLinesAndBlankLines() throws {
        let output = """

        Xcode 27.0
        Build version 19A100

        """
        let parsed = try XcodeLocator.parseVersionOutput(output)
        XCTAssertEqual(parsed.version, XcodeVersion(major: 27, minor: 0))
        XCTAssertEqual(parsed.build, "19A100")
    }

    func testThrowsWhenBuildIsMissing() {
        XCTAssertThrowsError(try XcodeLocator.parseVersionOutput("Xcode 26.5"))
    }

    func testThrowsWhenVersionIsMissing() {
        XCTAssertThrowsError(try XcodeLocator.parseVersionOutput("Build version 17F42"))
    }

    func testThrowsOnEmptyOutput() {
        XCTAssertThrowsError(try XcodeLocator.parseVersionOutput(""))
    }
}

final class XcodeAppRootTests: XCTestCase {
    func testDerivesAppRootFromDeveloperDirectory() {
        let developerDir = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer")
        XCTAssertEqual(
            XcodeLocator.appRoot(forDeveloperDir: developerDir).path,
            "/Applications/Xcode.app"
        )
    }

    func testDerivesAppRootForASideBySideInstall() {
        let developerDir = URL(fileURLWithPath: "/Applications/Xcode-27.app/Contents/Developer")
        XCTAssertEqual(
            XcodeLocator.appRoot(forDeveloperDir: developerDir).path,
            "/Applications/Xcode-27.app"
        )
    }

    func testReturnsInputWhenThereIsNoAppBundle() {
        let developerDir = URL(fileURLWithPath: "/Library/Developer/CommandLineTools")
        XCTAssertEqual(
            XcodeLocator.appRoot(forDeveloperDir: developerDir).path,
            "/Library/Developer/CommandLineTools"
        )
    }
}
