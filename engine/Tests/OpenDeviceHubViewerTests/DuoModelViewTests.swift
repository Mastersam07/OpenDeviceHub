import Metal
import XCTest
@testable import OpenDeviceHubViewer

final class DuoModelViewTests: XCTestCase {
    /// The fold is the timeline's closing clip: the earlier stretches also run flat to shut, but
    /// turn the device on its side.
    func testTheFoldMapsOntoTheClosingClip() {
        XCTAssertEqual(DuoModelView.Pose.time(forHingeAngle: 180), 260.0 / 24, accuracy: 0.001)
        XCTAssertEqual(DuoModelView.Pose.time(forHingeAngle: 0), 380.0 / 24, accuracy: 0.001)
        XCTAssertEqual(
            DuoModelView.Pose.time(forHingeAngle: 90),
            (260.0 / 24 + 380.0 / 24) / 2,
            accuracy: 0.001
        )
    }

    func testAnglesOutsideTheHingeAreClamped() {
        XCTAssertEqual(DuoModelView.Pose.time(forHingeAngle: 400), 260.0 / 24, accuracy: 0.001)
        XCTAssertEqual(DuoModelView.Pose.time(forHingeAngle: -90), 380.0 / 24, accuracy: 0.001)
    }

    func testTheTextureTurnsWithThePanel() {
        XCTAssertEqual(DuoModelView.textureTransform(quarterTurns: 0).m11, 1)
        XCTAssertEqual(DuoModelView.textureTransform(quarterTurns: 1).m12, -1)
        XCTAssertEqual(DuoModelView.textureTransform(quarterTurns: 2).m11, -1)
        XCTAssertEqual(DuoModelView.textureTransform(quarterTurns: 3).m12, 1)
    }
}

@MainActor
final class DuoModelAssetTests: XCTestCase {
    func testTheModelLoadsAndBothScreensAreFound() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        guard let view = DuoModelView(metalDevice: device, showingCover: false, nativeRotation: 270)
        else {
            throw XCTSkip("this Xcode ships no foldable model")
        }
        XCTAssertNotNil(view.scene)

        view.setHingeAngle(120)
        XCTAssertEqual(view.hingeAngle, 120)
        view.setHingeAngle(400)
        XCTAssertEqual(view.hingeAngle, 180, "an angle beyond the hinge is clamped to it")
    }
}
