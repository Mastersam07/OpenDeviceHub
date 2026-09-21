import XCTest
@testable import OpenDeviceHubEngine

private func makeInstall(appPath: String = "/Applications/Xcode.app") -> XcodeInstall {
    let appRoot = URL(fileURLWithPath: appPath)
    return XcodeInstall(
        developerDir: appRoot.appending(path: "Contents/Developer"),
        appRoot: appRoot,
        version: XcodeVersion(major: 26, minor: 5),
        build: "17F42"
    )
}

final class FrameworkCandidatePathTests: XCTestCase {
    func testCoreSimulatorPrefersTheSystemWideLocation() {
        let paths = PrivateFramework.coreSimulator.candidatePaths(for: makeInstall())
        XCTAssertEqual(paths, [
            "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",
            "/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",
        ])
    }

    func testSimulatorKitPrefersSharedFrameworksThenTheDeveloperDirectory() {
        let paths = PrivateFramework.simulatorKit.candidatePaths(for: makeInstall())
        XCTAssertEqual(paths, [
            "/Applications/Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit",
            "/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit",
        ])
    }

    func testCandidatePathsFollowASideBySideInstall() {
        let paths = PrivateFramework.simulatorKit.candidatePaths(
            for: makeInstall(appPath: "/Applications/Xcode-27.app")
        )
        XCTAssertTrue(paths[0].hasPrefix("/Applications/Xcode-27.app/Contents/SharedFrameworks/"))
        XCTAssertTrue(paths[1].hasPrefix("/Applications/Xcode-27.app/Contents/Developer/"))
    }

    func testEveryFrameworkOffersAtLeastTwoCandidates() {
        for framework in PrivateFramework.allCases {
            XCTAssertGreaterThanOrEqual(framework.candidatePaths(for: makeInstall()).count, 2)
        }
    }
}

final class CoreSimDeviceIOPathTests: XCTestCase {
    func testProbesTheSystemWideSubFrameworkFirst() {
        let paths = PrivateFramework.coreSimDeviceIO.candidatePaths(for: makeInstall())
        XCTAssertEqual(paths, [
            "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Frameworks/CoreSimDeviceIO.framework/CoreSimDeviceIO",
            "/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/CoreSimulator.framework/Frameworks/CoreSimDeviceIO.framework/CoreSimDeviceIO",
        ])
    }

    func testIsCoveredByAllCases() {
        XCTAssertTrue(PrivateFramework.allCases.contains(.coreSimDeviceIO))
    }
}

final class PrivateSymbolInventoryTests: XCTestCase {
    func testEveryFrameworkDeclaresSymbolsToProbe() {
        for framework in PrivateFramework.allCases {
            XCTAssertFalse(PrivateSymbolProbe.symbols(for: framework).isEmpty, "\(framework)")
        }
    }

    func testCoreSimDeviceIOProbesTheDisplayProtocols() {
        let names = PrivateSymbolProbe.symbols(for: .coreSimDeviceIO)
            .filter { $0.0 == .protocolSymbol }
            .map(\.1)
        XCTAssertTrue(names.contains("SimDisplayRenderable"))
        XCTAssertTrue(names.contains("SimDisplayIOSurfaceRenderable"))
        XCTAssertTrue(names.contains("SimLegacyHIDDescriptor"))
    }

    func testNoSymbolIsDeclaredTwiceWithinAFramework() {
        for framework in PrivateFramework.allCases {
            let names = PrivateSymbolProbe.symbols(for: framework).map(\.1)
            XCTAssertEqual(Set(names).count, names.count, "\(framework)")
        }
    }
}

final class PrivateSymbolSpellingTests: XCTestCase {
    func testObjectiveCFrameworkTriesTheBareNameFirst() {
        XCTAssertEqual(
            PrivateSymbolProbe.candidateSpellings(for: "SimDevice", in: .coreSimulator),
            ["SimDevice", "CoreSimulator.SimDevice"]
        )
    }

    func testSwiftFrameworkFallsBackToAModuleQualifiedName() {
        XCTAssertEqual(
            PrivateSymbolProbe.candidateSpellings(for: "SimDeviceLegacyHIDClient", in: .simulatorKit),
            ["SimDeviceLegacyHIDClient", "SimulatorKit.SimDeviceLegacyHIDClient"]
        )
    }

    func testAnAlreadyQualifiedNameIsUsedAsIs() {
        XCTAssertEqual(
            PrivateSymbolProbe.candidateSpellings(for: "SimulatorKit.SimDeviceScreen", in: .simulatorKit),
            ["SimulatorKit.SimDeviceScreen"]
        )
    }
}
