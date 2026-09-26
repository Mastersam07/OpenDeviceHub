import CoreGraphics
import Foundation
import Testing
@testable import OpenDeviceHubEngine

private final class RecordingSession: InputSession, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TouchEvent] = []

    var events: [TouchEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func touch(_ event: TouchEvent) async throws {
        add(event)
    }

    // Swift 6 will not let a lock be taken directly in an async function.
    private func add(_ event: TouchEvent) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(event)
    }

    func key(_ event: KeyEvent) async throws {}
    func button(_ button: HardwareButton, phase: ButtonPhase) async throws {}
    func close() {}
}

@Suite struct SystemGestureTests {
    @Test func goesUpFromTheBottomWhenTheGuestIsUpright() async throws {
        let session = RecordingSession()
        try await SystemGesture.home(on: session, turn: .portrait, stepMilliseconds: 0)

        let events = session.events
        let first = try #require(events.first)
        #expect(first.phase == .began)
        #expect(first.edge == .bottom)
        #expect(first.points[0].y > 0.99)
        #expect(events.last?.phase == .ended)
        #expect(events.allSatisfy { $0.edge == .bottom })
        // Straight up the middle, and every contact stays on the screen.
        #expect(events.allSatisfy { abs($0.points[0].x - 0.5) < 0.001 })
        #expect(events.allSatisfy { (0...1).contains($0.points[0].y) })
    }

    /// A panel built sideways puts the home indicator along the framebuffer's right edge, so both
    /// the points and the edge have to come out turned. Measured on 27A266a against the unfolded
    /// panel of a foldable, where no other edge goes home.
    @Test func turnsWithTheGuestsOwnLayout() async throws {
        let session = RecordingSession()
        try await SystemGesture.home(on: session, turn: .landscapeLeft, stepMilliseconds: 0)

        let events = session.events
        #expect(events.allSatisfy { $0.edge == .right })
        let first = try #require(events.first)
        #expect(first.points[0].x > 0.99)
        #expect(abs(first.points[0].y - 0.5) < 0.001)
        // Travelling up the guest's screen is travelling back along the framebuffer's x.
        let last = try #require(events.last)
        #expect(last.points[0].x < first.points[0].x)
    }

    @Test func theAppSwitcherComesToRestBeforeItLifts() async throws {
        let session = RecordingSession()
        try await SystemGesture.appSwitcher(on: session, turn: .portrait, stepMilliseconds: 0)

        let events = session.events
        let moves = events.filter { $0.phase == .moved }
        let travel = moves.prefix(while: { $0.points[0].y > 0.61 })
        #expect(!travel.isEmpty)
        // After the travel the contact keeps moving, but only around where it stopped, which is what
        // the guest reads as a rest rather than a flick.
        let resting = moves.dropFirst(travel.count)
        #expect(resting.count >= 15)
        #expect(resting.allSatisfy { abs($0.points[0].y - 0.6) < 0.01 })
        #expect(events.last?.phase == .ended)
    }

    @Test func aHomeSwipeNeverRests() async throws {
        let session = RecordingSession()
        try await SystemGesture.home(on: session, turn: .portrait, stepMilliseconds: 0)

        let moves = session.events.filter { $0.phase == .moved }
        let steps = zip(moves, moves.dropFirst()).map { abs($1.points[0].y - $0.points[0].y) }
        #expect(steps.allSatisfy { $0 > 0.01 })
    }
}
