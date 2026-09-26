import CoreGraphics
import Foundation

/// The swipes up from the bottom edge, sent to a device.
///
/// The paths are written in the space the guest lays its interface out in. That is not the space the
/// digitizer is addressed in unless the device is upright and its panel is built square into the
/// housing, so both the points and the edge the contact starts at are converted by `turn`, which is
/// how far the guest's layout is turned from the framebuffer.
public enum SystemGesture {
    public static func home(
        on session: any InputSession,
        turn: DeviceOrientation = .portrait,
        stepMilliseconds: Int = 10
    ) async throws {
        try await stroke(
            HomeGesture.swipePath(),
            on: session,
            turn: turn,
            stepMilliseconds: stepMilliseconds,
            restsAtEnd: false
        )
    }

    public static func appSwitcher(
        on session: any InputSession,
        turn: DeviceOrientation = .portrait,
        stepMilliseconds: Int = 10
    ) async throws {
        try await stroke(
            HomeGesture.appSwitcherPath(),
            on: session,
            turn: turn,
            stepMilliseconds: stepMilliseconds,
            restsAtEnd: true
        )
    }

    private static func stroke(
        _ path: [CGPoint],
        on session: any InputSession,
        turn: DeviceOrientation,
        stepMilliseconds: Int,
        restsAtEnd: Bool
    ) async throws {
        guard let finish = path.last else { return }
        let points = native(path, turn)
        // The guest reads the edge from the framebuffer, not from what the window shows, so this is
        // taken after the conversion. Measured on 27A266a: on the unfolded panel of a foldable the
        // home indicator sits along the framebuffer's right edge, and no other value goes home.
        let edge = TouchEvent.Edge.beginning(at: points[0])

        try await session.touch(TouchEvent(phase: .began, points: [points[0]], edge: edge))
        for point in points.dropFirst() {
            try await Task.sleep(for: .milliseconds(stepMilliseconds))
            try await session.touch(TouchEvent(phase: .moved, points: [point], edge: edge))
        }

        var last = points[points.count - 1]
        if restsAtEnd {
            for point in native(HomeGesture.settlePath(around: finish), turn) {
                try await Task.sleep(for: .milliseconds(40))
                try await session.touch(TouchEvent(phase: .moved, points: [point], edge: edge))
                last = point
            }
        }
        try await session.touch(TouchEvent(phase: .ended, points: [last], edge: edge))
    }

    private static func native(_ path: [CGPoint], _ turn: DeviceOrientation) -> [CGPoint] {
        path.map { CoordinateMapper.portraitNativePoint(from: $0, orientation: turn) }
    }
}
