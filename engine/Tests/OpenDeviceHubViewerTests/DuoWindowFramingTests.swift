import AppKit
import Metal
import XCTest
@testable import OpenDeviceHubViewer

/// Framing is measured on the model's twin, so a pose has to sit centred in a window that is
/// actually drawing, not only off screen where nothing has evaluated the pose yet.
@MainActor
final class DuoWindowFramingTests: XCTestCase {
    func testOpenAndShutSitCentredInAWindowThatDraws() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        guard let view = DuoModelView(metalDevice: device, showingCover: false, nativeRotation: 270)
        else { throw XCTSkip("this Xcode ships no foldable model") }
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 440, height: 380),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500))

        func drawnCentre() -> CGPoint {
            let image = view.snapshot()
            guard let raster = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else { return CGPoint(x: -1, y: -1) }
            var minX = raster.pixelsWide, maxX = -1, minY = raster.pixelsHigh, maxY = -1
            for y in stride(from: 0, to: raster.pixelsHigh, by: 2) {
                for x in stride(from: 0, to: raster.pixelsWide, by: 2)
                where (raster.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            return CGPoint(x: Double(minX + maxX) / 2 / Double(raster.pixelsWide), y: Double(minY + maxY) / 2 / Double(raster.pixelsHigh))
        }

        view.setHingeAngle(180)
        try await Task.sleep(for: .milliseconds(300))
        let open = drawnCentre()
        view.setShowingCover(true, nativeRotation: 0)
        view.setHingeAngle(0)
        try await Task.sleep(for: .milliseconds(300))
        let shut = drawnCentre()
        print("RESULT drawn centre open \(open) shut \(shut)")
        for (name, centre) in [("open", open), ("shut", shut)] {
            XCTAssertEqual(centre.x, 0.5, accuracy: 0.03, "\(name) is off centre across")
            XCTAssertEqual(centre.y, 0.5, accuracy: 0.03, "\(name) is off centre down")
        }
    }
}
