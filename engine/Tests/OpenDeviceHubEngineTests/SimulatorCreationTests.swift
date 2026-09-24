import XCTest
@testable import OpenDeviceHubEngine

/// The pairing is the part that fails late and confusingly: an unsupported combination is refused by
/// simctl with a message about the runtime, long after the person chose the device.
final class SimulatorCreationTests: XCTestCase {
    private func runtime(_ name: String, _ version: String, available: Bool = true) -> SimctlRuntime {
        SimctlRuntime(
            identifier: "com.apple.CoreSimulator.SimRuntime.\(name.replacingOccurrences(of: " ", with: "-"))",
            name: name,
            version: version,
            buildversion: "1",
            isAvailable: available
        )
    }

    private func type(_ name: String, _ identifier: String) -> SimctlDeviceType {
        SimctlDeviceType(identifier: identifier, name: name)
    }

    private let iPhone17 = SimctlDeviceType(
        identifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
        name: "iPhone 17"
    )
    private let iPhoneDuo = SimctlDeviceType(
        identifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo",
        name: "iPhone Duo"
    )

    /// The real case that makes this matter: one runtime here supports a single device.
    func testARuntimeIsOfferedOnlyForDevicesItSupports() {
        let support = [
            SimctlRuntimeSupport(runtime: runtime("iOS 27.0", "27.0"), deviceTypeIdentifiers: [iPhone17.identifier]),
            SimctlRuntimeSupport(runtime: runtime("iOS 27.1", "27.1"), deviceTypeIdentifiers: [iPhoneDuo.identifier]),
        ]
        XCTAssertEqual(SimulatorCreation.runtimes(for: iPhone17, in: support).map(\.name), ["iOS 27.0"])
        XCTAssertEqual(SimulatorCreation.runtimes(for: iPhoneDuo, in: support).map(\.name), ["iOS 27.1"])
    }

    func testNewestRuntimeComesFirst() {
        let both: Set<String> = [iPhone17.identifier]
        let support = [
            SimctlRuntimeSupport(runtime: runtime("iOS 26.5", "26.5"), deviceTypeIdentifiers: both),
            SimctlRuntimeSupport(runtime: runtime("iOS 27.0", "27.0"), deviceTypeIdentifiers: both),
            SimctlRuntimeSupport(runtime: runtime("iOS 9.0", "9.0"), deviceTypeIdentifiers: both),
        ]
        XCTAssertEqual(
            SimulatorCreation.runtimes(for: iPhone17, in: support).map(\.name),
            ["iOS 27.0", "iOS 26.5", "iOS 9.0"]
        )
    }

    func testAnUnavailableRuntimeIsNeverOffered() {
        let support = [
            SimctlRuntimeSupport(
                runtime: runtime("iOS 18.1", "18.1", available: false),
                deviceTypeIdentifiers: [iPhone17.identifier]
            )
        ]
        XCTAssertTrue(SimulatorCreation.runtimes(for: iPhone17, in: support).isEmpty)
    }

    func testOnlyIPhonesAndIPadsAreOffered() {
        XCTAssertTrue(SimulatorCreation.isSupported(iPhone17))
        XCTAssertTrue(SimulatorCreation.isSupported(
            type("iPad Pro 13-inch (M5)", "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13")
        ))
        XCTAssertFalse(SimulatorCreation.isSupported(
            type("Apple Watch Series 11", "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11")
        ))
        XCTAssertFalse(SimulatorCreation.isSupported(
            type("Apple TV 4K", "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K")
        ))
    }

    /// A device type no installed runtime can run would be a dead row in the picker.
    func testADeviceNoRuntimeCanRunIsNotOffered() {
        let support = [
            SimctlRuntimeSupport(runtime: runtime("iOS 27.0", "27.0"), deviceTypeIdentifiers: [iPhone17.identifier])
        ]
        let offered = SimulatorCreation.deviceTypes(in: support, from: [iPhone17, iPhoneDuo])
        XCTAssertEqual(offered.map(\.name), ["iPhone 17"])
    }

    func testTheSuggestedNameIsTheDeviceName() {
        XCTAssertEqual(SimulatorCreation.suggestedName(for: iPhone17, existing: []), "iPhone 17")
    }

    func testATakenNameGetsANumber() {
        XCTAssertEqual(
            SimulatorCreation.suggestedName(for: iPhone17, existing: ["iPhone 17"]),
            "iPhone 17 2"
        )
        XCTAssertEqual(
            SimulatorCreation.suggestedName(for: iPhone17, existing: ["iPhone 17", "iPhone 17 2"]),
            "iPhone 17 3"
        )
    }
}
