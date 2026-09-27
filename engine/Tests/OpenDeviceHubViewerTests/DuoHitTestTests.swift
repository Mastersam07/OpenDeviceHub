import AppKit
import Metal
import SceneKit
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
        XCTAssertGreaterThan(found[.cameraControl, default: 0], 0, "the camera control is not on the body")
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
        // The camera control is the lower part on the same edge.
        let camera = try XCTUnwrap(view.hardwareButtonRect(.cameraControl))
        XCTAssertGreaterThan(camera.height, camera.width, "the camera control stands along the side")
        XCTAssertEqual(camera.midX, lock.midX, accuracy: 12, "on the same edge as the power button")
        XCTAssertLessThan(camera.maxY, lock.minY, "and below it")

        // Shut, they are still two different buttons under the pointer.
        view.setShowingCover(true, nativeRotation: 0)
        view.setHingeAngle(0)
        let shutDown = try XCTUnwrap(view.hardwareButtonRect(.volumeDown))
        let shutUp = try XCTUnwrap(view.hardwareButtonRect(.volumeUp))
        XCTAssertEqual(view.hardwareButton(at: CGPoint(x: shutDown.midX - 4, y: shutDown.midY)), .volumeDown)
        XCTAssertEqual(view.hardwareButton(at: CGPoint(x: shutUp.midX + 4, y: shutUp.midY)), .volumeUp)
        XCTAssertNotNil(view.hardwareButtonRect(.lock))
    }

    /// A shut device hides its volume buttons behind its front edge, so a button under the pointer
    /// has to come up out of the body to be seen at all. Only the hovered one moves, the pointer can
    /// follow it out, and it goes back when the pointer leaves. The symbol beside it takes no clicks.
    func testAHoveredButtonComesUpOutOfTheBody() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        guard let view = DuoModelView(metalDevice: device, showingCover: true, nativeRotation: 0)
        else { throw XCTSkip("this Xcode ships no foldable model") }
        view.frame = CGRect(x: 0, y: 0, width: 620, height: 440)
        view.layoutSubtreeIfNeeded()
        view.liftDuration = 0
        view.setHingeAngle(0)
        let up = try XCTUnwrap(view.hardwareButtonRect(.volumeUp))
        let down = try XCTUnwrap(view.hardwareButtonRect(.volumeDown))
        // Room above each button for it to rise into.
        let aboveUp = up.insetBy(dx: 0, dy: -14)
        let aboveDown = down.insetBy(dx: 0, dy: -14)

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = view.scene
        let upBefore = drawnPoints(renderer, view, in: aboveUp)
        let downBefore = drawnPoints(renderer, view, in: aboveDown)
        XCTAssertGreaterThan(upBefore, 0)

        let onUp = CGPoint(x: up.midX, y: up.midY)
        view.mouseMoved(with: mouseEvent(.mouseMoved, at: onUp))
        XCTAssertGreaterThan(view.liftOffset(of: .volumeUp), 0, "the button under the pointer came up")
        XCTAssertEqual(view.liftOffset(of: .volumeDown), 0, "its neighbour did not")
        let upAfter = drawnPoints(renderer, view, in: aboveUp)
        let downAfter = drawnPoints(renderer, view, in: aboveDown)
        print("RESULT shut, hovered: volume up drew \(upBefore) -> \(upAfter) points, volume down \(downBefore) -> \(downAfter)")
        XCTAssertGreaterThan(upAfter, upBefore + 60, "the button is now drawn where it was hidden")
        XCTAssertEqual(downAfter, downBefore, accuracy: 8, "the other button is where it was")

        // The pointer can follow the button up past where it used to end.
        let justAbove = CGPoint(x: up.midX, y: up.maxY + 3)
        XCTAssertEqual(view.hardwareButton(at: justAbove), .volumeUp)

        let badge = try XCTUnwrap(view.subviews.compactMap { $0 as? HardwareButtonBadge }.first)
        XCTAssertFalse(badge.isHidden)
        XCTAssertTrue(view.bounds.contains(badge.frame), "the symbol is inside the view")
        XCTAssertNil(badge.hitTest(CGPoint(x: badge.frame.midX, y: badge.frame.midY)), "the symbol takes no clicks")

        view.mouseExited(with: mouseEvent(.mouseExited, at: CGPoint(x: -10, y: -10)))
        XCTAssertEqual(view.liftOffset(of: .volumeUp), 0, "it went back down")
        XCTAssertNil(view.hardwareButton(at: justAbove))
        XCTAssertTrue(badge.isHidden)
        XCTAssertEqual(drawnPoints(renderer, view, in: aboveUp), upBefore, accuracy: 8)
    }

    /// How many points of the view, within this rectangle, have something drawn in them.
    private func drawnPoints(_ renderer: SCNRenderer, _ view: DuoModelView, in rect: CGRect) -> Int {
        renderer.pointOfView = view.pointOfView
        let image = renderer.snapshot(atTime: 0, with: view.bounds.size, antialiasingMode: .none)
        guard let raster = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else { return -1 }
        let scale = CGFloat(raster.pixelsWide) / view.bounds.width
        var count = 0
        let rows = Int((view.bounds.height - rect.maxY) * scale)..<Int((view.bounds.height - rect.minY) * scale)
        let columns = Int(rect.minX * scale)..<Int(rect.maxX * scale)
        for y in rows.clamped(to: 0..<raster.pixelsHigh) {
            for x in columns.clamped(to: 0..<raster.pixelsWide)
            where (raster.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 {
                count += 1
            }
        }
        return Int(CGFloat(count) / (scale * scale))
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
        if type == .mouseExited {
            return NSEvent.enterExitEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
            )!
        }
        return NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        )!
    }
}
