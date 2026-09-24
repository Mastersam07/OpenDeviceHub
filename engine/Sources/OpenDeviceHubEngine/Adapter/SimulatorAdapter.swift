import CoreGraphics
import Foundation
import IOSurface

public enum DeviceState: String, Sendable, Codable {
    case shutdown
    case booting
    case booted
    case shuttingDown
    case unknown
}

public struct DeviceInfo: Sendable, Hashable, Codable {
    public let udid: String
    public let name: String
    public let deviceTypeIdentifier: String
    public let runtimeIdentifier: String
    public let runtimeName: String
    public let state: DeviceState
    public let isAvailable: Bool

    public init(
        udid: String,
        name: String,
        deviceTypeIdentifier: String,
        runtimeIdentifier: String,
        runtimeName: String,
        state: DeviceState,
        isAvailable: Bool
    ) {
        self.udid = udid
        self.name = name
        self.deviceTypeIdentifier = deviceTypeIdentifier
        self.runtimeIdentifier = runtimeIdentifier
        self.runtimeName = runtimeName
        self.state = state
        self.isAvailable = isAvailable
    }
}

public struct DisplayFrame: @unchecked Sendable {
    public let surface: IOSurfaceRef
    public let timestamp: UInt64

    public init(surface: IOSurfaceRef, timestamp: UInt64) {
        self.surface = surface
        self.timestamp = timestamp
    }
}

public struct TouchEvent: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        case began
        case moved
        case ended
        case cancelled
    }

    /// Which screen edge a contact started at. The guest recognises its system gestures, the home
    /// indicator swipe and the notification pull, from this rather than from the coordinates, so a
    /// swipe that merely begins near the edge does not trigger them.
    public enum Edge: Sendable, Hashable {
        case none
        case top
        case left
        case bottom
        case right
    }

    public let phase: Phase
    /// One or two points, normalized 0...1 in the device's portrait native coordinate space.
    public let points: [CGPoint]
    public let edge: Edge

    public init(phase: Phase, points: [CGPoint], edge: Edge = .none) {
        self.phase = phase
        self.points = points
        self.edge = edge
    }
}

public struct KeyEvent: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        case down
        case up
    }

    public let phase: Phase
    /// HID usage from the keyboard usage page, not a macOS virtual keycode.
    public let usage: UInt32

    public init(phase: Phase, usage: UInt32) {
        self.phase = phase
        self.usage = usage
    }
}

public enum HardwareButton: Sendable, Hashable {
    case home
    case lock
    case volumeUp
    case volumeDown
    case siri
    case actionButton
}

public enum ButtonPhase: Sendable, Hashable {
    case down
    case up
}

public protocol DisplaySession: AnyObject, Sendable {
    var frames: AsyncStream<DisplayFrame> { get }
    var pixelSize: CGSize { get }
    var pointScale: CGFloat { get }
    /// The device screen's physical pixel density, which physical size scaling needs.
    var pixelsPerInch: CGFloat? { get }
    /// Whether the device offers a bezel, its own screen shape with rounded corners and any cutout.
    var supportsBezel: Bool { get }
    /// Shows the device's bezel, or the raw rectangular framebuffer. Does nothing when the device
    /// does not offer one.
    func setBezelEnabled(_ enabled: Bool)
    func close()
}

public protocol InputSession: AnyObject, Sendable {
    func touch(_ event: TouchEvent) async throws
    func key(_ event: KeyEvent) async throws
    func button(_ button: HardwareButton, phase: ButtonPhase) async throws
    func close()
}

public protocol SimulatorAdapter: Sendable {
    var xcode: XcodeInstall { get }
    var capabilities: Capabilities { get }
    func devices() throws -> [DeviceInfo]
    func openDisplay(_ udid: String) throws -> any DisplaySession
    func openInput(_ udid: String) throws -> any InputSession
    func simulateMemoryWarning(_ udid: String) throws
    /// Turns the device itself, which makes the guest re-lay out. The viewer still has to turn its
    /// own view to match, since the framebuffer stays portrait native.
    func setOrientation(_ orientation: DeviceOrientation, udid: String) throws
    /// Connects or disconnects the Mac's keyboard as the device's hardware keyboard.
    func setHardwareKeyboardEnabled(_ enabled: Bool, udid: String) throws
    /// Points the guest's keyboard at a language, for example "en-US".
    func setKeyboardLanguage(_ language: String, udid: String) throws
    /// Watches every device in the set, so a window learns that its device has gone or come back
    /// without asking.
    func watchDeviceStates() throws -> any DeviceNotifier
}

extension DeviceState {
    /// The numeric values were observed on Xcode 26.5 (17F42) by polling a real boot and shutdown
    /// cycle. Anything else falls back to the device's own state string, which both CoreSimulator
    /// and simctl report.
    public static func from(state: UInt, stateString: String) -> DeviceState {
        switch state {
        case 1: .shutdown
        case 2: .booting
        case 3: .booted
        case 4: .shuttingDown
        default: from(stateString: stateString)
        }
    }

    public static func from(stateString: String) -> DeviceState {
        switch stateString.lowercased().filter({ !$0.isWhitespace }) {
        case "shutdown": .shutdown
        case "booting": .booting
        case "booted": .booted
        case "shuttingdown": .shuttingDown
        default: .unknown
        }
    }
}
