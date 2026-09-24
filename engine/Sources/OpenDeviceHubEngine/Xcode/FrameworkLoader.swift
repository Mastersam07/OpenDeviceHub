import Foundation

public enum PrivateFramework: String, Sendable, Hashable, CaseIterable {
    case coreSimulator = "CoreSimulator"
    case coreSimDeviceIO = "CoreSimDeviceIO"
    case simulatorKit = "SimulatorKit"
    case simPasteboardPlus = "SimPasteboardPlus"

    /// Probed in order. CoreSimulator lives outside Xcode; SimulatorKit moved from the developer
    /// directory into the app bundle's SharedFrameworks in Xcode 27.
    public func candidatePaths(for install: XcodeInstall) -> [String] {
        switch self {
        case .coreSimulator:
            return [
                "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",
                install.developerDir
                    .appending(path: "Library/PrivateFrameworks/CoreSimulator.framework/CoreSimulator")
                    .path(percentEncoded: false),
            ]
        case .coreSimDeviceIO:
            let suffix = "CoreSimulator.framework/Frameworks/CoreSimDeviceIO.framework/CoreSimDeviceIO"
            return [
                "/Library/Developer/PrivateFrameworks/\(suffix)",
                install.developerDir
                    .appending(path: "Library/PrivateFrameworks/\(suffix)")
                    .path(percentEncoded: false),
            ]
        case .simPasteboardPlus:
            // Inside CoreSimulator's own bundle rather than beside it, which is why it is not a
            // variation of the two paths above.
            let suffix = "CoreSimulator.framework/Frameworks/SimPasteboardPlus.framework/SimPasteboardPlus"
            return [
                "/Library/Developer/PrivateFrameworks/\(suffix)",
                install.developerDir
                    .appending(path: "Library/PrivateFrameworks/\(suffix)")
                    .path(percentEncoded: false),
            ]
        case .simulatorKit:
            return [
                install.appRoot
                    .appending(path: "Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit")
                    .path(percentEncoded: false),
                install.developerDir
                    .appending(path: "Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit")
                    .path(percentEncoded: false),
            ]
        }
    }
}

public struct LoadedFramework: @unchecked Sendable {
    public let framework: PrivateFramework
    public let path: String
    let handle: UnsafeMutableRawPointer
}

public enum FrameworkLoader {
    public static func load(
        _ framework: PrivateFramework,
        from install: XcodeInstall
    ) throws -> LoadedFramework {
        var attempts: [String] = []

        for path in framework.candidatePaths(for: install) {
            guard FileManager.default.fileExists(atPath: path) else {
                attempts.append("\(path) (not present)")
                continue
            }
            if let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) {
                return LoadedFramework(framework: framework, path: path, handle: handle)
            }
            let reason = dlerror().map { String(cString: $0) } ?? "dlopen failed"
            attempts.append("\(path) (\(reason))")
        }

        throw EngineError.frameworkNotFound(name: framework.rawValue, searched: attempts)
    }
}

extension LoadedFramework {
    public func hasSymbol(_ name: String) -> Bool {
        symbol(named: name) != nil
    }

    /// Public so a test can cross check a table against a function the simulator exports.
    public func symbol(named name: String) -> UnsafeMutableRawPointer? {
        dlsym(handle, name)
    }
}
