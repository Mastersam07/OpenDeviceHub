import Testing
@testable import OpenDeviceHubEngine

@Suite struct HingeMoveTests {
    @Test func startsAndEndsExactlyWhereItIsAsked() {
        let move = HingeMove(start: 180, target: 0)
        #expect(move.angle(at: 0) == 180)
        #expect(move.angle(at: 1) == 0)
        #expect(move.angle(at: -0.5) == 180)
        #expect(move.angle(at: 1.5) == 0)
        #expect(move.angle(at: 0.5) == 90)
    }

    @Test func neverTurnsBack() {
        let move = HingeMove(start: 0, target: 180)
        var last = -1.0
        for step in 0...100 {
            let angle = move.angle(at: Double(step) / 100)
            #expect(angle >= last)
            last = angle
        }
    }

    @Test func settlesAtBothEnds() {
        let move = HingeMove(start: 0, target: 180)
        #expect(move.angle(at: 0.05) < 2, "barely moving at the start")
        #expect(move.angle(at: 0.95) > 178, "barely moving at the end")
        #expect(move.angle(at: 0.25) + move.angle(at: 0.75) == 180, "symmetric")
    }

    @Test func takesLongerOverALongerWay() {
        #expect(HingeMove(start: 90, target: 100).duration == 0.35)
        #expect(HingeMove(start: 0, target: 90).duration == 0.5)
        #expect(HingeMove(start: 180, target: 0).duration == 1)
    }
}
