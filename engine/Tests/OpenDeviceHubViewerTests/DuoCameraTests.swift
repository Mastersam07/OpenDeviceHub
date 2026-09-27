import Foundation
import simd
import Testing
@testable import OpenDeviceHubViewer

@Suite struct DuoCameraTests {
    private let flatOn = simd_normalize(SIMD3<Float>(0, 1, 0))

    @Test func looksAtTheDeviceTheRightWayUpWhenItIsUpright() {
        let up = DuoModelView.cameraUp(quarterTurns: 0, direction: flatOn)
        #expect(simd_length(up - SIMD3<Float>(0, 0, -1)) < 0.001)
    }

    @Test func rollsWithTheDevice() {
        let direction = flatOn
        let turns = (0..<4).map { DuoModelView.cameraUp(quarterTurns: $0, direction: direction) }
        for (before, after) in zip(turns, turns.dropFirst()) {
            #expect(abs(simd_dot(before, after)) < 0.001)
        }
        #expect(simd_length(turns[0] + turns[2]) < 0.001)
        #expect(simd_length(turns[1] + turns[3]) < 0.001)
        #expect(turns.allSatisfy { abs(simd_dot($0, direction)) < 0.001 })
    }

    @Test func wrapsRatherThanRunningOffTheEnd() {
        #expect(DuoModelView.cameraUp(quarterTurns: 4, direction: flatOn)
            == DuoModelView.cameraUp(quarterTurns: 0, direction: flatOn))
        #expect(DuoModelView.cameraUp(quarterTurns: -1, direction: flatOn)
            == DuoModelView.cameraUp(quarterTurns: 3, direction: flatOn))
    }

    /// The camera orbits round to the cover as the device shuts.
    @Test func staysSquareToAnOrbitedCamera() {
        let direction = simd_normalize(SIMD3<Float>(0.7, 0.7, 0))
        for turns in 0..<4 {
            let up = DuoModelView.cameraUp(quarterTurns: turns, direction: direction)
            #expect(abs(simd_length(up) - 1) < 0.001)
            #expect(abs(simd_dot(up, direction)) < 0.001)
        }
    }
}
