import Foundation
import OpenDeviceHubEngine

/// The active panel is never inferred from the angle sent: the guest reports it.
@MainActor
public final class FoldableController {
    private let open: (String) throws -> any HingeControl
    private let openHingeStream: ((String) throws -> HingeAngleStream)?
    private let readDisplays: (@Sendable (String) async throws -> DisplayReport)?
    private var controls: [String: any HingeControl] = [:]
    private var ready: Set<String> = []
    private var activating: Set<String> = []
    private var wanted: [String: Double] = [:]
    private var followers: [String: Follower] = [:]

    private struct Follower {
        let watcher: ActivePanelWatcher
        let hinge: HingeAngleStream?
        let task: Task<Void, Never>
    }

    public var report: ((String) -> Void)?

    public init(
        open: @escaping (String) throws -> any HingeControl,
        hingeStream: ((String) throws -> HingeAngleStream)? = nil,
        displayReport: (@Sendable (String) async throws -> DisplayReport)? = nil
    ) {
        self.open = open
        openHingeStream = hingeStream
        readDisplays = displayReport
    }

    public func angle(for udid: String) -> Double? {
        wanted[udid]
    }

    public func setAngle(_ degrees: Double, for udid: String) {
        wanted[udid] = degrees
        guard let control = control(for: udid) else { return }

        guard ready.contains(udid) else {
            // Activation is a round trip: the first angle starts it and the latest follows it.
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

    /// Turns a foldable, which only its own provider can do.
    public func setOrientation(_ orientation: DeviceOrientation, for udid: String) throws {
        guard let control = control(for: udid) else {
            throw EngineError.capabilityUnavailable(name: "hinge on \(udid)")
        }
        guard ready.contains(udid) else {
            Task { [weak self] in
                try? await control.activate()
                self?.ready.insert(udid)
                try? control.setOrientation(orientation)
                self?.followers[udid]?.watcher.poke()
            }
            return
        }
        try control.setOrientation(orientation)
        followers[udid]?.watcher.poke()
    }

    public func follow(
        _ udid: String,
        onPanel: @escaping @MainActor (DisplayReport.Display) -> Void,
        onHinge: @escaping @MainActor (Double) -> Void
    ) {
        guard followers[udid] == nil, let readDisplays else { return }
        let hinge: HingeAngleStream?
        do {
            hinge = try openHingeStream?(udid)
        } catch {
            report?("the hinge cannot be read back: \(error.localizedDescription)")
            hinge = nil
        }
        let watcher = ActivePanelWatcher(
            read: { try await readDisplays(udid) },
            hinge: hinge,
            onHinge: { sample in
                Task { @MainActor in onHinge(sample.degrees) }
            }
        )
        let task = Task { @MainActor in
            for await panel in watcher.changes {
                onPanel(panel)
            }
        }
        followers[udid] = Follower(watcher: watcher, hinge: hinge, task: task)
    }

    public func activePanel(for udid: String) -> DisplayReport.Display? {
        followers[udid]?.watcher.activePanel
    }

    public func forget(_ udid: String) {
        controls[udid] = nil
        ready.remove(udid)
        activating.remove(udid)
        wanted[udid] = nil
        if let follower = followers.removeValue(forKey: udid) {
            follower.task.cancel()
            follower.watcher.close()
            follower.hinge?.close()
        }
    }

    private func send(_ degrees: Double, to control: any HingeControl, for udid: String) {
        do {
            try control.setHingeAngle(degrees)
        } catch {
            report?("the hinge did not move: \(error.localizedDescription)")
            return
        }
        // The guest switches panels at its own threshold, so the watcher looks now.
        followers[udid]?.watcher.poke()
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
