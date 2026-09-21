import Foundation

public struct ClassProbeResult: Sendable, Hashable {
    public let framework: PrivateFramework
    public let requested: String
    /// The spelling that the Objective-C runtime actually resolved, or nil if none did.
    public let resolved: String?

    public var isResolved: Bool { resolved != nil }
}

public enum PrivateSymbolProbe {
    /// Objective-C classes in CoreSimulator, confirmed exported on Xcode 26.5 (17F42).
    public static let coreSimulatorClasses = [
        "SimServiceContext",
        "SimDeviceSet",
        "SimDevice",
        "SimDeviceType",
        "SimRuntime",
        "SimDeviceIO",
        "SimDeviceIOClient",
    ]

    /// SimulatorKit is a Swift framework on Xcode 26.5 (17F42), so its classes are registered
    /// under mangled names and only resolve when the lookup is module qualified.
    public static let simulatorKitClasses = [
        "SimDeviceLegacyHIDClient",
        "SimDeviceScreen",
        "SimDisplayRenderableView",
        "SimDigitizerInputView",
        "SimHIDCaptureManager",
    ]

    public static func probeAll(in framework: PrivateFramework) -> [ClassProbeResult] {
        let names = switch framework {
        case .coreSimulator: coreSimulatorClasses
        case .simulatorKit: simulatorKitClasses
        }
        return names.map { probe($0, in: framework) }
    }

    public static func probe(_ name: String, in framework: PrivateFramework) -> ClassProbeResult {
        let resolved = candidateSpellings(for: name, in: framework)
            .first { NSClassFromString($0) != nil }
        return ClassProbeResult(framework: framework, requested: name, resolved: resolved)
    }

    static func candidateSpellings(for name: String, in framework: PrivateFramework) -> [String] {
        guard !name.contains(".") else { return [name] }
        return [name, "\(framework.rawValue).\(name)"]
    }
}
