import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

private final class FakeHinge: HingeControl, @unchecked Sendable {
    var activations = 0
    var angles: [Double] = []
    var orientations: [DeviceOrientation] = []
    var refusesToActivate = false

    func activate() async throws {
        activations += 1
        if refusesToActivate {
            throw EngineError.capabilityUnavailable(name: "hinge")
        }
    }

    func setHingeAngle(_ degrees: Double) throws { angles.append(degrees) }
    func setOrientation(_ orientation: DeviceOrientation) throws { orientations.append(orientation) }
}

@MainActor
final class FoldableControllerTests: XCTestCase {
    private var hinges: [String: FakeHinge] = [:]
    private var opened: [String] = []

    private func makeController(failing: Bool = false) -> FoldableController {
        let controller = FoldableController(open: { udid in
            self.opened.append(udid)
            if failing { throw EngineError.capabilityUnavailable(name: "hinge") }
            let hinge = FakeHinge()
            self.hinges[udid] = hinge
            return hinge
        })
        controller.report = { _ in }
        controller.reducesMotion = { false }
        return controller
    }

    func testTheFirstAngleIsSentOnceTheFeatureIsOn() async throws {
        let controller = makeController()
        controller.setAngle(120, for: "A")

        XCTAssertEqual(hinges["A"]?.angles, [], "nothing should be sent before activation")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(hinges["A"]?.activations, 1)
        XCTAssertEqual(hinges["A"]?.angles, [120])
    }

    func testTheLatestAngleWinsWhileActivating() async throws {
        let controller = makeController()
        controller.setAngle(30, for: "A")
        controller.setAngle(90, for: "A")
        controller.setAngle(180, for: "A")

        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(hinges["A"]?.angles, [180])
        XCTAssertEqual(hinges["A"]?.activations, 1, "activation should happen once")
    }

    func testOneConnectionPerDeviceHoweverManyAngles() async throws {
        let controller = makeController()
        controller.setAngle(10, for: "A")
        try await Task.sleep(for: .milliseconds(120))
        controller.setAngle(20, for: "A")
        controller.setAngle(30, for: "A")

        XCTAssertEqual(opened, ["A"])
        XCTAssertEqual(hinges["A"]?.angles, [10, 20, 30])
    }

    func testForgettingADeviceDropsItsConnection() async throws {
        let controller = makeController()
        controller.setAngle(90, for: "A")
        try await Task.sleep(for: .milliseconds(120))
        controller.forget("A")
        controller.setAngle(90, for: "A")

        XCTAssertEqual(opened, ["A", "A"])
        XCTAssertEqual(controller.angle(for: "A"), 90)
    }

    /// A device whose hinge cannot be reached still shows, so nothing here is allowed to throw.
    func testADeviceThatCannotConnectIsSkipped() {
        let controller = makeController(failing: true)
        controller.setAngle(90, for: "A")
        XCTAssertEqual(controller.angle(for: "A"), 90)
    }

    /// The window is shown the same run the guest is given, rather than jumping ahead of it.
    func testAPresetEasesTheHingeThroughARun() async throws {
        let controller = makeController()
        var drawn: [Double] = []
        var events: [HingeMoveEvent] = []
        controller.onMove = { _, event in
            events.append(event)
            if case .angle(let angle) = event { drawn.append(angle) }
        }
        controller.setAngle(180, for: "A")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(hinges["A"]?.angles, [180])

        controller.setAngle(0, for: "A", eased: true)
        try await Task.sleep(for: .milliseconds(1400))
        let sent = try XCTUnwrap(hinges["A"]?.angles.dropFirst())
        // A slow machine steps less often; the move still takes its second and keeps its shape.
        XCTAssertGreaterThan(sent.count, 4, "a run of angles, not one")
        XCTAssertEqual(sent.first, 180, "starting where it was")
        XCTAssertEqual(sent.last, 0, "ending on the preset")
        XCTAssertEqual(Array(sent), sent.sorted(by: >), "never turning back")
        XCTAssertEqual(drawn, Array(sent), "the window is shown the same run")
        XCTAssertEqual(events.first, .began(target: 0))
        XCTAssertEqual(events.last, .ended)
    }

    func testReduceMotionJumpsToThePreset() async throws {
        let controller = makeController()
        controller.reducesMotion = { true }
        controller.setAngle(180, for: "A")
        try await Task.sleep(for: .milliseconds(120))
        controller.setAngle(0, for: "A", eased: true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(hinges["A"]?.angles, [180, 0], "one send, no run")
    }

    /// A pinch during a move takes over from where the fold visibly is, and the move stops.
    func testAPinchDuringAMoveTakesOverWhereTheFoldIs() async throws {
        let controller = makeController()
        controller.setAngle(180, for: "A")
        try await Task.sleep(for: .milliseconds(120))
        controller.setAngle(0, for: "A", eased: true)
        try await Task.sleep(for: .milliseconds(300))
        let underway = try XCTUnwrap(hinges["A"]?.angles.last)
        XCTAssertLessThan(underway, 180)
        XCTAssertGreaterThan(underway, 0)

        controller.setAngle(90, for: "A")
        let count = hinges["A"]?.angles.count
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(hinges["A"]?.angles.last, 90)
        XCTAssertEqual(hinges["A"]?.angles.count, count, "nothing more was sent after the pinch")
    }
}

