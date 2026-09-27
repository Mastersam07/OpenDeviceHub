import Metal
import XCTest
@testable import OpenDeviceHubViewer

/// Between about 45 and 10 degrees the device stands almost on edge and is taller than the open
/// device the framing is held from, so the camera has to back off there, posed directly or mid move,
/// while the presets keep the framing they have.
@MainActor
final class DuoFramingLimitTests: XCTestCase {
    private func makeView() throws -> DuoModelView {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        guard let view = DuoModelView(metalDevice: device, showingCover: false, nativeRotation: 270)
        else { throw XCTSkip("this Xcode ships no foldable model") }
        view.frame = CGRect(x: 0, y: 0, width: 440, height: 380)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func testNoPoseTouchesTheEdgesAndThePresetsAreUnchanged() throws {
        let view = try makeView()
        var worst = CGSize.zero
        var fills: [Int: CGSize] = [:]
        for angle in stride(from: 180.0, through: 0, by: -10) {
            view.setHingeAngle(angle)
            let extent = view.drawnExtent(at: angle)
            fills[Int(angle)] = extent
            worst = CGSize(width: max(worst.width, extent.width), height: max(worst.height, extent.height))
            XCTAssertLessThanOrEqual(extent.width, 0.98, "\(Int(angle)) degrees touches the sides")
            XCTAssertLessThanOrEqual(extent.height, 0.98, "\(Int(angle)) degrees touches the top and bottom")
        }
        print("RESULT direct poses fill at most \(String(format: "%.2f across, %.2f down", worst.width, worst.height))")
        XCTAssertEqual(fills[180]?.height ?? 0, 0.77, accuracy: 0.03, "open is framed as before")
        XCTAssertEqual(fills[0]?.height ?? 0, 0.97, accuracy: 0.02, "shut is framed as before")
        XCTAssertGreaterThan(fills[20]?.height ?? 0, 0.9, "standing, the device still uses the height it has")
    }

    func testAMoveStaysInsideTheWindowAllTheWay() throws {
        let view = try makeView()
        view.setHingeAngle(180)
        view.beginMove(to: 0)
        var worst = CGSize.zero
        for angle in stride(from: 180.0, through: 0, by: -5) {
            view.setHingeAngle(angle)
            let extent = view.drawnExtent(at: angle)
            worst = CGSize(width: max(worst.width, extent.width), height: max(worst.height, extent.height))
            XCTAssertLessThanOrEqual(extent.height, 0.98, "\(Int(angle)) degrees touches the top and bottom mid move")
        }
        view.endMove()
        print("RESULT a move fills at most \(String(format: "%.2f across, %.2f down", worst.width, worst.height))")
    }
}
