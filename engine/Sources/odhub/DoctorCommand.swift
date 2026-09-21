import ArgumentParser
import Foundation
import OpenDeviceHubEngine

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Report the active Xcode, the simulator frameworks and what resolves from them."
    )

    func run() throws {
        let install = try XcodeLocator.locate()

        print("Xcode")
        print("  version:       \(install.version) (\(install.build))")
        print("  developer dir: \(display(install.developerDir))")
        print("  app root:      \(display(install.appRoot))")

        var loadFailed = false
        for framework in PrivateFramework.allCases {
            print("")
            print(framework.rawValue)
            do {
                let loaded = try FrameworkLoader.load(framework, from: install)
                print("  loaded: \(loaded.path)")
                report(PrivateSymbolProbe.probeAll(in: framework))
            } catch let error as EngineError {
                loadFailed = true
                print("  not loaded: \(error.localizedDescription)")
            }
        }

        if loadFailed {
            throw ExitCode.failure
        }
    }

    private func display(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func report(_ results: [ClassProbeResult]) {
        let width = results.map(\.requested.count).max() ?? 0
        for result in results {
            guard let resolved = result.resolved else {
                print("  missing \(result.requested)")
                continue
            }
            if resolved == result.requested {
                print("  ok      \(result.requested)")
            } else {
                let name = result.requested.padding(toLength: width, withPad: " ", startingAt: 0)
                print("  ok      \(name) (as \(resolved))")
            }
        }
    }
}
