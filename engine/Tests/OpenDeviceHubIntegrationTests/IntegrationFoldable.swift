import Foundation
import OpenDeviceHubEngine

/// One hinge control per device for the whole test run.
///
/// A fresh one for every test does not hold up: each new connection to the guest's vendor service
/// answers more slowly than the last, and around the fourth it stops answering at all. Measured on
/// 27A266a by opening and turning on six in a row: 1.1s, 7.9s, 8.1s, then a timeout. The app keeps
/// one per device for as long as its window is open, so this is also how it is really used.
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
