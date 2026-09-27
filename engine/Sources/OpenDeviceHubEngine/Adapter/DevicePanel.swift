import CoreGraphics

/// One of a device's built in screens. A foldable has two, both live at the same time.
public struct DevicePanel: Sendable, Hashable, Identifiable {
    /// The IO port's own UUID, stable for the life of the boot.
    public let id: String
    public let index: Int
    public let name: String
    public let pixelSize: CGSize
    /// The panel the device type calls its main screen: a foldable's cover, not its larger panel.
    public let isMainScreen: Bool
    /// Where a touch on this panel is addressed; zero is the device's default screen.
    public let screenID: Int
    /// How far the panel is built turned in its housing; a foldable's unfolded panel is sideways.
    public let nativeRotation: Int
    /// The body drawn around this panel; a foldable's two panels declare different ones.
    public let chromeIdentifier: String?

    public init(
        id: String,
        index: Int,
        name: String,
        pixelSize: CGSize,
        isMainScreen: Bool,
        screenID: Int = 0,
        nativeRotation: Int = 0,
        chromeIdentifier: String? = nil
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.pixelSize = pixelSize
        self.isMainScreen = isMainScreen
        self.screenID = screenID
        self.nativeRotation = nativeRotation
        self.chromeIdentifier = chromeIdentifier
    }

    /// Names a panel once all are known: one needs no name, two are told apart by size.
    public static func name(at index: Int, of sizes: [CGSize]) -> String {
        guard sizes.count > 1 else { return "Screen" }
        guard sizes.count == 2 else { return "Screen \(index + 1)" }
        let area = { (size: CGSize) in size.width * size.height }
        let other = sizes[1 - index]
        if area(sizes[index]) == area(other) { return "Screen \(index + 1)" }
        return area(sizes[index]) > area(other) ? "Unfolded" : "Cover"
    }
}
