import AppKit
import OpenDeviceHubEngine

/// A window that keeps the size it is given. AppKit otherwise shrinks a window to the visible
/// screen, and with a locked aspect ratio that quietly defeats Pixel Accurate on any device taller
/// than the display: a 1206x2622 phone wants 1311 points of height on a two times Mac, which no
/// laptop screen has.
final class DeviceWindow: NSWindow {
    /// Full screen needs AppKit's own sizing, so the override steps aside for the transition.
    var constrainsToScreen = false

    private var resize: DeviceResizeSession?
    private var pushedCursor = false

    /// A drag that starts on one of the device's corners resizes the window, keeping the device's
    /// shape. AppKit's own edge resize still works; this is the handle that is easy to hit.
    override func sendEvent(_ event: NSEvent) {
        if resize != nil {
            switch event.type {
            case .leftMouseDragged:
                if let frame = resize?.frame(at: NSEvent.mouseLocation) {
                    setFrame(frame, display: true, animate: false)
                }
                return
            case .leftMouseUp:
                endResize()
                return
            default:
                break
            }
        }
        if event.type == .leftMouseDown,
           !styleMask.contains(.fullScreen),
           let root = contentView as? DevicePresentationView,
           let visible = (screen ?? NSScreen.main)?.visibleFrame {
            let local = root.convert(event.locationInWindow, from: nil)
            if let corner = root.resizeCorner(at: local) {
                resize = DeviceResizeSession(
                    corner: corner,
                    initialFrame: frame,
                    initialPointer: NSEvent.mouseLocation,
                    deviceSize: root.deviceBodyRect.size,
                    visibleFrame: visible,
                    minimumSize: minSize
                )
                corner.cursor.push()
                pushedCursor = true
                return
            }
        }
        super.sendEvent(event)
    }

    private func endResize() {
        guard resize != nil else { return }
        resize = nil
        if pushedCursor {
            NSCursor.pop()
            pushedCursor = false
        }
    }

    override func close() {
        endResize()
        super.close()
    }

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
