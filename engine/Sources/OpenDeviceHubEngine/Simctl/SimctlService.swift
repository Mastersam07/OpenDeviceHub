import Foundation

public struct SimctlService: Sendable {
    public init() {}

    static func listDevicesArguments() -> [String] {
        ["simctl", "list", "devices", "-j"]
    }

    static func listRuntimesArguments() -> [String] {
        ["simctl", "list", "runtimes", "-j"]
    }

    public func listRuntimes() throws -> [SimctlRuntime] {
        try SimctlModels.parseRuntimes(run(Self.listRuntimesArguments()))
    }

    public func listDevices() throws -> [DeviceInfo] {
        let byRuntime = try SimctlModels.parseDevices(run(Self.listDevicesArguments()))
        let names = Dictionary(
            (try? listRuntimes())?.map { ($0.identifier, $0.name) } ?? [],
            uniquingKeysWith: { first, _ in first }
        )

        return byRuntime.flatMap { identifier, devices in
            devices.map { device in
                DeviceInfo(
                    udid: device.udid,
                    name: device.name,
                    deviceTypeIdentifier: device.deviceTypeIdentifier,
                    runtimeIdentifier: identifier,
                    runtimeName: SimctlModels.runtimeName(forIdentifier: identifier, runtimes: names),
                    state: DeviceState.from(stateString: device.state),
                    isAvailable: device.isAvailable
                )
            }
        }
    }

