public struct Capabilities: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let display = Capabilities(rawValue: 1 << 0)
    public static let touch = Capabilities(rawValue: 1 << 1)
    public static let multiTouch = Capabilities(rawValue: 1 << 2)
    public static let keyboard = Capabilities(rawValue: 1 << 3)
    public static let hardwareButtons = Capabilities(rawValue: 1 << 4)
    public static let memoryWarning = Capabilities(rawValue: 1 << 5)
    public static let slowAnimations = Capabilities(rawValue: 1 << 6)
    public static let shake = Capabilities(rawValue: 1 << 7)
    public static let biometrics = Capabilities(rawValue: 1 << 8)
    public static let pointer = Capabilities(rawValue: 1 << 9)
    public static let rotation = Capabilities(rawValue: 1 << 10)
    public static let deviceNotifications = Capabilities(rawValue: 1 << 11)
    public static let hardwareKeyboard = Capabilities(rawValue: 1 << 12)
    public static let pasteboardSync = Capabilities(rawValue: 1 << 13)
}

extension Capabilities {
    public static let known: [(name: String, capability: Capabilities)] = [
        ("display", .display),
        ("touch", .touch),
        ("multiTouch", .multiTouch),
        ("keyboard", .keyboard),
        ("hardwareButtons", .hardwareButtons),
        ("hardwareKeyboard", .hardwareKeyboard),
        ("memoryWarning", .memoryWarning),
        ("slowAnimations", .slowAnimations),
        ("shake", .shake),
        ("biometrics", .biometrics),
        ("pointer", .pointer),
        ("rotation", .rotation),
        ("deviceNotifications", .deviceNotifications),
    ]

    public var names: [String] {
        Capabilities.known.filter { contains($0.capability) }.map(\.name)
    }
}
