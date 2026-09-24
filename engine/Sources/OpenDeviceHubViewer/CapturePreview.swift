import AppKit
import AVFoundation
import OpenDeviceHubEngine

/// The card that appears beside a device after a capture, and what happens to the file.
///
/// Left alone it files the capture and disappears, which is what the simulator this replaces does.
/// Acted on, it does that instead. Nothing is written to the capture folder until one of those
/// happens.
@MainActor
public final class CapturePreviewPresenter {
    public static let lifetime: TimeInterval = 6

    private var showing: [CapturePreviewPanel] = []
    private let filer: CaptureFiler
    private let report: (String) -> Void

    public init(filer: CaptureFiler = CaptureFiler(), report: @escaping (String) -> Void = { _ in }) {
        self.filer = filer
        self.report = report
    }

    public func show(_ capture: PendingCapture, beside window: NSWindow?) {
        // One at a time. Taking another capture files the one before it straight away, which is
        // what the simulator this replaces does: previews never pile up on screen.
        settleEverything()

        guard let image = Self.thumbnail(for: capture.temporary) else {
            // Nothing to show is not a reason to lose the file.
            settle(capture)
            return
        }

        let size = CapturePreviewLayout.size(for: image.size)
        let panel = CapturePreviewPanel(capture: capture, image: image, size: size)
        panel.onFinish = { [weak self] outcome in self?.finish(panel, outcome) }

        let anchor = window?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        let visible = (window?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.anchor = anchor
        panel.setFrame(
            CapturePreviewLayout.frame(size: size, beside: anchor, visible: visible),
            display: false
        )
        showing.append(panel)
        panel.orderFrontRegardless()
        panel.startCountdown(Self.lifetime)
    }

    /// Everything still on screen is filed, so quitting does not quietly lose a capture.
    public func settleEverything() {
        for panel in showing {
            panel.stopCountdown()
            settle(panel.capture)
            panel.close()
        }
        showing.removeAll()
    }

    private func finish(_ panel: CapturePreviewPanel, _ outcome: CapturePreviewOutcome) {
        showing.removeAll { $0 === panel }
        panel.close()
        switch outcome {
        case .settle:
            settle(panel.capture)
        case .discard:
            filer.discard(panel.capture)
        case .saved(let url):
            report("saved \(url.path(percentEncoded: false))")
        }
    }

    private func settle(_ capture: PendingCapture) {
        do {
            let landed = try filer.settle(capture)
            report("saved \(landed.path(percentEncoded: false))")
        } catch {
            report("could not save the capture: \(error.localizedDescription)")
        }
    }

    /// A still for an image, and the first frame for a recording, so a video does not show as a
    /// blank card.
    static func thumbnail(for url: URL) -> NSImage? {
        if let image = NSImage(contentsOf: url), image.size.width > 0 {
            return image
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let frame = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return NSImage(cgImage: frame, size: CGSize(width: frame.width, height: frame.height))
    }
}

public enum CapturePreviewOutcome {
    case settle
    case discard
    case saved(URL)
}

@MainActor
final class CapturePreviewPanel: NSPanel {
    let capture: PendingCapture
    var anchor: CGRect = .zero
    var onFinish: ((CapturePreviewOutcome) -> Void)?

    private var countdown: Task<Void, Never>?
    private let filer = CaptureFiler()

    init(capture: PendingCapture, image: NSImage, size: CGSize) {
        self.capture = capture
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            // Borderless and non activating: this is a notice, not something to switch apps for.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = CapturePreviewView(image: image)
        view.frame = CGRect(origin: .zero, size: size)
        view.onClick = { [weak self] in self?.open() }
        view.menu = buildMenu()
        contentView = view
    }

    func startCountdown(_ seconds: TimeInterval) {
        countdown = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.onFinish?(.settle)
        }
    }

    func stopCountdown() {
        countdown?.cancel()
        countdown = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [
            ("Open", #selector(open)),
            ("Save As\u{2026}", #selector(saveAs)),
            ("Copy", #selector(copyToPasteboard)),
            ("Reveal in Finder", #selector(reveal)),
            ("Delete", #selector(deleteCapture)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    /// Opening, revealing and copying all need the file where it is going to live, so they settle it
    /// first. Only Delete and the countdown decide otherwise.
    @objc private func open() {
        stopCountdown()
        guard let landed = try? filer.settle(capture) else { return }
        NSWorkspace.shared.open(landed)
        onFinish?(.saved(landed))
    }

    @objc private func reveal() {
        stopCountdown()
        guard let landed = try? filer.settle(capture) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([landed])
        onFinish?(.saved(landed))
    }

    @objc private func copyToPasteboard() {
        stopCountdown()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([capture.temporary as NSURL])
        if let image = NSImage(contentsOf: capture.temporary) {
            NSPasteboard.general.writeObjects([image])
        }
        onFinish?(.settle)
    }

    @objc private func saveAs() {
        stopCountdown()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = capture.name
        panel.directoryURL = capture.destination
        guard panel.runModal() == .OK, let chosen = panel.url,
              let landed = try? filer.save(capture, to: chosen) else {
            // Cancelled, so the capture is still pending and keeps its original fate.
            onFinish?(.settle)
            return
        }
        onFinish?(.saved(landed))
    }

    @objc private func deleteCapture() {
        stopCountdown()
        onFinish?(.discard)
    }
}

private final class CapturePreviewView: NSView {
    var onClick: (() -> Void)?
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) {
        // Control click is a right click, which is how the menu is reached on a one button mouse.
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        onClick?()
    }
}
