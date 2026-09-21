import AppKit
import QuartzCore

/// A red dot in the title bar while a recording runs. A window title is plain text, so the dot is a
/// real view rather than a glyph: it takes a colour, sits at the title's own size, and fades in and
/// out instead of flicking between two characters. Keeping it out of the title also leaves the name
/// steady in Mission Control and the Window menu.
@MainActor
final class RecordingIndicator {
    private let accessory = NSTitlebarAccessoryViewController()
    private let dot = DotView()
    private var attachedTo: NSWindow?

    init() {
        dot.frame = CGRect(x: 0, y: 0, width: 22, height: 16)
        accessory.view = dot
        accessory.layoutAttribute = .left
    }

    func setVisible(_ visible: Bool, on window: NSWindow?) {
        guard let window else { return }
        if visible {
            guard attachedTo !== window else { return }
            detach()
            window.addTitlebarAccessoryViewController(accessory)
            attachedTo = window
            dot.startPulsing()
        } else {
            detach()
        }
    }

    func detach() {
        dot.stopPulsing()
        guard let attachedTo else { return }
        if let index = attachedTo.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory }) {
            attachedTo.removeTitlebarAccessoryViewController(at: index)
        }
        self.attachedTo = nil
    }
}

private final class DotView: NSView {
    private static let pulse = "odh.recording.pulse"

    override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 16) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setFill()
        let size: CGFloat = 9
        NSBezierPath(ovalIn: CGRect(
            x: (bounds.width - size) / 2,
            y: (bounds.height - size) / 2,
            width: size,
            height: size
        )).fill()
    }

    func startPulsing() {
        wantsLayer = true
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.25
        fade.duration = 0.7
        fade.autoreverses = true
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(fade, forKey: Self.pulse)
    }

    func stopPulsing() {
        layer?.removeAnimation(forKey: Self.pulse)
    }
}
