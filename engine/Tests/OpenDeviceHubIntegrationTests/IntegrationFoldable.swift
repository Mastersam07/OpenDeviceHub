import Foundation
import OpenDeviceHubEngine

/// One hinge control per device for the whole run: each new vendor connection answers more slowly
/// than the last and the fourth times out (27A266a: 1.1s, 7.9s, 8.1s, then a timeout).
actor IntegrationFoldable {
    static let shared = IntegrationFoldable()
    private var controls: [String: any HingeControl] = [:]

    func control(for udid: String, adapter: any SimulatorAdapter) async throws -> any HingeControl {
        if let existing = controls[udid] { return existing }
        let made = try adapter.openFoldableControl(udid)
        try await made.activate()
        controls[udid] = made
        return made
    }
}
