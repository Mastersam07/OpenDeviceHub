import AppKit
import OpenDeviceHubEngine
import SwiftUI

/// What the panel needs to do its job, passed in so it never reaches for `simctl` itself.
@MainActor
public struct NewSimulatorActions {
    public var deviceTypes: () -> [SimctlDeviceType]
    public var runtimeSupport: () -> [SimctlRuntimeSupport]
    public var existingNames: () -> [String]
    /// Returns the new device's UDID, or throws with something worth showing.
    public var create: (String, SimctlDeviceType, SimctlRuntime) throws -> String
    public var created: (String) -> Void

    public init(
        deviceTypes: @escaping () -> [SimctlDeviceType],
        runtimeSupport: @escaping () -> [SimctlRuntimeSupport],
        existingNames: @escaping () -> [String],
        create: @escaping (String, SimctlDeviceType, SimctlRuntime) throws -> String,
        created: @escaping (String) -> Void
    ) {
        self.deviceTypes = deviceTypes
        self.runtimeSupport = runtimeSupport
        self.existingNames = existingNames
        self.create = create
        self.created = created
    }
}

@MainActor
public enum NewSimulatorPanel {
    private static var controller: NewSimulatorWindowController?

    public static func show(actions: NewSimulatorActions, settings: ViewerSettings = ViewerSettings()) {
        // Rebuilt each time rather than reused: the runtimes and device types on the machine can
        // change between openings, and a stale list would offer something that is no longer there.
        let controller = NewSimulatorWindowController(actions: actions, settings: settings)
        Self.controller = controller
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    static func dismiss() {
        controller?.close()
        controller = nil
    }
}

@MainActor
final class NewSimulatorWindowController: NSWindowController {
    init(actions: NewSimulatorActions, settings: ViewerSettings) {
        let view = NewSimulatorView(actions: actions, settings: settings)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "New Simulator"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
}

@MainActor
private struct NewSimulatorView: View {
    private let actions: NewSimulatorActions
    private let settings: ViewerSettings
    private let types: [SimctlDeviceType]
    private let support: [SimctlRuntimeSupport]

    @State private var name: String
    @State private var type: SimctlDeviceType?
    @State private var runtime: SimctlRuntime?
    @State private var failure: String?
    /// True once the name has been edited, so the suggestion stops following the device type.
    @State private var nameIsMine = false

    init(actions: NewSimulatorActions, settings: ViewerSettings) {
        self.actions = actions
        self.settings = settings
        let support = actions.runtimeSupport()
        let types = SimulatorCreation.deviceTypes(in: support, from: actions.deviceTypes())
        self.support = support
        self.types = types
        let first = types.first
        _type = State(initialValue: first)
        _runtime = State(initialValue: first.flatMap {
            SimulatorCreation.runtimes(for: $0, in: support).first
        })
        _name = State(initialValue: first.map {
            SimulatorCreation.suggestedName(for: $0, existing: actions.existingNames())
        } ?? "")
    }

    private var runtimes: [SimctlRuntime] {
        type.map { SimulatorCreation.runtimes(for: $0, in: support) } ?? []
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && type != nil && runtime != nil
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .onChange(of: name) { _, _ in nameIsMine = true }

                Picker("Device Type", selection: $type) {
                    ForEach(types, id: \.identifier) { candidate in
                        Text(candidate.name).tag(Optional(candidate))
                    }
                }
                .onChange(of: type) { _, _ in deviceTypeChanged() }

                Picker("OS Version", selection: $runtime) {
                    ForEach(runtimes, id: \.identifier) { candidate in
                        Text(candidate.name).tag(Optional(candidate))
                    }
                }
                .disabled(runtimes.isEmpty)
            } footer: {
                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(Color.red)
                } else if runtimes.count == 1, let only = runtimes.first {
                    // Worth saying: one runtime is normal for a device only just added.
                    Text("\(only.name) is the only version that runs this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Cancel") { NewSimulatorPanel.dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Previous") { fillFromPrevious() }
                    .disabled(settings.lastCreatedSimulator == nil)
                    .help("Fill this in with the last simulator you created.")
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func deviceTypeChanged() {
        // The chosen runtime may not run the new device, so it follows rather than going stale.
        if let runtime, !runtimes.contains(runtime) {
            self.runtime = runtimes.first
        } else if runtime == nil {
            runtime = runtimes.first
        }
        if !nameIsMine, let type {
            name = SimulatorCreation.suggestedName(for: type, existing: actions.existingNames())
            // Assigning the field fires onChange, which would otherwise look like the person typing.
            nameIsMine = false
        }
    }

    private func fillFromPrevious() {
        guard let previous = settings.lastCreatedSimulator else { return }
        if let match = types.first(where: { $0.identifier == previous.deviceType }) {
            type = match
            runtime = SimulatorCreation.runtimes(for: match, in: support)
                .first { $0.identifier == previous.runtime }
                ?? SimulatorCreation.runtimes(for: match, in: support).first
        }
        name = previous.name
        nameIsMine = true
    }

    private func create() {
        guard let type, let runtime else { return }
        let wanted = name.trimmingCharacters(in: .whitespaces)
        do {
            let udid = try actions.create(wanted, type, runtime)
            settings.lastCreatedSimulator = LastCreatedSimulator(
                name: wanted,
                deviceType: type.identifier,
                runtime: runtime.identifier
            )
            NewSimulatorPanel.dismiss()
            actions.created(udid)
        } catch {
            failure = error.localizedDescription
        }
    }
}
