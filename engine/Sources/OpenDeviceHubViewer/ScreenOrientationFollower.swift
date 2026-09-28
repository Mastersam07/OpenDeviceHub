import Foundation
import OpenDeviceHubEngine

/// Keeps each window turned the way its device's screen is, whoever turned the device.
///
/// A turn from the window itself is shown at once and taken back if the screen does not follow, so
/// the window shows what the screen shows whoever turned the device, and a window opened on a device
/// already turned shows it turned.
@MainActor
public final class ScreenOrientationFollower {
    private struct Following {
        let watcher: ScreenOrientationWatcher
        let tasks: [Task<Void, Never>]
    }

    private let read: @Sendable (String) async throws -> DisplayReport
    private let panels: (String) -> [DevicePanel]
    private var following: [String: Following] = [:]
    private var hinges: [String: Double] = [:]
    private var asked: [String: DeviceOrientation] = [:]
    /// Each change a device's screens announce, for anything else that watches them, such as a
    /// foldable's panel watcher. A screen's changes can only be listened to once.
    public var onScreenChange: ((String) -> Void)?

    public init(
        read: @escaping @Sendable (String) async throws -> DisplayReport,
        panels: @escaping (String) -> [DevicePanel]
    ) {
        self.read = read
        self.panels = panels
    }

    /// Again after the device comes back, since the window then has new screens to listen to.
    public func follow(_ udid: String, controller: DeviceWindowController) {
        forget(udid)
        let angles = Dictionary(panels(udid).map { ($0.screenID, $0.nativeRotation) }, uniquingKeysWith: { first, _ in first })
        let read = read
        let watcher = ScreenOrientationWatcher(
            read: { try await read(udid) },
            nativeRotation: { angles[$0] ?? 0 }
        )
        var tasks = controller.screenChanges.map { changes in
            Task { [weak self] in
                for await _ in changes {
                    watcher.poke()
                    self?.onScreenChange?(udid)
                }
            }
        }
        tasks.append(Task { [weak self, weak controller] in
            for await event in watcher.changes {
                guard let controller else { return }
                let orientation: DeviceOrientation
                switch event {
                case .turned(let turned):
                    orientation = turned
                    self?.asked[udid] = turned
                case .stillAt(let still):
                    orientation = still
                }
                if controller.currentOrientation != orientation {
                    controller.setOrientation(orientation)
                }
            }
        })
        following[udid] = Following(watcher: watcher, tasks: tasks)
        watcher.poke()
    }

    /// Where a rotate counts on from: the turn last asked for, or the screen's last turn, rather than
    /// what the window shows, so a turn the screen refuses (upside down on a Face ID phone) is passed
    /// on the next press instead of asked for again.
    public func lastTurn(_ udid: String) -> DeviceOrientation? {
        asked[udid]
    }

    /// The window asked the device to turn and shows it turned; the screen is checked once it has
    /// had time to follow.
    public func turned(_ udid: String, to orientation: DeviceOrientation) {
        asked[udid] = orientation
        following[udid]?.watcher.confirm()
    }

    /// A foldable's hinge is where it is shown: a move of a degree or more keeps the window from
    /// turning on what the report says while the fold goes through.
    public func hingeMoved(_ udid: String, to degrees: Double) {
        if let last = hinges[udid], abs(last - degrees) < 1 { return }
        hinges[udid] = degrees
        following[udid]?.watcher.holdStill()
    }

    public func forget(_ udid: String) {
        hinges[udid] = nil
        asked[udid] = nil
        guard let gone = following.removeValue(forKey: udid) else { return }
        for task in gone.tasks { task.cancel() }
        gone.watcher.close()
    }
}
