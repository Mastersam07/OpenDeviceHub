import Metal
import XCTest
@testable import OpenDeviceHubViewer
import OpenDeviceHubEngine

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

extension DuoHitTestTests {
    /// The body's buttons are found by where they sit, hit tested as the screens are, and nothing
    /// else on the body answers as a button.
    func testTheBodysButtonsAreWhereTheyAre() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        guard let view = DuoModelView(metalDevice: device, showingCover: false, nativeRotation: 270)
        else { throw XCTSkip("this Xcode ships no foldable model") }
        view.frame = CGRect(x: 0, y: 0, width: 620, height: 440)
        view.layoutSubtreeIfNeeded()
        view.setHingeAngle(180)

        var found: [HardwareButton: Int] = [:]
        var onScreen = 0
        for x in stride(from: 2.0, to: 620.0, by: 4.0) {
            for y in stride(from: 2.0, to: 440.0, by: 4.0) {
                let point = CGPoint(x: x, y: y)
                if let button = view.hardwareButton(at: point) {
                    found[button, default: 0] += 1
                    XCTAssertNil(view.screenPoint(at: point), "a button and the screen overlap at \(point)")
                } else if view.screenPoint(at: point) != nil {
                    onScreen += 1
                }
            }
        }
        print("RESULT buttons hit: \(found), screen points \(onScreen)")
        XCTAssertGreaterThan(found[.volumeDown, default: 0], 0, "volume down is not on the body")
        XCTAssertGreaterThan(found[.volumeUp, default: 0], 0, "volume up is not on the body")
        XCTAssertGreaterThan(found[.lock, default: 0], 0, "the power button is not on the body")
        XCTAssertNil(found[.home])
        XCTAssertGreaterThan(onScreen, found.values.reduce(0, +) * 20, "the buttons are small next to the screen")

        // The two volume buttons are neighbours on the top edge, down to the left of up, a small
        // gap apart; the power button stands on the right edge. A flat strip on the top edge is not
        // a button, and once counted as one, which shifted every label along by one.
        let down = try XCTUnwrap(view.hardwareButtonRect(.volumeDown))
        let up = try XCTUnwrap(view.hardwareButtonRect(.volumeUp))
        let lock = try XCTUnwrap(view.hardwareButtonRect(.lock))
        XCTAssertLessThan(down.midX, up.midX, "volume down is to the left of volume up")
        XCTAssertLessThan(up.minX - down.maxX, 30, "the volume buttons are neighbours, not \(up.minX - down.maxX) points apart")
        XCTAssertGreaterThan(down.midX, view.bounds.midX, "the volume buttons are on the right half")
        XCTAssertGreaterThan(lock.midX, up.maxX, "the power button is further right, on the side")
        XCTAssertGreaterThan(lock.height, lock.width, "the power button stands along the side")

        // Shut, they are still two different buttons under the pointer.
        view.setShowingCover(true, nativeRotation: 0)
        view.setHingeAngle(0)
        let shutDown = try XCTUnwrap(view.hardwareButtonRect(.volumeDown))
        let shutUp = try XCTUnwrap(view.hardwareButtonRect(.volumeUp))
        XCTAssertEqual(view.hardwareButton(at: CGPoint(x: shutDown.midX - 4, y: shutDown.midY)), .volumeDown)
        XCTAssertEqual(view.hardwareButton(at: CGPoint(x: shutUp.midX + 4, y: shutUp.midY)), .volumeUp)
        XCTAssertNotNil(view.hardwareButtonRect(.lock))
    }
}
