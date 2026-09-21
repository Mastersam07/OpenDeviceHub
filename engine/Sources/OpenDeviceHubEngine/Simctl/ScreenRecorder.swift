import Foundation

/// Records a device's screen with `simctl io recordVideo`. Stopping means sending SIGINT, because
/// that is how simctl is told to finish the file cleanly; killing it leaves an unplayable movie.
public final class ScreenRecorder: @unchecked Sendable {
    public enum Codec: String, Sendable, CaseIterable {
        case h264
        case hevc
    }

    /// How a non rectangular display's mask is handled. `black` matches what the window shows.
    public enum MaskPolicy: String, Sendable, CaseIterable {
        case ignored
        case black
    }

    public let url: URL
    private let process: Process
    private let lock = NSLock()
    private var hasStopped = false

    static func arguments(
        udid: String,
        url: URL,
        codec: Codec,
        mask: MaskPolicy
    ) -> [String] {
        [
            "simctl", "io", udid, "recordVideo",
            "--codec=\(codec.rawValue)",
            "--mask=\(mask.rawValue)",
            "--force",
            url.path(percentEncoded: false),
        ]
    }

    public init(
        udid: String,
        url: URL,
        codec: Codec = .h264,
        mask: MaskPolicy = .black
    ) throws {
        self.url = url
        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = Self.arguments(udid: udid, url: url, codec: codec, mask: mask)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
    }

    public var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !hasStopped && process.isRunning
    }

    /// Finishes the recording and waits for the file to be written.
    @discardableResult
    public func stop() -> URL {
        lock.lock()
        let alreadyStopped = hasStopped
        hasStopped = true
        lock.unlock()

        guard !alreadyStopped, process.isRunning else { return url }
        process.interrupt()
        process.waitUntilExit()
        return url
    }
}
