import Foundation

public enum PrivateSymbolKind: String, Sendable, Hashable {
    case classSymbol = "class"
    case protocolSymbol = "protocol"
}

public struct SymbolProbeResult: Sendable, Hashable {
    public let framework: PrivateFramework
    public let kind: PrivateSymbolKind
    public let requested: String
    /// The spelling the Objective-C runtime actually resolved, or nil if none did.
    public let resolved: String?

    public var isResolved: Bool { resolved != nil }
}

public enum PrivateSymbolProbe {
    /// Objective-C classes in CoreSimulator, confirmed exported on Xcode 26.5 (17F42).
    public static let coreSimulatorSymbols: [(PrivateSymbolKind, String)] = [
        (.classSymbol, "SimServiceContext"),
        (.classSymbol, "SimDeviceSet"),
        (.classSymbol, "SimDevice"),
        (.classSymbol, "SimDeviceType"),
        (.classSymbol, "SimRuntime"),
        (.classSymbol, "SimDeviceIO"),
        (.classSymbol, "SimDeviceIOClient"),
        (.protocolSymbol, "SimDeviceIOProtocol"),
        (.protocolSymbol, "SimDeviceNotifier"),
    ]

    /// The display and legacy HID surface lives in this sub-framework of CoreSimulator, which is
    /// loaded transitively. It is almost entirely protocols, and those are what the adapter casts to.
    public static let coreSimDeviceIOSymbols: [(PrivateSymbolKind, String)] = [
        (.classSymbol, "SimDeviceIOPort"),
        (.classSymbol, "SimDeviceIOPortDescriptor"),
        (.protocolSymbol, "SimDeviceIOPortInterface"),
        (.protocolSymbol, "SimDeviceIOPortDescriptorInterface"),
        (.protocolSymbol, "SimDeviceIOPortDescriptorState"),
        (.protocolSymbol, "SimDisplayRenderable"),
        (.protocolSymbol, "SimDisplayIOSurfaceRenderable"),
        (.protocolSymbol, "SimDisplayDescriptorState"),
        (.protocolSymbol, "SimDisplayRotationAngle"),
        (.protocolSymbol, "SimDisplayVSyncPresentable"),
        (.protocolSymbol, "SimLegacyHIDDescriptor"),
    ]

    /// SimulatorKit is a Swift framework on Xcode 26.5 (17F42), so its symbols are registered under
    /// mangled names and only resolve when the lookup is module qualified.
    public static let simulatorKitSymbols: [(PrivateSymbolKind, String)] = [
        (.classSymbol, "SimDeviceLegacyHIDClient"),
        (.classSymbol, "SimDeviceScreen"),
        (.classSymbol, "SimDisplayRenderableView"),
        (.classSymbol, "SimDigitizerInputView"),
        (.classSymbol, "SimHIDCaptureManager"),
    ]

    public static func symbols(for framework: PrivateFramework) -> [(PrivateSymbolKind, String)] {
        switch framework {
        case .coreSimulator: coreSimulatorSymbols
        case .coreSimDeviceIO: coreSimDeviceIOSymbols
        case .simulatorKit: simulatorKitSymbols
        }
    }

    public static func probeAll(in framework: PrivateFramework) -> [SymbolProbeResult] {
        symbols(for: framework).map { probe($0.1, kind: $0.0, in: framework) }
    }

    public static func probe(
        _ name: String,
        kind: PrivateSymbolKind,
        in framework: PrivateFramework
    ) -> SymbolProbeResult {
        let resolved = candidateSpellings(for: name, in: framework).first { spelling in
            switch kind {
            case .classSymbol: NSClassFromString(spelling) != nil
            case .protocolSymbol: NSProtocolFromString(spelling) != nil
            }
        }
        return SymbolProbeResult(
            framework: framework,
            kind: kind,
            requested: name,
            resolved: resolved
        )
    }

    static func candidateSpellings(for name: String, in framework: PrivateFramework) -> [String] {
        guard !name.contains(".") else { return [name] }
        return [name, "\(framework.rawValue).\(name)"]
    }
}
