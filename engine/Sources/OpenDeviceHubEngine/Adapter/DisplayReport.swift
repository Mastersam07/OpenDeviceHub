import CoreGraphics
import Foundation
import XPC

/// What the guest says about its screens, the only honest answer to which panel is in use. The
/// hinge says where the device should be and the framebuffers only what was last drawn.
public struct DisplayReport: Sendable, Hashable {
    public struct Display: Sendable, Hashable, Identifiable {
        public var id: String { uniqueID }
        public let uniqueID: String
        public let name: String
        /// The number a touch is addressed to, the device type profile's screen ID.
        public let displayID: Int
        public let isActive: Bool
        public let backlight: Backlight
        public let isPrimary: Bool
        public let isIntegrated: Bool
        public let pixelSize: CGSize
        public let pointScale: Int
        /// Clockwise degrees the guest's layout on this screen is turned from the framebuffer.
        public let currentRotation: Int
        /// How far the panel itself is built round in its housing.
        public let nativeRotation: Int
        public let chromeIdentifier: String?
    }

    public enum Backlight: String, Sendable, Hashable {
        case off
        case inactiveOn
        case activeOn
        case activeDimmed
        case unknown
    }

    public let displays: [Display]

    /// The screen the guest is laying out on. Two active ones mean the report cannot be trusted.
    public var activeIntegrated: Display? {
        let active = displays.filter { $0.isActive && $0.isIntegrated }
        return active.count == 1 ? active[0] : nil
    }

    /// The built in screens; the report also lists the guest's external and virtual displays.
    public var integrated: [Display] { displays.filter(\.isIntegrated) }

    /// Device Hub's rule: a report naming a panel whose backlight is off "cannot be right". The
    /// other panel's backlight lags for a few seconds after a fold, so it is not checked.
    public var isSettled: Bool {
        guard let active = activeIntegrated else { return false }
        switch active.backlight {
        case .activeOn, .activeDimmed, .unknown: return true
        case .off, .inactiveOn: return false
        }
    }

    public func display(withID displayID: Int) -> Display? {
        displays.first { $0.displayID == displayID }
    }

    static let maximumDisplays = 32

    /// Refuses a report that does not hold together: the wrong panel is worse than no panel.
    static func parse(_ output: xpc_object_t) throws -> DisplayReport {
        guard XPCValue.bool(output, "current") == true else {
            throw EngineError.privateCall(symbol: "displayinfo", message: "the report is not current")
        }
        guard let records = XPCValue.array(output, "displays") else {
            throw EngineError.privateCall(symbol: "displayinfo", message: "the report lists no displays")
        }
        guard records.count <= maximumDisplays else {
            throw EngineError.privateCall(symbol: "displayinfo", message: "the report lists too many displays")
        }
        let carriesLayoutActivity = records.contains { XPCValue.bool($0, "active") != nil }
        var seen: Set<String> = []
        var displays: [Display] = []
        for record in records {
            guard let uniqueID = XPCValue.string(record, "uniqueId"), !uniqueID.isEmpty,
                  seen.insert(uniqueID).inserted else {
                throw EngineError.privateCall(symbol: "displayinfo", message: "a display has no identity of its own")
            }
            let integrated = XPCValue.dictionary(record, "type").map {
                xpc_dictionary_get_value($0, "integrated") != nil
            } ?? false
            let backlight = Backlight(rawValue: XPCValue.string(record, "backlightState") ?? "") ?? .unknown
            let isActive: Bool
            if carriesLayoutActivity {
                // Layout is the authority when present; the backlight can lag it mid fold.
                guard let active = XPCValue.bool(record, "active") else {
                    throw EngineError.privateCall(symbol: "displayinfo", message: "a display has no activity")
                }
                isActive = active
            } else {
                switch backlight {
                case .activeOn, .activeDimmed: isActive = true
                case .off, .inactiveOn: isActive = false
                case .unknown:
                    throw EngineError.privateCall(symbol: "displayinfo", message: "a display's activity is unknown")
                }
            }

            let bounds = XPCValue.array(record, "bounds")?.compactMap { corner -> CGPoint? in
                guard let values = XPCValue.array(corner), values.count == 2,
                      let x = XPCValue.number(values[0]), let y = XPCValue.number(values[1]) else { return nil }
                return CGPoint(x: x, y: y)
            } ?? []
            let size: CGSize = bounds.count == 2
                ? CGSize(width: bounds[1].x - bounds[0].x, height: bounds[1].y - bounds[0].y)
                : .zero
            guard !isActive || (size.width > 0 && size.height > 0) else {
                throw EngineError.privateCall(symbol: "displayinfo", message: "the active display has no size")
            }

            displays.append(Display(
                uniqueID: uniqueID,
                name: XPCValue.string(record, "name") ?? "",
                displayID: Int(XPCValue.number(record, "displayId") ?? 0),
                isActive: isActive,
                backlight: backlight,
                isPrimary: XPCValue.bool(record, "primary") ?? false,
                isIntegrated: integrated,
                pixelSize: size,
                pointScale: Int(XPCValue.number(record, "pointScale") ?? 1),
                currentRotation: Self.degrees(XPCValue.string(record, "currentOrientation")),
                nativeRotation: Self.degrees(XPCValue.string(record, "nativeOrientation")),
                chromeIdentifier: XPCValue.string(record, "chromeIdentifier")
            ))
        }
        return DisplayReport(displays: displays)
    }

    /// The report writes a rotation as `rot0`, `rot90`, `rot180` or `rot270`.
    static func degrees(_ rotation: String?) -> Int {
        guard let rotation, rotation.hasPrefix("rot"), let value = Int(rotation.dropFirst(3)) else { return 0 }
        return ((value % 360) + 360) % 360
    }
}
