import AppKit
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
    /// The last angle sent, or between moves the last the guest reported.
    private var shown: [String: Double] = [:]
    private var moves: [String: Task<Void, Never>] = [:]
    private var followers: [String: Follower] = [:]

    private struct Follower {
        let watcher: ActivePanelWatcher
        let hinge: HingeAngleStream?
        let tasks: [Task<Void, Never>]
    }

    public var report: ((String) -> Void)?
    /// Each angle a move passes through, so the window draws the same fold the guest is given.
    public var onAngle: ((String, Double) -> Void)?

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

    /// Eased, the hinge is walked there over a moment; otherwise sent at once, as a pinch wants.
    public func setAngle(_ degrees: Double, for udid: String, eased: Bool = false) {
        wanted[udid] = degrees
        moves.removeValue(forKey: udid)?.cancel()
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
        guard eased, let start = shown[udid], abs(start - degrees) > 0.1,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            send(degrees, to: control, for: udid)
            return
        }
        move(HingeMove(start: start, target: degrees), on: control, for: udid)
    }

    private func move(_ move: HingeMove, on control: any HingeControl, for udid: String) {
        followers[udid]?.watcher.poke()
        let task = Task { @MainActor [weak self] in
            let started = ContinuousClock.now
            while !Task.isCancelled {
                let elapsed = ContinuousClock.now - started
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let progress = min(1, seconds / move.duration)
                let angle = move.angle(at: progress)
                guard let self else { return }
                send(angle, to: control, for: udid, poke: false)
                onAngle?(udid, angle)
                if progress >= 1 { break }
                try? await Task.sleep(for: HingeMove.stepInterval)
            }
            guard let self, !Task.isCancelled else { return }
            moves[udid] = nil
            followers[udid]?.watcher.poke()
        }
        moves[udid] = task
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

    /// `nudges` are the panels' own change announcements; each makes the watcher look at once.
    public func follow(
        _ udid: String,
        nudges: [AsyncStream<ScreenProperties>] = [],
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
            onHinge: { [weak self] sample in
                Task { @MainActor in
                    // While a move runs, the stream only echoes what was just sent.
                    guard let self, self.moves[udid] == nil else { return }
                    self.shown[udid] = sample.degrees
                    onHinge(sample.degrees)
                }
            }
        )
        var tasks = [Task { @MainActor in
            for await panel in watcher.changes {
                onPanel(panel)
            }
        }]
        for nudge in nudges {
            tasks.append(Task {
                for await _ in nudge {
                    watcher.poke()
                }
            })
        }
        followers[udid] = Follower(watcher: watcher, hinge: hinge, tasks: tasks)
    }

    public func activePanel(for udid: String) -> DisplayReport.Display? {
        followers[udid]?.watcher.activePanel
    }

    public func forget(_ udid: String) {
        moves.removeValue(forKey: udid)?.cancel()
        shown[udid] = nil
        controls[udid] = nil
        ready.remove(udid)
        activating.remove(udid)
        wanted[udid] = nil
        if let follower = followers.removeValue(forKey: udid) {
            for task in follower.tasks { task.cancel() }
            follower.watcher.close()
            follower.hinge?.close()
        }
    }

    private func send(_ degrees: Double, to control: any HingeControl, for udid: String, poke: Bool = true) {
        do {
            try control.setHingeAngle(degrees)
        } catch {
            report?("the hinge did not move: \(error.localizedDescription)")
            return
        }
        shown[udid] = degrees
        // The guest switches panels at its own threshold, so the watcher looks now.
        if poke { followers[udid]?.watcher.poke() }
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
