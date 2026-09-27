import Foundation
import OpenDeviceHubEngine

/// The foldable's other screen, kept warm alongside the one the window opened on.
public struct FoldableCover {
    public let panel: DevicePanel
    public let session: any DisplaySession

    public init(panel: DevicePanel, session: any DisplaySession) {
        self.panel = panel
        self.session = session
    }
}
