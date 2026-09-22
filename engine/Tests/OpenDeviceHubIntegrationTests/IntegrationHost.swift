import Foundation
import XCTest

/// The test host app the integration tests look for. It is installed on demand rather than assumed,
/// so a test that needs a real app on the device cannot quietly skip because nobody ran a script
/// first.
enum IntegrationHost {
    static let bundleID = "io.opendevicehub.testhost"

    static func install(on udid: String) throws {
        let script = repositoryRoot
            .appending(path: "scripts")
            .appending(path: "integration-setup.sh")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path(percentEncoded: false), udid]
        let errors = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errors
        try process.run()
        let message = String(
            decoding: errors.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw XCTSkip("the test host could not be installed: \(message)")
        }
    }

    /// The tests run from a build directory, so the repository is found from this file's own path
    /// rather than from the working directory.
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
