import CoreGraphics

/// One of a device's built in screens.
///
/// Most devices have exactly one. A foldable has two, both live at the same time, and which one the
/// guest is drawing to depends on how far it is folded.
public struct DevicePanel: Sendable, Hashable, Identifiable {
    /// The IO port's own UUID, stable for the life of the boot.
    public let id: String
    public let index: Int
    public let name: String
    public let pixelSize: CGSize
    /// Whether this is the panel the device type calls its main screen. On a foldable that is the
    /// cover, not the larger one.
    public let isMainScreen: Bool
    /// Where a touch on this panel is addressed. Zero is the device's default screen, which is what
    /// every ordinary device uses.
    public let screenID: Int
    /// How far the panel is turned in its housing. A foldable's unfolded panel is built sideways, so
    /// its picture has to be turned by this much on top of whatever the guest is doing.
    public let nativeRotation: Int
    /// The body Apple draws around this panel. A foldable's two panels declare different ones, and
    /// drawing the cover's body around the unfolded screen puts every button in the wrong place.
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

    /// Names a set of panels once they are all known, since a name only means something in context:
    /// one screen needs no name, and two are told apart by which is the larger.
    ///
    /// Only a foldable has two built in panels today, so the larger is the unfolded screen and the
    /// smaller the cover. Anything beyond two is numbered rather than guessed at.
    public static func name(at index: Int, of sizes: [CGSize]) -> String {
        guard sizes.count > 1 else { return "Screen" }
        guard sizes.count == 2 else { return "Screen \(index + 1)" }
        let area = { (size: CGSize) in size.width * size.height }
        let other = sizes[1 - index]
        if area(sizes[index]) == area(other) { return "Screen \(index + 1)" }
        return area(sizes[index]) > area(other) ? "Unfolded" : "Cover"
    }
}
