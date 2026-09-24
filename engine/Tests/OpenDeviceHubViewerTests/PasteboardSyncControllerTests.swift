import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

private final class FakeSession: PasteboardSession, @unchecked Sendable {
    var isAutomatic = false
    var sends = 0
    var gets = 0
    var reconciles = 0

    func setAutomatic(_ enabled: Bool) { isAutomatic = enabled }
    func send() { sends += 1 }
    func get() { gets += 1 }
    func reconcile() { reconciles += 1 }
}

@MainActor
final class PasteboardSyncControllerTests: XCTestCase {
    private var sessions: [String: FakeSession] = [:]
    private var opened: [String] = []
    private var open: [String] = []
    private var front: String?

    private func makeController(isAutomatic: Bool) -> PasteboardSyncController {
        PasteboardSyncController(
            isAutomatic: isAutomatic,
            devices: { self.open },
            frontmost: { self.front },
            open: { udid in
                self.opened.append(udid)
                let session = FakeSession()
                self.sessions[udid] = session
                return session
            }
        )
    }

    func testAdoptingStartsTheSyncOnlyWhenItIsOn() {
        open = ["a"]
        let off = makeController(isAutomatic: false)
        off.adopt("a")
        XCTAssertTrue(opened.isEmpty)

        let on = makeController(isAutomatic: true)
        on.adopt("a")
        XCTAssertEqual(sessions["a"]?.isAutomatic, true)
    }

    func testTurningItOnReachesEveryOpenDevice() {
        open = ["a", "b"]
        let controller = makeController(isAutomatic: false)
        controller.setAutomatic(true)

        XCTAssertTrue(controller.isAutomatic)
        XCTAssertEqual(sessions["a"]?.isAutomatic, true)
        XCTAssertEqual(sessions["b"]?.isAutomatic, true)
    }

    func testSendingReachesEveryOpenDeviceAndGettingOnlyTheFrontOne() {
        open = ["a", "b"]
        front = "b"
        let controller = makeController(isAutomatic: true)
        controller.send()
        controller.get()

        XCTAssertEqual(sessions["a"]?.sends, 1)
        XCTAssertEqual(sessions["b"]?.sends, 1)
        XCTAssertEqual(sessions["a"]?.gets, 0)
        XCTAssertEqual(sessions["b"]?.gets, 1)
    }

    func testOneConnectionPerDeviceHoweverManyActions() {
        open = ["a"]
        let controller = makeController(isAutomatic: true)
        controller.send()
        controller.send()
        front = "a"
        controller.get()

        XCTAssertEqual(opened, ["a"])
    }

    func testResignActiveOnlyReconcilesWhileTheSyncIsOn() {
        open = ["a"]
        front = "a"
        let off = makeController(isAutomatic: false)
        off.reconcileOnResignActive()
        XCTAssertTrue(opened.isEmpty)

        let on = makeController(isAutomatic: true)
        on.reconcileOnResignActive()
        XCTAssertEqual(sessions["a"]?.reconciles, 1)
    }

    func testForgettingADeviceStopsItsSyncAndDropsTheConnection() {
        open = ["a"]
        let controller = makeController(isAutomatic: true)
        controller.adopt("a")
        let session = sessions["a"]
        controller.forget("a")

        XCTAssertEqual(session?.isAutomatic, false)
        controller.send()
        XCTAssertEqual(opened, ["a", "a"])
    }

    /// A device whose clipboard cannot be reached still shows, so the failure has to be swallowed.
    func testADeviceThatCannotConnectIsSkipped() {
        open = ["a"]
        front = "a"
        let controller = PasteboardSyncController(
            isAutomatic: true,
            devices: { self.open },
            frontmost: { self.front },
            open: { _ in throw EngineError.capabilityUnavailable(name: "pasteboard sync") }
        )
        controller.setAutomatic(true)
        controller.send()
        controller.get()
        controller.reconcileOnResignActive()
    }
}
