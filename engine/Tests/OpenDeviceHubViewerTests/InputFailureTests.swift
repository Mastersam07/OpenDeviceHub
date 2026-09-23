import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// The rule that decides whether a failed send means the window has lost its device or only that
/// the guest would not take that particular gesture. Getting it the wrong way round either hides a
/// dead session or tears a working window down over an unsupported pinch.
final class InputFailureTests: XCTestCase {
    func testARefusedGestureLeavesTheSessionAlone() {
        XCTAssertFalse(InputFailure.endsTheSession(
            EngineError.capabilityUnavailable(name: "touch phase cancelled")
        ))
        XCTAssertFalse(InputFailure.endsTheSession(
            EngineError.capabilityUnavailable(name: "hardware button siri")
        ))
    }

    func testACancelledTaskIsNotAFailure() {
        XCTAssertFalse(InputFailure.endsTheSession(CancellationError()))
    }

    func testAClosedSessionEndsIt() {
        XCTAssertTrue(InputFailure.endsTheSession(EngineError.inputSessionClosed))
    }

    func testAFailedPrivateCallEndsIt() {
        XCTAssertTrue(InputFailure.endsTheSession(
            EngineError.privateCall(symbol: "sendWithMessage:", message: "device not found")
        ))
    }

    func testAnUnrecognisedErrorEndsIt() {
        struct Unknown: Error {}
        XCTAssertTrue(
            InputFailure.endsTheSession(Unknown()),
            "an error we do not recognise is treated as fatal rather than swallowed"
        )
    }

    func testTheMessageLeadsWithWhatItMeans() {
        let message = InputFailure.message(for: EngineError.inputSessionClosed)
        XCTAssertTrue(message.hasPrefix("Input stopped reaching the device."))
        XCTAssertTrue(message.contains("The input session is closed."))
    }
}
