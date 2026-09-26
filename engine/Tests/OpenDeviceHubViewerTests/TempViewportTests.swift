import AppKit
import Metal
import XCTest
@testable import OpenDeviceHubViewer
import OpenDeviceHubEngine

@MainActor
final class TempViewportTests: XCTestCase {
    private func fill(_ view: DuoModelView) throws -> String {
        let raster = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(view.snapshot().tiffRepresentation)))
        var minX = raster.pixelsWide, maxX = -1, minY = raster.pixelsHigh, maxY = -1
        for y in 0..<raster.pixelsHigh {
            for x in 0..<raster.pixelsWide {
                guard let c = raster.colorAt(x: x, y: y), c.alphaComponent > 0.3 else { continue }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return String(format: "fills %.2f across %.2f down, centre %.2f %.2f",
            Double(maxX - minX + 1) / Double(raster.pixelsWide), Double(maxY - minY + 1) / Double(raster.pixelsHigh),
            Double(minX + maxX) / 2 / Double(raster.pixelsWide), Double(minY + maxY) / 2 / Double(raster.pixelsHigh))
    }

    func testPosesInTheStableViewport() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        for size in [CGSize(width: 416, height: 292), CGSize(width: 620, height: 440)] {
            guard let view = DuoModelView(metalDevice: device, showingCover: false, nativeRotation: 270) else { throw XCTSkip("no model") }
            view.frame = CGRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            for angle in [180.0, 120.0, 90.0, 45.0, 30.0, 10.0, 0.0] {
                view.setHingeAngle(angle)
                if angle < 15 { view.setShowingCover(true, nativeRotation: 0) }
                print("PROBE \(Int(size.width))x\(Int(size.height)) at \(Int(angle)): \(try fill(view))")
            }
            view.setShowingCover(false, nativeRotation: 270)
            view.setHingeAngle(180)
            view.setOrientation(.landscapeLeft)
            print("PROBE \(Int(size.width))x\(Int(size.height)) turned: \(try fill(view))")
        }
    }
}
