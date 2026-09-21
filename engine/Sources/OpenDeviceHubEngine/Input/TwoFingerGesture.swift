import CoreGraphics
import Foundation

/// Where two contacts sit for a pinch, a rotation or a two finger pan. Pure geometry, so the
/// gesture maths is tested without a device.
public enum TwoFingerGesture {
    /// Two contacts placed opposite each other about `centre`, `spread` apart along a line at
    /// `angle` radians. Coordinates are normalized and clamped to the screen.
    public static func contacts(
        centre: CGPoint,
        spread: CGFloat,
        angle: CGFloat
    ) -> [CGPoint] {
        let half = max(spread, 0) / 2
        let dx = cos(angle) * half
        let dy = sin(angle) * half
        return [
            clamp(CGPoint(x: centre.x + dx, y: centre.y + dy)),
            clamp(CGPoint(x: centre.x - dx, y: centre.y - dy)),
        ]
    }

    /// Both contacts moved together, which is a two finger pan rather than a pinch.
    public static func panned(
        contacts: [CGPoint],
        by offset: CGPoint
    ) -> [CGPoint] {
        contacts.map { clamp(CGPoint(x: $0.x + offset.x, y: $0.y + offset.y)) }
    }

    /// The opposite contact for an Option drag: the pointer is one finger and this is the other,
    /// mirrored through the centre of the screen, so moving the pointer pinches and rotates at once.
    public static func mirrored(_ point: CGPoint, about centre: CGPoint) -> CGPoint {
        clamp(CGPoint(x: 2 * centre.x - point.x, y: 2 * centre.y - point.y))
    }

    /// The second contact for an Option Shift drag, which keeps the offset captured when the
    /// gesture started so both fingers travel together.
    public static func offsetPartner(_ point: CGPoint, by offset: CGSize) -> CGPoint {
        clamp(CGPoint(x: point.x + offset.width, y: point.y + offset.height))
    }

    static func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }
}
