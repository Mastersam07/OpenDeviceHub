import Foundation

public enum EngineError: Error, Sendable, Hashable {
    case xcodeNotFound(searched: [String])
    case xcodeVersionUnreadable(output: String)
    case unsupportedXcode(version: String, supported: String, note: String)
    case frameworkNotFound(name: String, searched: [String])
    case symbolNotFound(name: String, framework: String)
    case capabilityUnavailable(name: String)
    case deviceNotFound(udid: String)
    case deviceNotBooted(udid: String)
    case privateCall(symbol: String, message: String)
    case simctl(args: [String], code: Int32, stderr: String)
}

extension EngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .xcodeNotFound(let searched):
            return "No Xcode developer directory found. Searched: \(searched.joined(separator: ", "))"
        case .xcodeVersionUnreadable(let output):
            return "Could not read the Xcode version from: \(output)"
        case .unsupportedXcode(let version, let supported, let note):
            return "Xcode \(version) is not supported (supported: \(supported)). \(note)"
        case .frameworkNotFound(let name, let searched):
            return "\(name) was not found. Searched: \(searched.joined(separator: ", "))"
        case .symbolNotFound(let name, let framework):
            return "\(name) was not found in \(framework) on this Xcode build."
        case .capabilityUnavailable(let name):
            return "\(name) is not available on this Xcode build."
        case .deviceNotFound(let udid):
            return "No simulator with UDID \(udid)."
        case .deviceNotBooted(let udid):
            return "Simulator \(udid) is not booted."
        case .privateCall(let symbol, let message):
            return "\(symbol) failed: \(message)"
        case .simctl(let args, let code, let stderr):
            let command = (["simctl"] + args).joined(separator: " ")
            return "\(command) failed with status \(code): \(stderr)"
        }
    }
}
