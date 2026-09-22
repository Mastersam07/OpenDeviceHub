import AppKit
import OpenDeviceHubEngine

/// What the window shows instead of a frozen last frame once its device has gone. The device may
/// have been shut down from anywhere, so this is also what a window looks like while it waits for
/// its device to come back.
@MainActor
public final class ShutdownOverlayView: NSView {
    public var onReboot: (() -> Void)?

    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let button = NSButton(title: "Reboot", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let stack = NSStackView()

    public init(deviceName: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        title.stringValue = deviceName
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .white
        title.alignment = .center

        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center

        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(reboot)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [title, detail, button, spinner] as [NSView] {
            stack.addArrangedSubview(view)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
        setShutDown()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    public func setShutDown() {
        detail.stringValue = "Shut down"
        button.isHidden = false
        button.isEnabled = true
        spinner.stopAnimation(nil)
    }

    /// Shown from the moment a boot starts until the device is back, whoever started it, so the
    /// window never looks like it ignored the request.
    public func setBooting() {
        detail.stringValue = "Starting up"
        button.isHidden = true
        spinner.startAnimation(nil)
    }

    public func setFailed(_ message: String) {
        detail.stringValue = message
        button.isHidden = false
        button.isEnabled = true
        spinner.stopAnimation(nil)
    }

    @objc private func reboot() {
        setBooting()
        onReboot?()
    }
}

public enum DetachReason: Sendable, Equatable {
    case shutDown
    case booting
    case failed(String)

    var summary: String {
        switch self {
        case .shutDown: "shut down"
        case .booting: "starting up"
        case .failed(let message): message
        }
    }
}

public enum DeviceWindowTransition: Equatable {
    case detach(DetachReason)
    case reattach
    case ignore

    public static func forState(_ state: DeviceState, isDetached: Bool) -> DeviceWindowTransition {
        switch state {
        case .shutdown, .shuttingDown:
            isDetached ? .ignore : .detach(.shutDown)
        case .booting:
            isDetached ? .detach(.booting) : .ignore
        case .booted:
            isDetached ? .reattach : .ignore
        case .unknown:
            .ignore
        }
    }
}
