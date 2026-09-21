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
