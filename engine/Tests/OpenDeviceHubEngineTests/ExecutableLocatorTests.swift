import XCTest
@testable import OpenDeviceHubEngine

final class ExecutableLocatorTests: XCTestCase {
    func testFindsASiblingNextToTheRunningExecutable() {
        let running = URL(fileURLWithPath: "/tmp/build/debug/odhub")
        let sibling = ExecutableLocator.siblingURL(of: running, named: "odhub-viewer")
        XCTAssertEqual(sibling.path, "/tmp/build/debug/odhub-viewer")
    }

    func testSiblingLookupWorksInsideAnApplicationBundle() {
        let running = URL(fileURLWithPath: "/Applications/Thing.app/Contents/MacOS/odhub")
        let sibling = ExecutableLocator.siblingURL(of: running, named: "odhub-viewer")
        XCTAssertEqual(sibling.path, "/Applications/Thing.app/Contents/MacOS/odhub-viewer")
    }

    func testResolvesAnAbsoluteInvocation() {
        let url = ExecutableLocator.executableURL(
            fromArgument: "/usr/local/bin/odhub",
            currentDirectory: "/var/empty"
        )
        XCTAssertEqual(url?.path, "/usr/local/bin/odhub")
    }

    func testResolvesARelativeInvocationAgainstTheWorkingDirectory() {
        let url = ExecutableLocator.executableURL(
            fromArgument: "build/odhub",
            currentDirectory: "/var/empty"
        )
        XCTAssertEqual(url?.path, "/var/empty/build/odhub")
    }

    func testRejectsAMissingOrEmptyArgument() {
        XCTAssertNil(ExecutableLocator.executableURL(fromArgument: nil, currentDirectory: "/var/empty"))
        XCTAssertNil(ExecutableLocator.executableURL(fromArgument: "", currentDirectory: "/var/empty"))
    }

    func testLocatesTheViewerBesideTheCommand() {
        let running = URL(fileURLWithPath: "/var/empty/build/odhub")
        XCTAssertEqual(
            ExecutableLocator.siblingURL(of: running, named: Brand.viewerExecutableName).path,
            "/var/empty/build/odhub-viewer"
        )
    }

    func testTheViewerIsNamedSeparatelyFromTheCommand() {
        XCTAssertNotEqual(Brand.commandName, Brand.viewerExecutableName)
        XCTAssertTrue(Brand.viewerExecutableName.hasPrefix(Brand.commandName))
    }
}
