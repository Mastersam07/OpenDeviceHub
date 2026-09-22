import AppKit

/// A window that keeps the size it is given. AppKit otherwise shrinks a window to the visible
/// screen, and with a locked aspect ratio that quietly defeats Pixel Accurate on any device taller
/// than the display: a 1206x2622 phone wants 1311 points of height on a two times Mac, which no
/// laptop screen has.
final class DeviceWindow: NSWindow {
    /// Full screen needs AppKit's own sizing, so the override steps aside for the transition.
    var constrainsToScreen = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        if constrainsToScreen {
            return super.constrainFrameRect(frameRect, to: screen)
        }
        guard let visible = (screen ?? self.screen ?? NSScreen.main)?.visibleFrame else {
            return frameRect
        }
        // Keeping the size is the whole point of the override, but a window still has to be
        // reachable, so only where it sits is adjusted.
        let titleBar = max(frameRect.height - contentLayoutRect.height, 28)
        return DeviceGeometry.reachableFrame(frameRect, in: visible, titleBarHeight: titleBar)
    }
}
