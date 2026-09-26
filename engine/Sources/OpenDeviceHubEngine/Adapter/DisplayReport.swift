import CoreGraphics
import Foundation
import XPC

/// What the guest says about its screens, right now.
///
/// This is the only honest answer to which panel of a foldable is in use. The hinge angle says
/// where the device should be and the framebuffers say what was last drawn; the report says which
/// screen the guest is laying out on. Device Hub reads the same report and trusts `active` when the
/// panel's backlight agrees with it.
public struct DisplayReport: Sendable, Hashable {
    public struct Display: Sendable, Hashable, Identifiable {
        public var id: String { uniqueID }
        public let uniqueID: String
        public let name: String
        /// The number a touch is addressed to, the same value the device type's profile calls the
        /// screen ID.
        public let displayID: Int
        public let isActive: Bool
        public let backlight: Backlight
        public let isPrimary: Bool
        public let isIntegrated: Bool
        public let pixelSize: CGSize
        public let pointScale: Int
        /// Clockwise, in degrees, how far the guest's layout on this screen is turned from the
        /// framebuffer right now.
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

    /// The one screen the guest is laying out on, or nil when the report cannot say. Two active
    /// integrated screens would mean the reading has stopped meaning anything, so that is nil too.
    public var activeIntegrated: Display? {
        let active = displays.filter { $0.isActive && $0.isIntegrated }
        return active.count == 1 ? active[0] : nil
    }

    /// The built in screens, which is all a window ever shows. The report also lists the guest's
    /// external and virtual displays.
    public var integrated: [Display] { displays.filter(\.isIntegrated) }

    /// Whether every screen's layout and backlight tell the same story. Mid fold they do not, for a
    /// moment: the guest moves its layout before a panel's backlight follows. Device Hub trusts the
    /// layout only when the backlight agrees, so a report that is not settled is one to wait on,
    /// not one to act on.
    public var isSettled: Bool {
        integrated.allSatisfy { display in
            switch display.backlight {
            case .activeOn, .activeDimmed: display.isActive
            case .off, .inactiveOn: !display.isActive
            case .unknown: true
            }
        }
    }

    public func display(withID displayID: Int) -> Display? {
        displays.first { $0.displayID == displayID }
    }

    static let maximumDisplays = 32

    /// Reads the output of the `displayinfo` action, refusing anything that does not hold together.
    /// A stale report, a duplicated identity, or an active screen without a size would each lead
    /// to trusting the wrong panel, which is worse than knowing nothing.
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
                // Layout is the authority when the report has it. The backlight can lag it mid
                // fold, which `isSettled` reports rather than this refusing the report.
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
