import Foundation
import OpenDeviceHubEngine

/// The other screen of a foldable, held for the life of the window alongside the one it opened on.
/// Both are kept warm: the guest moves between them as it folds, and the window has to have the
/// picture already there when it does.
public struct FoldableCover {
    public let panel: DevicePanel
    public let session: any DisplaySession

    public init(panel: DevicePanel, session: any DisplaySession) {
        self.panel = panel
        self.session = session
    }
}
