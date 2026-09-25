import AppKit
import OpenDeviceHubEngine

/// The bar along the bottom of a foldable's window: how far it is folded, and the three positions
/// worth going straight to.
///
/// Only a foldable gets one. Every other device has nothing to put here, so the bar is not built at
/// all rather than shown empty.
public final class FoldControlBar: NSVisualEffectView {
    /// The positions the presets go to. Halfway is the one the guest treats as open but tented,
    /// which is where a foldable spends most of its time in a demonstration.
    public enum Preset: CaseIterable {
        case closed, half, open

        var angle: Double {
            switch self {
            case .closed: FoldableControl.closedAngle
            case .half: 120
            case .open: FoldableControl.openAngle
            }
        }

        var title: String {
            switch self {
            case .closed: "Closed"
            case .half: "Half"
            case .open: "Open"
            }
        }
    }

    /// Called continuously while the slider moves, and once when a preset is chosen.
    public var onAngle: ((Double) -> Void)?

    private let slider = NSSlider()
    private let readout = NSTextField(labelWithString: "")
    private let presets = NSSegmentedControl()

    public init() {
        super.init(frame: .zero)
        material = .titlebar
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true

        slider.minValue = FoldableControl.closedAngle
        slider.maxValue = FoldableControl.openAngle
        slider.doubleValue = FoldableControl.closedAngle
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.controlSize = .small

        readout.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        readout.textColor = .secondaryLabelColor
        readout.alignment = .right

        presets.segmentCount = Preset.allCases.count
        presets.segmentStyle = .rounded
        presets.controlSize = .small
        for (index, preset) in Preset.allCases.enumerated() {
            presets.setLabel(preset.title, forSegment: index)
            presets.setWidth(56, forSegment: index)
        }
        presets.target = self
        presets.action = #selector(presetChosen)

        for view in [slider, readout, presets] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            presets.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            presets.centerYAnchor.constraint(equalTo: centerYAnchor),

            slider.leadingAnchor.constraint(equalTo: presets.trailingAnchor, constant: 14),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),

            readout.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 10),
            readout.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            readout.centerYAnchor.constraint(equalTo: centerYAnchor),
            readout.widthAnchor.constraint(equalToConstant: 44),
        ])

        showAngle(FoldableControl.closedAngle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    /// Moves the controls without reporting the change, for when the angle came from somewhere else.
    public func showAngle(_ degrees: Double) {
        slider.doubleValue = degrees
        readout.stringValue = "\(Int(degrees.rounded()))\u{00B0}"
        let match = Preset.allCases.firstIndex { abs($0.angle - degrees) < 0.5 }
        presets.selectedSegment = match ?? -1
    }

    @objc private func sliderMoved() {
        showAngle(slider.doubleValue)
        onAngle?(slider.doubleValue)
    }

    @objc private func presetChosen() {
        let index = presets.selectedSegment
        guard Preset.allCases.indices.contains(index) else { return }
        let angle = Preset.allCases[index].angle
        showAngle(angle)
        onAngle?(angle)
    }
}
