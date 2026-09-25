import Foundation
import OpenDeviceHubEngine

/// Holds the fold control for each open foldable, and notices when the guest changes panels.
///
/// The connection has to be turned on before the guest acts on anything, which takes a round trip,
/// so the first angle a window asks for is sent once that finishes rather than dropped.
@MainActor
public final class FoldableController {
    private let open: (String) throws -> any HingeControl
    private var controls: [String: any HingeControl] = [:]
    private var ready: Set<String> = []
    private var activating: Set<String> = []
    private var wanted: [String: Double] = [:]
    private var lastSide: [String: Bool] = [:]

    /// Called when the guest changes which panel it draws to, with true for the unfolded one. The
    /// window follows; the guest has already moved.
    public var onHandoff: ((String, Bool) -> Void)?
    public var report: ((String) -> Void)?

    public init(open: @escaping (String) throws -> any HingeControl) {
        self.open = open
    }

    /// The angle this device was last put at, or nil when it has not been touched in this session.
    public func angle(for udid: String) -> Double? {
        wanted[udid]
    }

    public func setAngle(_ degrees: Double, for udid: String) {
        wanted[udid] = degrees
        guard let control = control(for: udid) else { return }

        guard ready.contains(udid) else {
            // A slider sends many angles a second, and turning the feature on is a round trip, so
            // only the first starts it. The rest leave their angle behind and the one in flight
            // sends whichever is latest when it finishes.
            guard !activating.contains(udid) else { return }
            activating.insert(udid)
            Task { [weak self] in
                do {
                    try await control.activate()
                } catch {
                    self?.activating.remove(udid)
                    self?.report?("the hinge is unavailable: \(error.localizedDescription)")
                    return
                }
                guard let self else { return }
                activating.remove(udid)
                ready.insert(udid)
                send(wanted[udid] ?? degrees, to: control, for: udid)
            }
            return
        }
        send(degrees, to: control, for: udid)
    }

    public func forget(_ udid: String) {
        controls[udid] = nil
        ready.remove(udid)
        activating.remove(udid)
        wanted[udid] = nil
        lastSide[udid] = nil
    }

    private func send(_ degrees: Double, to control: any HingeControl, for udid: String) {
        do {
            try control.setHingeAngle(degrees)
        } catch {
            report?("the hinge did not move: \(error.localizedDescription)")
            return
        }
        noteHandoff(degrees, for: udid)
    }

    /// The guest moves its own picture at the threshold. This only reports the crossing, and only
    /// when it is a crossing rather than every slider step.
    private func noteHandoff(_ degrees: Double, for udid: String) {
        let unfolded = degrees >= FoldableControl.handoffAngle
        guard lastSide[udid] != unfolded else { return }
        let isFirst = lastSide[udid] == nil
        lastSide[udid] = unfolded
        guard !isFirst else { return }
        onHandoff?(udid, unfolded)
    }

    private func control(for udid: String) -> (any HingeControl)? {
        if let existing = controls[udid] { return existing }
        do {
            let made = try open(udid)
            controls[udid] = made
            return made
        } catch {
            report?("the hinge is unavailable: \(error.localizedDescription)")
            return nil
        }
    }
}
