import CoreGraphics
import Testing
@testable import OpenDeviceHubViewer

@Suite struct ScrollDragTests {
    @Test func aScrollDownMovesTheFingerDownTheView() {
        var drag = ScrollDrag(anchor: CGPoint(x: 100, y: 200), start: CGPoint(x: 0.5, y: 0.5))
        let moved = drag.move(deltaX: 0, deltaY: 30, precise: true)
        #expect(moved.x == 100)
        #expect(moved.y == 170)
    }

    @Test func theMovesAddUp() {
        var drag = ScrollDrag(anchor: CGPoint(x: 100, y: 200), start: CGPoint(x: 0.5, y: 0.5))
        _ = drag.move(deltaX: 5, deltaY: 10, precise: true)
        let moved = drag.move(deltaX: 5, deltaY: 10, precise: true)
        #expect(moved == CGPoint(x: 110, y: 180))
    }

    @Test func aWheelLineIsWorthAboutADozenPoints() {
        var drag = ScrollDrag(anchor: .zero, start: .zero)
        let moved = drag.move(deltaX: 0, deltaY: -1, precise: false)
        #expect(moved.y == 12)
    }

    @Test func liftsFromTheLastPointThatWasOnTheScreen() {
        var drag = ScrollDrag(anchor: .zero, start: CGPoint(x: 0.4, y: 0.6))
        #expect(drag.last == CGPoint(x: 0.4, y: 0.6))
        drag.last = CGPoint(x: 0.4, y: 0.9)
        #expect(drag.last == CGPoint(x: 0.4, y: 0.9))
    }
}
