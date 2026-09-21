import XCTest
@testable import OpenDeviceHubEngine

final class SimctlArgumentTests: XCTestCase {
    func testListDevicesAsksForJSON() {
        XCTAssertEqual(SimctlService.listDevicesArguments(), ["simctl", "list", "devices", "-j"])
    }

    func testListRuntimesAsksForJSON() {
        XCTAssertEqual(SimctlService.listRuntimesArguments(), ["simctl", "list", "runtimes", "-j"])
    }
}

final class SimctlParsingTests: XCTestCase {
    private let devicesJSON = Data("""
    {
      "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
          {
            "lastBootedAt": "2026-05-07T14:29:31Z",
            "dataPath": "/tmp/data",
            "dataPathSize": 326803456,
            "logPath": "/tmp/log",
            "udid": "5AD6D15B-D72B-481A-A0E9-3ED89C0820C6",
            "isAvailable": true,
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
            "state": "Shutdown",
            "name": "iPhone 17 Pro"
          }
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [
          {
            "dataPath": "/tmp/data2",
            "logPath": "/tmp/log2",
            "udid": "11111111-2222-3333-4444-555555555555",
            "isAvailable": false,
            "availabilityError": "runtime profile not found",
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-15",
            "state": "Shutdown",
            "name": "iPhone 15"
          }
        ]
      }
    }
    """.utf8)

    func testParsesDevicesGroupedByRuntime() throws {
        let parsed = try SimctlModels.parseDevices(devicesJSON)
        XCTAssertEqual(parsed.count, 2)
        let modern = try XCTUnwrap(parsed["com.apple.CoreSimulator.SimRuntime.iOS-26-5"])
        XCTAssertEqual(modern.first?.name, "iPhone 17 Pro")
        XCTAssertEqual(modern.first?.udid, "5AD6D15B-D72B-481A-A0E9-3ED89C0820C6")
        XCTAssertEqual(modern.first?.isAvailable, true)
        XCTAssertNil(modern.first?.availabilityError)
    }

    func testParsesUnavailableDevicesAndTheirReason() throws {
        let parsed = try SimctlModels.parseDevices(devicesJSON)
        let legacy = try XCTUnwrap(parsed["com.apple.CoreSimulator.SimRuntime.iOS-17-5"])
        XCTAssertEqual(legacy.first?.isAvailable, false)
        XCTAssertEqual(legacy.first?.availabilityError, "runtime profile not found")
    }

    func testParsesRuntimes() throws {
        let json = Data("""
        {"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        "name":"iOS 26.5","version":"26.5","buildversion":"23F77","isAvailable":true}]}
        """.utf8)
        let runtimes = try SimctlModels.parseRuntimes(json)
        XCTAssertEqual(runtimes.count, 1)
        XCTAssertEqual(runtimes[0].name, "iOS 26.5")
        XCTAssertEqual(runtimes[0].buildversion, "23F77")
    }

    func testRejectsMalformedJSON() {
        XCTAssertThrowsError(try SimctlModels.parseDevices(Data("not json".utf8)))
    }
}

final class RuntimeNamingTests: XCTestCase {
    func testPrefersTheInstalledRuntimeName() {
        let name = SimctlModels.runtimeName(
            forIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            runtimes: ["com.apple.CoreSimulator.SimRuntime.iOS-26-5": "iOS 26.5"]
        )
        XCTAssertEqual(name, "iOS 26.5")
    }

    func testDerivesANameWhenTheRuntimeIsNotInstalled() {
        let name = SimctlModels.runtimeName(
            forIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-5",
            runtimes: [:]
        )
        XCTAssertEqual(name, "iOS 17.5")
    }

    func testReadableNameHandlesPlatformsAndPatchVersions() {
        XCTAssertEqual(RuntimeIdentifier.readableName(for: "com.apple.CoreSimulator.SimRuntime.iOS-26-5"), "iOS 26.5")
        XCTAssertEqual(RuntimeIdentifier.readableName(for: "com.apple.CoreSimulator.SimRuntime.watchOS-11-0"), "watchOS 11.0")
        XCTAssertEqual(RuntimeIdentifier.readableName(for: "com.apple.CoreSimulator.SimRuntime.xrOS-2-1-1"), "xrOS 2.1.1")
    }

    func testReadableNameLeavesUnexpectedShapesAlone() {
        XCTAssertEqual(RuntimeIdentifier.readableName(for: "com.apple.CoreSimulator.SimRuntime.iOS"), "iOS")
        XCTAssertEqual(RuntimeIdentifier.readableName(for: "something-else-entirely"), "something-else-entirely")
        XCTAssertEqual(RuntimeIdentifier.readableName(for: ""), "")
    }
}

final class SimctlPasteboardArgumentTests: XCTestCase {
    func testPasteboardCopyArguments() {
        XCTAssertEqual(
            SimctlService.pasteboardCopyArguments(udid: "ABC"),
            ["simctl", "pbcopy", "ABC"]
        )
    }

    func testPasteboardPasteArguments() {
        XCTAssertEqual(
            SimctlService.pasteboardPasteArguments(udid: "ABC"),
            ["simctl", "pbpaste", "ABC"]
        )
    }

    func testBootArgumentsMatchTheDocumentedSyntax() {
        XCTAssertEqual(SimctlService.bootArguments(udid: "ABC"), ["simctl", "boot", "ABC"])
        XCTAssertEqual(SimctlService.shutdownArguments(udid: "ABC"), ["simctl", "shutdown", "ABC"])
        XCTAssertEqual(SimctlService.bootStatusArguments(udid: "ABC"), ["simctl", "bootstatus", "ABC", "-b"])
    }
}

final class DebugPathTests: XCTestCase {
    func testAppContainerArguments() {
        XCTAssertEqual(
            SimctlService.appContainerArguments(udid: "ABC", bundleID: "com.example.app", kind: .data),
            ["simctl", "get_app_container", "ABC", "com.example.app", "data"]
        )
    }

    func testEveryContainerKindIsPassedThrough() {
        for kind in SimctlService.ContainerKind.allCases {
            let arguments = SimctlService.appContainerArguments(udid: "A", bundleID: "b", kind: kind)
            XCTAssertEqual(arguments.last, kind.rawValue)
        }
    }

    func testTheSystemLogDirectoryIsUnderTheUsersLogs() {
        let url = SimctlService.systemLogDirectory(udid: "ABC")
        XCTAssertTrue(url.path.hasSuffix("Library/Logs/CoreSimulator/ABC"))
    }

    func testTheDeviceDataDirectoryPointsAtTheDevice() {
        let url = SimctlService.deviceDataDirectory(udid: "ABC")
        XCTAssertTrue(url.path.hasSuffix("CoreSimulator/Devices/ABC/data"))
    }
}
