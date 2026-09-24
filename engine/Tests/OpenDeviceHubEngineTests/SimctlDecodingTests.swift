import XCTest
@testable import OpenDeviceHubEngine

/// The JSON here is real `simctl` output, trimmed but not reshaped. Hand written models drift from
/// the tool they decode, and the failure is a runtime that silently supports nothing.
final class SimctlDecodingTests: XCTestCase {
    /// Captured from `simctl list runtimes -j` on Xcode 27. Note the extra keys: the model has to
    /// ignore what it does not want rather than fail on it.
    private let runtimesJSON = """
        {
          "runtimes": [
            {
              "isAvailable": true,
              "version": "27.1",
              "buildversion": "24A94401",
              "supportedDeviceTypes": [
                {
                  "bundlePath": "/Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPhone Duo.simdevicetype",
                  "name": "iPhone Duo",
                  "productFamily": "iPhone",
                  "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"
                }
              ],
              "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
              "name": "iOS 27.1"
            }
          ]
        }
        """

    private let deviceTypesJSON = """
        {
          "devicetypes": [
            {
              "productFamily": "iPhone",
              "bundlePath": "/Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPhone 17.simdevicetype",
              "maxRuntimeVersion": 4294967295,
              "name": "iPhone 17",
              "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
              "modelIdentifier": "iPhone18,1",
              "minRuntimeVersion": 1769472
            }
          ]
        }
        """

    func testRuntimeSupportKeepsTheDeviceTypesTheRuntimeCanRun() throws {
        let decoded = try JSONDecoder().decode(
            SimctlModels.RuntimeSupportList.self,
            from: Data(runtimesJSON.utf8)
        )
        XCTAssertEqual(decoded.runtimes.count, 1)
        let runtime = try XCTUnwrap(decoded.runtimes.first)
        XCTAssertEqual(runtime.name, "iOS 27.1")
        XCTAssertTrue(runtime.isAvailable)
        XCTAssertEqual(
            runtime.supportedDeviceTypes?.map(\.identifier),
            ["com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"]
        )
    }

    func testDeviceTypesDecodeDespiteTheKeysWeIgnore() throws {
        let decoded = try JSONDecoder().decode(
            SimctlModels.DeviceTypeList.self,
            from: Data(deviceTypesJSON.utf8)
        )
        XCTAssertEqual(decoded.devicetypes.map(\.name), ["iPhone 17"])
        XCTAssertEqual(
            decoded.devicetypes.map(\.identifier),
            ["com.apple.CoreSimulator.SimDeviceType.iPhone-17"]
        )
    }

    /// A runtime with no supported device types at all must decode rather than throw, because the
    /// key is absent in some simctl output.
    func testAMissingSupportedDeviceTypesKeyIsNotAFailure() throws {
        let json = """
            {"runtimes":[{"isAvailable":false,"version":"18.1","buildversion":"22B5","identifier":"x","name":"iOS 18.1"}]}
            """
        let decoded = try JSONDecoder().decode(
            SimctlModels.RuntimeSupportList.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(decoded.runtimes.first?.supportedDeviceTypes)
    }
}
