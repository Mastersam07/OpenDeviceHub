import XCTest
@testable import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

final class CommandLineToolTests: XCTestCase {
    private let binary = "/Applications/OpenDeviceHub.app/Contents/MacOS/odhub"
    private let candidates = CommandLineTool.candidateDirectories(home: "/Users/someone")

    func testPrefersAFolderThePersonOwnsOverOneNeedingAPassword() {
        let location = CommandLineTool.chooseLocation(
            candidates: candidates,
            onPath: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"],
            isWritable: { $0 == "/opt/homebrew/bin" }
        )
        XCTAssertEqual(location.directory, "/opt/homebrew/bin")
        XCTAssertFalse(location.needsAuthorization)
    }

    func testAWritableUsrLocalBinNeedsNoPassword() {
        let location = CommandLineTool.chooseLocation(
            candidates: candidates,
            onPath: ["/usr/bin"],
            isWritable: { $0 == "/usr/local/bin" }
        )
        XCTAssertEqual(location.directory, "/usr/local/bin")
        XCTAssertFalse(location.needsAuthorization)
    }

    func testAWritableFolderThatIsNotOnThePathIsNoUse() {
        let location = CommandLineTool.chooseLocation(
            candidates: candidates,
            onPath: ["/usr/bin"],
            isWritable: { $0 == "/Users/someone/bin" }
        )
        XCTAssertEqual(location.directory, "/usr/local/bin")
        XCTAssertTrue(location.needsAuthorization)
    }

    func testWithNothingWritableItFallsBackToAskingForAPassword() {
        let location = CommandLineTool.chooseLocation(
            candidates: candidates,
            onPath: ["/opt/homebrew/bin", "/usr/local/bin"],
            isWritable: { _ in false }
        )
        XCTAssertEqual(location.directory, "/usr/local/bin")
        XCTAssertTrue(location.needsAuthorization)
    }

    func testNoLinkAnywhereMeansNotInstalled() {
        let state = CommandLineTool.state(
            links: candidates.map { ("\($0)/odhub", nil) },
            expecting: binary
        )
        XCTAssertEqual(state, .missing)
    }

    func testALinkToOurBinaryIsFoundWhicheverFolderItIsIn() {
        let state = CommandLineTool.state(
            links: [
                ("/opt/homebrew/bin/odhub", nil),
                ("/usr/local/bin/odhub", binary),
            ],
            expecting: binary
        )
        XCTAssertEqual(state, .installed(at: "/usr/local/bin/odhub"))
    }

    func testOurOwnLinkWinsOverSomeoneElsesWithTheSameName() {
        let state = CommandLineTool.state(
            links: [
                ("/opt/homebrew/bin/odhub", "/somewhere/else/odhub"),
                ("/usr/local/bin/odhub", binary),
            ],
            expecting: binary
        )
        XCTAssertEqual(state, .installed(at: "/usr/local/bin/odhub"))
    }

    func testALinkSomewhereElseIsReportedWithBothPaths() {
        let stale = "/Users/someone/old/OpenDeviceHub.app/Contents/MacOS/odhub"
        let state = CommandLineTool.state(
            links: [("/opt/homebrew/bin/odhub", stale)],
            expecting: binary
        )
        XCTAssertEqual(state, .pointsElsewhere(link: "/opt/homebrew/bin/odhub", destination: stale))
    }

    func testPathEntriesIgnoreEmptySegments() {
        XCTAssertEqual(
            CommandLineTool.pathEntries("/usr/bin::/bin:"),
            ["/usr/bin", "/bin"]
        )
    }

    /// Asks a real shell what the quoting produces, because the only thing that matters is what `sh`
    /// makes of it, and a path with a quote in it is exactly where hand written escaping goes wrong.
    func testAwkwardPathsSurviveARealShellIntact() throws {
        for path in [
            "/Users/someone/My Apps/odhub",
            "/Users/someone/it's mine/odhub",
            "/Users/someone/a \"quoted\" name/odhub",
            "/Users/someone/back\\slash/odhub",
            "/Users/someone/$(whoami)/odhub",
            "/Users/someone/semi;colon && true/odhub",
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "printf %s \(CommandLineTool.shellQuoted(path))"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(String(data: data, encoding: .utf8), path, "quoting mangled \(path)")
        }
    }

    func testTheAppleScriptStringEscapesQuotesAndBackslashes() {
        let quoted = CommandLineTool.appleScriptQuoted("ln -sf \"a\\b\" /usr/local/bin/odhub")
        XCTAssertEqual(quoted, "\"ln -sf \\\"a\\\\b\\\" /usr/local/bin/odhub\"")
    }

    func testTheAuthorizingScriptAsksForAdministratorPrivileges() {
        let script = CommandLineTool.authorizingScript("rm -f '/usr/local/bin/odhub'")
        XCTAssertEqual(
            script,
            "do shell script \"rm -f '/usr/local/bin/odhub'\" with administrator privileges"
        )
    }

    func testTheManualCommandIsTheOneAPersonWouldType() {
        XCTAssertEqual(
            CommandLineTool.manualCommand(binary: binary, link: "/usr/local/bin/odhub"),
            "sudo mkdir -p '/usr/local/bin' && sudo ln -sf '\(binary)' '/usr/local/bin/odhub'"
        )
    }
}
