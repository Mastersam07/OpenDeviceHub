import AVFoundation
import IOSurface
import XCTest
@testable import OpenDeviceHubViewer

final class PanelRecorderTests: XCTestCase {
    private func surface(width: Int, height: Int, blue: UInt8, green: UInt8, red: UInt8) throws -> IOSurfaceRef {
        let made = IOSurfaceCreate([
            kIOSurfaceWidth: width, kIOSurfaceHeight: height,
            kIOSurfaceBytesPerElement: 4, kIOSurfacePixelFormat: kCVPixelFormatType_32BGRA,
        ] as CFDictionary)
        let surface = try XCTUnwrap(made)
        IOSurfaceLock(surface, [], nil)
        let base = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt8.self)
        let rowBytes = IOSurfaceGetBytesPerRow(surface)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = base + y * rowBytes + x * 4
                pixel[0] = blue; pixel[1] = green; pixel[2] = red; pixel[3] = 255
            }
        }
        IOSurfaceUnlock(surface, [], nil)
        return surface
    }

    private func pixel(of image: CGImage, x: Int, y: Int) -> (red: Int, green: Int, blue: Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    /// Two panels of different sizes land in one movie; the one followed is seen, fitted on black.
    func testTheMovieFollowsThePanelAndKeepsEachPanelsShape() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "panel-recorder-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = try PanelRecorder(url: url, size: CGSize(width: 400, height: 600), screenID: 3)
        let red = try surface(width: 400, height: 600, blue: 0, green: 0, red: 255)
        let green = try surface(width: 300, height: 400, blue: 0, green: 255, red: 0)

        for _ in 0..<4 {
            recorder.append(red, from: 3)
            recorder.append(green, from: 1)
            try await Task.sleep(for: .milliseconds(60))
        }
        recorder.follow(screenID: 1)
        for _ in 0..<4 {
            recorder.append(green, from: 1)
            recorder.append(red, from: 3)
            try await Task.sleep(for: .milliseconds(60))
        }
        XCTAssertEqual(recorder.frameCount, 8, "only the panel followed is recorded")
        recorder.stop()

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 400, height: 600))
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0.3)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let first = try await generator.image(at: .zero).image
        let last = try await generator.image(at: CMTime(seconds: duration.seconds - 0.01, preferredTimescale: 600)).image
        let firstCentre = pixel(of: first, x: 200, y: 300)
        let lastCentre = pixel(of: last, x: 200, y: 300)
        let lastTop = pixel(of: last, x: 200, y: 10)
        print("RESULT first centre \(firstCentre), last centre \(lastCentre), last top \(lastTop)")
        XCTAssertGreaterThan(firstCentre.red, 200, "the first frames are the red panel")
        XCTAssertGreaterThan(lastCentre.green, 200, "the last frames are the green panel")
        XCTAssertLessThan(lastTop.green + lastTop.red + lastTop.blue, 60, "the narrower panel is fitted on black")
    }
}
