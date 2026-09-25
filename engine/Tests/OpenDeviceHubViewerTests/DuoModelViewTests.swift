import Metal
import XCTest
@testable import OpenDeviceHubViewer

final class DuoModelViewTests: XCTestCase {
    func testTheFoldMapsOntoTheAssetsTimeline() {
        // Flat at the start, shut five seconds in, and halfway between at ninety degrees.
        XCTAssertEqual(DuoModelView.sceneTime(forHingeAngle: 180), 0)
        XCTAssertEqual(DuoModelView.sceneTime(forHingeAngle: 0), 5)
        XCTAssertEqual(DuoModelView.sceneTime(forHingeAngle: 90), 2.5, accuracy: 0.001)
        XCTAssertEqual(DuoModelView.sceneTime(forHingeAngle: 120), 5.0 / 3, accuracy: 0.001)
    }

    /// Nothing may ask the asset for a pose outside the fold, where the animation is a reel of
    /// unrelated poses.
    func testAnglesOutsideTheHingeAreClamped() {
        XCTAssertEqual(DuoModelView.sceneTime(forHingeAngle: 400), 0)
        XCTAssertEqual(DuoModelView.sceneTime(forHingeAngle: -90), 5)
    }
}

@MainActor
final class DuoModelAssetTests: XCTestCase {
    /// Loads the model Xcode ships and finds the screen in it. Skips where the asset is absent,
    /// which is every Xcode without a foldable.
    func testTheModelLoadsAndItsScreenIsFound() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        // The unfolded panel this device reports, which is what the screen is matched against.
        guard let view = DuoModelView(metalDevice: device, panelRatio: 2007.0 / 2853.0) else {
            throw XCTSkip("this Xcode ships no foldable model")
        }
        XCTAssertNotNil(view.scene)

        view.setHingeAngle(120)
        XCTAssertEqual(view.hingeAngle, 120)
        view.setHingeAngle(0)
        XCTAssertEqual(view.hingeAngle, 0)
        view.setHingeAngle(400)
        XCTAssertEqual(view.hingeAngle, 180, "an angle beyond the hinge is clamped to it")
    }
}
