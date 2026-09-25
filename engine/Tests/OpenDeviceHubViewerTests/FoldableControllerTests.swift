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
    private var handoffs: [(String, Bool)] = []

    private func makeController(failing: Bool = false) -> FoldableController {
        let controller = FoldableController(open: { udid in
            self.opened.append(udid)
            if failing { throw EngineError.capabilityUnavailable(name: "hinge") }
            let hinge = FakeHinge()
            self.hinges[udid] = hinge
            return hinge
        })
        controller.onHandoff = { udid, unfolded in self.handoffs.append((udid, unfolded)) }
        controller.report = { _ in }
        return controller
    }

    /// The feature has to be turned on before the guest acts, so the first angle waits for that
    /// rather than being dropped.
    func testTheFirstAngleIsSentOnceTheFeatureIsOn() async throws {
        let controller = makeController()
        controller.setAngle(120, for: "A")

        XCTAssertEqual(hinges["A"]?.angles, [], "nothing should be sent before activation")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(hinges["A"]?.activations, 1)
        XCTAssertEqual(hinges["A"]?.angles, [120])
    }

    /// A slider moves many times while the feature is coming up, and the guest should end at the
    /// angle the user left it on, not the one they started from.
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

    /// The guest changes panel as the angle passes the threshold, and the window follows. Every
    /// other step of the slider is not a handoff and must not rebuild the window.
    func testHandoffReportsOnlyTheCrossing() async throws {
        let controller = makeController()
        controller.setAngle(0, for: "A")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(handoffs.isEmpty, "the first angle establishes the side, it is not a crossing")

        controller.setAngle(5, for: "A")
        controller.setAngle(14, for: "A")
        XCTAssertTrue(handoffs.isEmpty, "still below the threshold")

        controller.setAngle(20, for: "A")
        XCTAssertEqual(handoffs.count, 1)
        XCTAssertEqual(handoffs.first?.1, true)

        controller.setAngle(120, for: "A")
        controller.setAngle(180, for: "A")
        XCTAssertEqual(handoffs.count, 1, "staying open is not another crossing")

        controller.setAngle(0, for: "A")
        XCTAssertEqual(handoffs.count, 2)
        XCTAssertEqual(handoffs.last?.1, false)
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
}
