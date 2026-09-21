import XCTest

enum IntegrationGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["ODH_INTEGRATION"] == "1"
    }

    static func requireEnabled() throws {
        try XCTSkipUnless(isEnabled, "Set ODH_INTEGRATION=1 to run tests that need a real simulator.")
    }
}
