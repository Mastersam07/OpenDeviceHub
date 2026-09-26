import Metal
import XCTest
@testable import OpenDeviceHubViewer

@MainActor
final class DuoHitTestTests: XCTestCase {
    /// A click in the middle of the window should land in the middle of the screen, and clicks
    /// either side of it should land either side. Checked at each pose, because the whole point of
    /// skinning the mesh by hand is that a bent screen is not where SceneKit thinks it is.
    func testClicksLandWhereTheyAreAimed() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        guard let view = DuoModelView(metalDevice: device, showingCover: false, nativeRotation: 0)
        else { throw XCTSkip("this Xcode ships no foldable model") }
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 440)
        view.layoutSubtreeIfNeeded()

        for angle in [180.0, 120.0] {
            view.setHingeAngle(angle)
            let middle = CGPoint(x: 320, y: 220)
            guard let centre = view.screenPoint(at: middle) else {
                XCTFail("a click in the middle missed the screen at \(Int(angle)) degrees")
                continue
            }
            XCTAssertEqual(centre.x, 0.5, accuracy: 0.12, "middle of the window at \(Int(angle))")
            XCTAssertEqual(centre.y, 0.5, accuracy: 0.12, "middle of the window at \(Int(angle))")

            // Left of the middle should read left of the middle, and right likewise.
            let left = view.screenPoint(at: CGPoint(x: 220, y: 220))
            let right = view.screenPoint(at: CGPoint(x: 420, y: 220))
            if let left, let right {
                XCTAssertLessThan(left.x, right.x, "left and right are swapped at \(Int(angle))")
            }

            // And the same up and down. The guest counts down its screen, so a click higher up the
            // window has to come out smaller, which a stray flip in the mapping would reverse: every
            // tap then landed mirrored, while swipes, which the guest reads from the edge, still
            // worked and hid it.
            let above = view.screenPoint(at: CGPoint(x: 320, y: 300))
            let below = view.screenPoint(at: CGPoint(x: 320, y: 140))
            if let above, let below {
                XCTAssertLessThan(above.y, below.y, "up and down are swapped at \(Int(angle))")
            }
        }
    }

    /// The two panels are built into the housing at different angles, so following the guest from
    /// one to the other has to bring the angle with it. Keeping the first panel's angle turned the
    /// cover's picture a quarter turn and took every click on it with it.
    func testFollowingToTheOtherPanelBringsItsOwnBuildAngle() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        guard let view = DuoModelView(metalDevice: device, showingCover: false, nativeRotation: 270)
        else { throw XCTSkip("this Xcode ships no foldable model") }
        view.frame = CGRect(x: 0, y: 0, width: 440, height: 620)
        view.layoutSubtreeIfNeeded()

        view.setShowingCover(true, nativeRotation: 0)
        view.setHingeAngle(0)

        let middle = try XCTUnwrap(
            view.screenPoint(at: CGPoint(x: 220, y: 310)),
            "a click in the middle missed the cover"
        )
        XCTAssertEqual(middle.x, 0.5, accuracy: 0.15)
        XCTAssertEqual(middle.y, 0.5, accuracy: 0.15)

        let left = view.screenPoint(at: CGPoint(x: 150, y: 310))
        let right = view.screenPoint(at: CGPoint(x: 290, y: 310))
        if let left, let right {
            XCTAssertLessThan(left.x, right.x, "left and right are swapped on the cover")
        }
        let above = view.screenPoint(at: CGPoint(x: 220, y: 420))
        let below = view.screenPoint(at: CGPoint(x: 220, y: 200))
        if let above, let below {
            XCTAssertLessThan(above.y, below.y, "up and down are swapped on the cover")
        }
    }
}
