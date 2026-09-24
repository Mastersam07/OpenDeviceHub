import Foundation

/// A capture that has been taken but not yet filed.
///
/// The simulator this replaces writes nothing to the capture folder while its preview is on screen:
/// the file appears only once the preview goes away without being acted on. Confirmed by watching
/// the folder during a capture. So a capture lands in a temporary place first, and this is what
/// decides where it ends up.
public struct PendingCapture: Equatable, Sendable {
    public let temporary: URL
    public let destination: URL

    public init(temporary: URL, destination: URL) {
        self.temporary = temporary
        self.destination = destination
    }

    public var name: String { temporary.lastPathComponent }

    /// Where the file will be when nothing is done to it.
    public var settled: URL { destination.appending(path: name) }
}

/// Moving, saving and discarding a pending capture. Separated from the preview window so the rules
/// can be tested without anything on screen.
/// `FileManager` is thread safe but not marked `Sendable`, hence the unchecked conformance, the
/// same reason `UserDefaultsPreferenceStorage` carries one.
public struct CaptureFiler: @unchecked Sendable {
    private let manager: FileManager

    public init(manager: FileManager = .default) {
        self.manager = manager
    }

    /// Moves the capture where it was always going. Returns where it landed, which is not always
    /// what was asked for: a name already taken gets a number rather than overwriting.
    @discardableResult
    public func settle(_ capture: PendingCapture) throws -> URL {
        try manager.createDirectory(at: capture.destination, withIntermediateDirectories: true)
        let target = Self.availableURL(capture.settled, manager: manager)
        try manager.moveItem(at: capture.temporary, to: target)
        return target
    }

    @discardableResult
    public func save(_ capture: PendingCapture, to chosen: URL) throws -> URL {
        if manager.fileExists(atPath: chosen.path(percentEncoded: false)) {
            try manager.removeItem(at: chosen)
        }
        try manager.moveItem(at: capture.temporary, to: chosen)
        return chosen
    }

    public func discard(_ capture: PendingCapture) {
        try? manager.removeItem(at: capture.temporary)
    }

    /// `name.png`, then `name 2.png`, and so on. Overwriting someone's earlier capture because the
    /// clock produced the same second is not a trade worth making.
    static func availableURL(_ wanted: URL, manager: FileManager) -> URL {
        guard manager.fileExists(atPath: wanted.path(percentEncoded: false)) else { return wanted }
        let directory = wanted.deletingLastPathComponent()
        let stem = wanted.deletingPathExtension().lastPathComponent
        let ext = wanted.pathExtension
        for suffix in 2...999 {
            let candidate = directory
                .appending(path: ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)")
            if !manager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        return wanted
    }
}
