import AVFoundation
import CoreImage
import Foundation
import IOSurface
import OpenDeviceHubEngine

/// One movie of one size from whichever panel is followed; `simctl` records one display per file.
final class PanelRecorder: @unchecked Sendable {
    let url: URL
    let size: CGSize

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var startedAt: ContinuousClock.Instant?
    private var activeScreenID: Int
    private var finished = false
    private var frames = 0

    init(url: URL, size: CGSize, screenID: Int) throws {
        // The encoder wants even dimensions.
        let width = Int(size.width.rounded(.down)) & ~1
        let height = Int(size.height.rounded(.down)) & ~1
        self.url = url
        self.size = CGSize(width: width, height: height)
        activeScreenID = screenID
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? EngineError.capabilityUnavailable(name: "recording")
        }
        writer.startSession(atSourceTime: .zero)
    }

    /// The panel whose frames go into the movie from now on.
    func follow(screenID: Int) {
        lock.lock()
        activeScreenID = screenID
        lock.unlock()
    }

    var frameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    /// Frames from any panel but the one followed are dropped; a smaller panel is fitted on black.
    /// `quarterTurns` undoes how far the panel is built round, as the model does when it draws.
    func append(_ surface: IOSurfaceRef, from screenID: Int, turnedBy quarterTurns: Int = 0) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, screenID == activeScreenID, input.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }
        let now = ContinuousClock.now
        let started = startedAt ?? now
        startedAt = started
        let elapsed = now - started
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let time = CMTime(seconds: seconds, preferredTimescale: 600)

        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        let picture = CIImage(ioSurface: surface).oriented(Self.orientation(quarterTurns: quarterTurns))
        let scale = min(size.width / picture.extent.width, size.height / picture.extent.height)
        let fitted = picture
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(
                translationX: (size.width - picture.extent.width * scale) / 2,
                y: (size.height - picture.extent.height * scale) / 2
            ))
        let frame = fitted.composited(over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size)))
        context.render(frame, to: buffer, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpaceCreateDeviceRGB())
        if adaptor.append(buffer, withPresentationTime: time) {
            frames += 1
        }
    }

    static func orientation(quarterTurns: Int) -> CGImagePropertyOrientation {
        switch ((quarterTurns % 4) + 4) % 4 {
        case 1: .right
        case 2: .down
        case 3: .left
        default: .up
        }
    }

    /// Finishes the movie and waits for it to be written.
    @discardableResult
    func stop() -> URL {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        lock.unlock()
        guard !alreadyFinished else { return url }
        input.markAsFinished()
        let written = DispatchSemaphore(value: 0)
        writer.finishWriting { written.signal() }
        _ = written.wait(timeout: .now() + 10)
        return url
    }
}