    private func run(_ arguments: [String]) throws -> Data {
        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments)
        guard result.status == 0 else {
            throw EngineError.simctl(
                args: Array(arguments.dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
        return Data(result.standardOutput.utf8)
    }
}

extension SimctlService {
    static func bootArguments(udid: String) -> [String] {
        ["simctl", "boot", udid]
    }

    static func shutdownArguments(udid: String) -> [String] {
        ["simctl", "shutdown", udid]
    }

    static func bootStatusArguments(udid: String) -> [String] {
        ["simctl", "bootstatus", udid, "-b"]
    }

    /// Booting is something simctl does well, so the adapter does not reach for `bootWithOptions:`.
    /// An already booted device makes `simctl boot` fail, which is treated as success.
    public func boot(udid: String) throws {
        let result = try ProcessRunner.run("/usr/bin/xcrun", Self.bootArguments(udid: udid))
        if result.status != 0, !result.standardError.contains("current state: Booted") {
            throw EngineError.simctl(
                args: Array(Self.bootArguments(udid: udid).dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
    }

    /// An already shut down device makes `simctl shutdown` fail, which is treated as success.
    public func shutdown(udid: String) throws {
        let result = try ProcessRunner.run("/usr/bin/xcrun", Self.shutdownArguments(udid: udid))
        if result.status != 0, !result.standardError.contains("current state: Shutdown") {
            throw EngineError.simctl(
                args: Array(Self.shutdownArguments(udid: udid).dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
    }

    public func waitForBoot(udid: String) throws {
        let result = try ProcessRunner.run("/usr/bin/xcrun", Self.bootStatusArguments(udid: udid))
        guard result.status == 0 else {
            throw EngineError.simctl(
                args: Array(Self.bootStatusArguments(udid: udid).dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
    }
}

extension SimctlService {
    static func pasteboardCopyArguments(udid: String) -> [String] {
        ["simctl", "pbcopy", udid]
    }

    static func pasteboardPasteArguments(udid: String) -> [String] {
        ["simctl", "pbpaste", udid]
    }

    /// Puts text on the device's pasteboard, so it can be pasted inside the guest.
    public func pasteboardCopy(_ text: String, udid: String) throws {
        let arguments = Self.pasteboardCopyArguments(udid: udid)
        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments, standardInput: text)
        guard result.status == 0 else {
            throw EngineError.simctl(
                args: Array(arguments.dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
    }

    public func pasteboardPaste(udid: String) throws -> String {
        let arguments = Self.pasteboardPasteArguments(udid: udid)
        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments)
        guard result.status == 0 else {
            throw EngineError.simctl(
                args: Array(arguments.dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
        return result.standardOutput
    }
}

extension SimctlService {
    public enum Appearance: String, Sendable, CaseIterable {
        case light
        case dark
    }

    static func appearanceArguments(udid: String, appearance: Appearance) -> [String] {
        ["simctl", "ui", udid, "appearance", appearance.rawValue]
    }

    static func readAppearanceArguments(udid: String) -> [String] {
        ["simctl", "ui", udid, "appearance"]
    }

    public func setAppearance(_ appearance: Appearance, udid: String) throws {
        let arguments = Self.appearanceArguments(udid: udid, appearance: appearance)
        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments)
        guard result.status == 0 else {
            throw EngineError.simctl(
                args: Array(arguments.dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
    }

    public func appearance(udid: String) throws -> Appearance? {
        let arguments = Self.readAppearanceArguments(udid: udid)
        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments)
        guard result.status == 0 else { return nil }
        return Appearance(rawValue: result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension SimctlService {
    static func installArguments(udid: String, app: URL) -> [String] {
        ["simctl", "install", udid, app.path(percentEncoded: false)]
    }

    static func addMediaArguments(udid: String, files: [URL]) -> [String] {
        ["simctl", "addmedia", udid] + files.map { $0.path(percentEncoded: false) }
    }

    static func addRootCertificateArguments(udid: String, certificate: URL) -> [String] {
        ["simctl", "keychain", udid, "add-root-cert", certificate.path(percentEncoded: false)]
    }

    static func openURLArguments(udid: String, url: String) -> [String] {
        ["simctl", "openurl", udid, url]
    }

    public func perform(_ action: DropAction, udid: String) throws {
        let arguments: [String]
        switch action {
        case .installApp(let app):
            arguments = Self.installArguments(udid: udid, app: app)
        case .addMedia(let files):
            arguments = Self.addMediaArguments(udid: udid, files: files)
        case .addRootCertificate(let certificate):
            arguments = Self.addRootCertificateArguments(udid: udid, certificate: certificate)
        case .openURL(let url):
            arguments = Self.openURLArguments(udid: udid, url: url)
        case .unsupported(let url):
            throw EngineError.capabilityUnavailable(name: "dropping \(url.lastPathComponent)")
        }

        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments)
        guard result.status == 0 else {
            throw EngineError.simctl(
                args: Array(arguments.dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
    }
}

extension SimctlService {
    public enum ContainerKind: String, Sendable, CaseIterable {
        case app
        case data
        case groups
    }

    static func appContainerArguments(udid: String, bundleID: String, kind: ContainerKind) -> [String] {
        ["simctl", "get_app_container", udid, bundleID, kind.rawValue]
    }

    public func appContainer(udid: String, bundleID: String, kind: ContainerKind) throws -> URL? {
        let arguments = Self.appContainerArguments(udid: udid, bundleID: bundleID, kind: kind)
        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments)
        guard result.status == 0 else {
            throw EngineError.simctl(
                args: Array(arguments.dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
        let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, path != "(null)" else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Where the simulator writes this device's logs.
    public static func systemLogDirectory(udid: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Logs/CoreSimulator")
            .appending(path: udid)
    }

    /// The device's own data directory, which is where an app's container lives.
    public static func deviceDataDirectory(udid: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Developer/CoreSimulator/Devices")
            .appending(path: udid)
            .appending(path: "data")
    }
}

extension SimctlService {
    /// Darwin notifications the guest's UIKit listens for. Both names were read out of the
    /// runtime's UIKitCore rather than guessed, and both were confirmed by their visible effect on
    /// Xcode 26.5: shake raised an Undo dialog, slow motion left an app mid transition a second
    /// after launch.
    public enum GuestNotification: String, Sendable, CaseIterable {
        case shake = "com.apple.UIKit.SimulatorShake"
        case slowMotionAnimation = "com.apple.UIKit.SimulatorSlowMotionAnimationState"
    }

    static func postNotificationArguments(udid: String, name: GuestNotification) -> [String] {
        ["simctl", "spawn", udid, "notifyutil", "-p", name.rawValue]
    }

    static func setNotificationStateArguments(
        udid: String,
        name: GuestNotification,
        state: Int
    ) -> [String] {
        ["simctl", "spawn", udid, "notifyutil", "-s", name.rawValue, String(state)]
    }

    public func shake(udid: String) throws {
        try runSimctl(Self.postNotificationArguments(udid: udid, name: .shake))
    }

    /// Slow motion is a notify state, so the value is set first and the notification then tells
    /// UIKit to read it.
    public func setSlowAnimations(_ enabled: Bool, udid: String) throws {
        try runSimctl(Self.setNotificationStateArguments(
            udid: udid, name: .slowMotionAnimation, state: enabled ? 1 : 0
        ))
        try runSimctl(Self.postNotificationArguments(udid: udid, name: .slowMotionAnimation))
    }

    private func runSimctl(_ arguments: [String]) throws {
        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments)
        guard result.status == 0 else {
            throw EngineError.simctl(
                args: Array(arguments.dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
    }
}

extension SimctlService {
    public enum ContentSizeStep: String, Sendable {
        case increment
        case decrement
    }

    /// The scenarios `simctl location list` reports, which are the same four Simulator.app offers.
    public enum LocationScenario: String, CaseIterable, Sendable {
        case cityRun = "City Run"
        case cityBicycleRide = "City Bicycle Ride"
        case freewayDrive = "Freeway Drive"
        case apple = "Apple"
    }

    static func eraseArguments(udid: String) -> [String] {
        ["simctl", "erase", udid]
    }

    static func iCloudSyncArguments(udid: String) -> [String] {
        ["simctl", "icloud_sync", udid]
    }

    static func contentSizeArguments(udid: String, step: ContentSizeStep) -> [String] {
        ["simctl", "ui", udid, "content_size", step.rawValue]
    }

    static func increaseContrastArguments(udid: String, enabled: Bool) -> [String] {
        ["simctl", "ui", udid, "increase_contrast", enabled ? "enabled" : "disabled"]
    }

    static func readIncreaseContrastArguments(udid: String) -> [String] {
        ["simctl", "ui", udid, "increase_contrast"]
    }

    static func locationScenarioArguments(udid: String, scenario: LocationScenario) -> [String] {
        ["simctl", "location", udid, "run", scenario.rawValue]
    }

    static func locationSetArguments(udid: String, latitude: Double, longitude: Double) -> [String] {
        ["simctl", "location", udid, "set", "\(latitude),\(longitude)"]
    }

    static func locationClearArguments(udid: String) -> [String] {
        ["simctl", "location", udid, "clear"]
    }

    /// Erasing needs the device down first, and leaves it down. The caller decides whether to boot
    /// it again, because erasing to then throw the device away is a reasonable thing to want.
    public func erase(udid: String) throws {
        try? shutdown(udid: udid)
        try runChecked(Self.eraseArguments(udid: udid))
    }

    /// Down and up again. Shutting down a device that is already down is not an error worth
    /// stopping for, which is why only the boot is checked.
    public func restart(udid: String) throws {
        try? shutdown(udid: udid)
        try boot(udid: udid)
    }

    public func triggerICloudSync(udid: String) throws {
        try runChecked(Self.iCloudSyncArguments(udid: udid))
    }

    public func stepContentSize(_ step: ContentSizeStep, udid: String) throws {
        try runChecked(Self.contentSizeArguments(udid: udid, step: step))
    }

    public func setIncreaseContrast(_ enabled: Bool, udid: String) throws {
        try runChecked(Self.increaseContrastArguments(udid: udid, enabled: enabled))
    }

    public func increasesContrast(udid: String) -> Bool {
        let result = try? ProcessRunner.run("/usr/bin/xcrun", Self.readIncreaseContrastArguments(udid: udid))
        return result?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "enabled"
    }

    public func runLocation(_ scenario: LocationScenario, udid: String) throws {
        try runChecked(Self.locationScenarioArguments(udid: udid, scenario: scenario))
    }

    public func setLocation(latitude: Double, longitude: Double, udid: String) throws {
        try runChecked(Self.locationSetArguments(udid: udid, latitude: latitude, longitude: longitude))
    }

    public func clearLocation(udid: String) throws {
        try runChecked(Self.locationClearArguments(udid: udid))
    }

    private func runChecked(_ arguments: [String]) throws {
        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments)
        guard result.status == 0 else {
            throw EngineError.simctl(
                args: Array(arguments.dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
    }
}

/// Creating a simulator, and the lists a person picks from to do it.
extension SimctlService {
    static func listDeviceTypesArguments() -> [String] {
        ["simctl", "list", "devicetypes", "-j"]
    }

    static func createArguments(name: String, deviceType: String, runtime: String) -> [String] {
        ["simctl", "create", name, deviceType, runtime]
    }

    public func listDeviceTypes() throws -> [SimctlDeviceType] {
        let data = try run(Self.listDeviceTypesArguments())
        return try JSONDecoder().decode(SimctlModels.DeviceTypeList.self, from: data).devicetypes
    }

    /// Which device types each runtime can run, which `simctl` only reports here rather than on the
    /// device types themselves.
    public func listRuntimeSupport() throws -> [SimctlRuntimeSupport] {
        let data = try run(Self.listRuntimesArguments())
        let decoded = try JSONDecoder().decode(SimctlModels.RuntimeSupportList.self, from: data)
        return decoded.runtimes.map { runtime in
            SimctlRuntimeSupport(
                runtime: SimctlRuntime(
                    identifier: runtime.identifier,
                    name: runtime.name,
                    version: runtime.version,
                    buildversion: runtime.buildversion,
                    isAvailable: runtime.isAvailable
                ),
                deviceTypeIdentifiers: Set((runtime.supportedDeviceTypes ?? []).map(\.identifier))
            )
        }
    }

    /// Returns the new device's UDID, which is all `simctl create` prints.
    @discardableResult
    public func createDevice(name: String, deviceType: String, runtime: String) throws -> String {
        let arguments = Self.createArguments(name: name, deviceType: deviceType, runtime: runtime)
        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments)
        guard result.status == 0 else {
            throw EngineError.simctl(
                args: Array(arguments.dropFirst()),
                code: result.status,
                stderr: result.standardError
            )
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
