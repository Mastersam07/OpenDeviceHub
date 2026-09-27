import Metal
import simd
import XCTest
@testable import OpenDeviceHubViewer

@MainActor
final class DuoMoveTests: XCTestCase {
    private func makeView() throws -> DuoModelView {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        guard let view = DuoModelView(metalDevice: device, showingCover: false, nativeRotation: 270)
        else { throw XCTSkip("this Xcode ships no foldable model") }
        view.frame = CGRect(x: 0, y: 0, width: 620, height: 440)
        view.layoutSubtreeIfNeeded()
        view.setHingeAngle(180)
        return view
    }

    /// A move makes no probe render per step, and ends framed exactly as a direct pose would be.
    func testAMoveIsFramedFromItsEndsAndNotPerStep() throws {
        let view = try makeView()
        view.beginMove(to: 0)
        let measured = view.probeRenders
        var worst = 0.0, total = 0.0
        let steps = 40
        for step in 1...steps {
            let start = ContinuousClock.now
            view.setHingeAngle(180 - 180 * Double(step) / Double(steps))
            let elapsed = ContinuousClock.now - start
            let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            worst = max(worst, ms)
            total += ms
        }
        print("RESULT a pose during a move: mean \(String(format: "%.1f", total / Double(steps))) ms, worst \(String(format: "%.1f", worst)) ms")
        XCTAssertEqual(view.probeRenders, measured, "no probe render during the move")
        view.endMove()

        let direct = try makeView()
        direct.setHingeAngle(0)
        let moved = view.pointOfView?.simdPosition ?? .zero
        let framed = direct.pointOfView?.simdPosition ?? .zero
        XCTAssertLessThan(simd_distance(moved, framed), 0.01, "the move ends where a direct pose is framed")
    }

    /// The camera walks between the two ends rather than sitting at either.
    func testTheCameraWalksBetweenTheEnds() throws {
        let view = try makeView()
        let open = view.pointOfView?.simdPosition ?? .zero
        view.beginMove(to: 0)
        view.setHingeAngle(0)
        let shut = view.pointOfView?.simdPosition ?? .zero
        view.setHingeAngle(90)
        let midway = view.pointOfView?.simdPosition ?? .zero
        XCTAssertGreaterThan(simd_distance(open, shut), 0.1, "the two ends are framed differently")
        XCTAssertGreaterThan(simd_distance(midway, open), 0.1, "midway is its own place")
        XCTAssertGreaterThan(simd_distance(midway, shut), 0.1)
    }
}
