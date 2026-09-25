import Darwin
import Foundation
import OpenDeviceHubPrivate

/// CoreSimulator makes no thread safety promise, so every call into it is serialized here. The
/// stored context is an Objective-C object and cannot be `Sendable` on its own.
public final class CoreSimulatorAdapter: SimulatorAdapter, @unchecked Sendable {
    public let xcode: XcodeInstall
    public let capabilities: Capabilities

    private let context: any ODHSimServiceContext
    private let lock = NSLock()

    public init(xcode: XcodeInstall) throws {
        self.xcode = xcode
        _ = try FrameworkLoader.load(.coreSimulator, from: xcode)
        let simulatorKit = try? FrameworkLoader.load(.simulatorKit, from: xcode)
        self.context = try Self.makeServiceContext(developerDir: xcode.developerDir.path(percentEncoded: false))
        self.capabilities = Self.detectCapabilities(hasSimulatorKit: simulatorKit != nil)
    }

    public func devices() throws -> [DeviceInfo] {
        lock.lock()
        defer { lock.unlock() }

        return (try deviceSet().devices ?? []).compactMap { element in
            let device = unsafeBitCast(element as AnyObject, to: (any ODHSimDevice).self)
            guard let udid = device.udid?.uuidString else { return nil }
            let runtimeIdentifier = device.runtimeIdentifier ?? ""
            return DeviceInfo(
                udid: udid,
                name: device.name ?? udid,
                deviceTypeIdentifier: device.deviceType?.identifier ?? "",
                runtimeIdentifier: runtimeIdentifier,
                runtimeName: device.runtime?.name
                    ?? RuntimeIdentifier.readableName(for: runtimeIdentifier),
                state: DeviceState.from(state: device.state, stateString: device.stateString ?? ""),
                isAvailable: device.available
            )
        }
    }

    /// Every built in screen the device has, in port order.
    ///
    /// One for an ordinary device, two for a foldable. Both of a foldable's panels are live at the
    /// same time, so this says nothing about which one the guest is currently drawing to.
    public func panels(_ udid: String) throws -> [DevicePanel] {
        lock.lock()
        defer { lock.unlock() }
        return try builtInPanels(udid).panels
    }

    public func openDisplay(_ udid: String) throws -> any DisplaySession {
        try openDisplay(udid, panel: nil)
    }

    /// Opens one panel, or the device's own main screen when none is named.
    public func openDisplay(_ udid: String, panel: DevicePanel?) throws -> any DisplaySession {
        lock.lock()
        defer { lock.unlock() }

        let found = try builtInPanels(udid)
        let chosen = panel.flatMap { wanted in
            // By identity first, so remembering a panel survives a port order that moved. Falling
            // back to the index keeps a remembered choice usable across a reboot, which mints new
            // port UUIDs.
            found.panels.firstIndex { $0.id == wanted.id }
                ?? found.panels.firstIndex { $0.index == wanted.index }
        } ?? found.panels.firstIndex { $0.isMainScreen } ?? found.panels.indices.first

        guard let index = chosen else {
            throw EngineError.capabilityUnavailable(name: "main display port")
        }

        // The bezel is on by default, matching what the simulator itself shows. The caller turns it
        // off through the session.
        return try SimulatorDisplaySession(
            descriptor: found.descriptors[index],
            pointScale: found.scale,
            bezelEnabled: true
        )
    }

    private func builtInPanels(
        _ udid: String
    ) throws -> (panels: [DevicePanel], descriptors: [AnyObject], scale: CGFloat) {
        let device = try rawDevice(udid)
        let state = DeviceState.from(state: device.state, stateString: device.stateString ?? "")
        guard state == .booted else {
            throw EngineError.deviceNotBooted(udid: udid)
        }
        guard let io = device.io else {
            throw EngineError.capabilityUnavailable(name: "device IO")
        }

        let scale = CGFloat(device.deviceType?.mainScreenScale ?? 1)
        let mainScreenSize = device.deviceType?.mainScreenSize ?? .zero
        let ports = unsafeBitCast(io as AnyObject, to: (any ODHSimDeviceIO).self).ioPorts ?? []

        guard let renderableProtocol = NSProtocolFromString("SimDisplayRenderable"),
              let surfaceProtocol = NSProtocolFromString("SimDisplayIOSurfaceRenderable"),
              let stateProtocol = NSProtocolFromString("SimDisplayDescriptorState") else {
            throw EngineError.symbolNotFound(name: "SimDisplay protocols", framework: "CoreSimDeviceIO")
        }

        var descriptors: [AnyObject] = []
        var identifiers: [String] = []
        var indexes: [Int] = []
        var sizes: [CGSize] = []

        for (index, element) in ports.enumerated() {
            let port = unsafeBitCast(element as AnyObject, to: (any ODHSimDeviceIOPort).self)
            guard let descriptor = port.descriptor as AnyObject?,
                  descriptor.conforms(to: renderableProtocol),
                  descriptor.conforms(to: surfaceProtocol) else { continue }

            let typedDescriptor = unsafeBitCast(descriptor, to: (any ODHSimDeviceIOPortDescriptor).self)
            guard let portState = typedDescriptor.state as AnyObject?,
                  portState.conforms(to: stateProtocol) else { continue }

            // Class 1 is an external display port that stays empty while unused. A foldable reports
            // a class 0 port per panel, which is why this collects them rather than taking the first.
            let displayState = unsafeBitCast(portState, to: (any ODHSimDisplayDescriptorState).self)
            guard displayState.displayClass == 0 else { continue }

            let renderable = unsafeBitCast(descriptor, to: (any ODHSimDisplayRenderable).self)
            descriptors.append(descriptor)
            identifiers.append(port.uuid?.uuidString ?? "port-\(index)")
            indexes.append(index)
            sizes.append(renderable.displaySize)
        }

        guard !descriptors.isEmpty else {
            throw EngineError.capabilityUnavailable(name: "main display port")
        }

        let panels = sizes.indices.map { position in
            DevicePanel(
                id: identifiers[position],
                index: indexes[position],
                name: DevicePanel.name(at: position, of: sizes),
                pixelSize: sizes[position],
                // A foldable's main screen is its cover, so this is read from the device rather than
                // assumed to be the first or the largest panel.
                isMainScreen: sizes[position] == mainScreenSize
            )
        }
        return (panels, descriptors, scale)
    }

    /// Opens the control that folds and turns a foldable.
    ///
    /// Available on any booted device, since the service is not foldable specific, but only a device
    /// with a hinge does anything with it.
    public func openFoldableControl(_ udid: String) throws -> FoldableControl {
        lock.lock()
        defer { lock.unlock() }

        let device = try rawDevice(udid)
        guard DeviceState.from(state: device.state, stateString: device.stateString ?? "") == .booted else {
            throw EngineError.deviceNotBooted(udid: udid)
        }
        guard (device as AnyObject).responds(to: NSSelectorFromString("lookup:error:")) else {
            throw EngineError.symbolNotFound(
                name: "-[SimDevice lookup:error:]",
                framework: PrivateFramework.coreSimulator.rawValue
            )
        }
        let port = device.lookup(FoldableControl.serviceName, error: nil)
        let digitizerPort = device.lookup(FoldableControl.digitizerServiceName, error: nil)
        guard port != 0, digitizerPort != 0 else {
            throw EngineError.capabilityUnavailable(name: "vendor input on \(udid)")
        }
        return try FoldableControl(port: port, digitizerPort: digitizerPort)
    }

    public func openInput(_ udid: String) throws -> any InputSession {
        lock.lock()
        defer { lock.unlock() }

        let device = try rawDevice(udid)
        let state = DeviceState.from(state: device.state, stateString: device.stateString ?? "")
        guard state == .booted else {
            throw EngineError.deviceNotBooted(udid: udid)
        }
        let simulatorKit = try FrameworkLoader.load(.simulatorKit, from: xcode)
        return try LegacyHIDInputSession(device: device, simulatorKit: simulatorKit)
    }

    public func simulateMemoryWarning(_ udid: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let device = try rawDevice(udid)
        guard DeviceState.from(state: device.state, stateString: device.stateString ?? "") == .booted else {
            throw EngineError.deviceNotBooted(udid: udid)
        }
        guard (device as AnyObject).responds(to: NSSelectorFromString("simulateMemoryWarning")) else {
            throw EngineError.symbolNotFound(
                name: "-[SimDevice simulateMemoryWarning]",
                framework: PrivateFramework.coreSimulator.rawValue
            )
        }
        device.simulateMemoryWarning()
    }

    /// The Mac's keyboard as the device's hardware keyboard.
    ///
    /// Two private pieces, both confirmed present on this Xcode before use: the selector on
    /// `SimDevice`, and `IndigoHIDGetKeyboardType` for the byte it wants. The type is asked for
    /// rather than guessed, because passing a made up keyboard type is not a safe thing to do to a
    /// device.
    public func setHardwareKeyboardEnabled(_ enabled: Bool, udid: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let device = try rawDevice(udid)
        guard DeviceState.from(state: device.state, stateString: device.stateString ?? "") == .booted else {
            throw EngineError.deviceNotBooted(udid: udid)
        }
        let selector = NSSelectorFromString("setHardwareKeyboardEnabled:keyboardType:error:")
        guard (device as AnyObject).responds(to: selector) else {
            throw EngineError.symbolNotFound(
                name: "-[SimDevice setHardwareKeyboardEnabled:keyboardType:error:]",
                framework: PrivateFramework.coreSimulator.rawValue
            )
        }
        let simulatorKit = try FrameworkLoader.load(.simulatorKit, from: xcode)
        guard let symbol = simulatorKit.symbol(named: "IndigoHIDGetKeyboardType") else {
            throw EngineError.symbolNotFound(
                name: "IndigoHIDGetKeyboardType",
                framework: PrivateFramework.simulatorKit.rawValue
            )
        }
        typealias KeyboardType = @convention(c) () -> UInt8
        let keyboardType = unsafeBitCast(symbol, to: KeyboardType.self)()

        // Returns BOOL with an NSError out parameter, so Swift imports it as throwing. Rewrapped
        // rather than passed through, so callers see one error type.
        do {
            try device.setHardwareKeyboardEnabled(enabled, keyboardType: keyboardType)
        } catch {
            throw EngineError.privateCall(
                symbol: "setHardwareKeyboardEnabled:keyboardType:error:",
                message: error.localizedDescription
            )
        }
    }

    /// Points the guest's keyboard at a language, for example "en-US".
    public func setKeyboardLanguage(_ language: String, udid: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let device = try rawDevice(udid)
        guard DeviceState.from(state: device.state, stateString: device.stateString ?? "") == .booted else {
            throw EngineError.deviceNotBooted(udid: udid)
        }
        let selector = NSSelectorFromString("setKeyboardLanguage:error:")
        guard (device as AnyObject).responds(to: selector) else {
            throw EngineError.symbolNotFound(
                name: "-[SimDevice setKeyboardLanguage:error:]",
                framework: PrivateFramework.coreSimulator.rawValue
            )
        }
        do {
            try device.setKeyboardLanguage(language)
        } catch {
            throw EngineError.privateCall(
                symbol: "setKeyboardLanguage:error:",
                message: error.localizedDescription
            )
        }
    }

    /// A connection that keeps the device's clipboard and the Mac's in step.
    ///
    /// The caller holds the result for as long as the device is on screen: the autosync runs on this
    /// connection, so releasing it stops the syncing.
    ///
    /// The port is looked up here rather than stored anywhere, because a mach port name means
    /// nothing outside the process that asked for it. Verified on Xcode 27 (27A266a) and Xcode 26.6.
    public func openPasteboard(_ udid: String) throws -> any PasteboardSession {
        lock.lock()
        defer { lock.unlock() }

        let device = try rawDevice(udid)
        guard DeviceState.from(state: device.state, stateString: device.stateString ?? "") == .booted else {
            throw EngineError.deviceNotBooted(udid: udid)
        }
        guard (device as AnyObject).responds(to: NSSelectorFromString("lookup:error:")) else {
            throw EngineError.symbolNotFound(
                name: "-[SimDevice lookup:error:]",
                framework: PrivateFramework.coreSimulator.rawValue
            )
        }
        _ = try FrameworkLoader.load(.simPasteboardPlus, from: xcode)
        // Asked of the listener class rather than written down here, so a rename in a later Xcode is
        // followed rather than guessed at.
        guard let service = PasteboardBridge.serviceName() else {
            throw EngineError.symbolNotFound(
                name: "+[SimPasteboardInterfaceListener machServiceName]",
                framework: PrivateFramework.simPasteboardPlus.rawValue
            )
        }
        let port = device.lookup(service, error: nil)
        guard port != 0 else {
            throw EngineError.capabilityUnavailable(name: "pasteboard sync on \(udid)")
        }
        return try PasteboardBridge(port: port)
    }

    public func setOrientation(_ orientation: DeviceOrientation, udid: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let device = try rawDevice(udid)
        guard DeviceState.from(state: device.state, stateString: device.stateString ?? "") == .booted else {
            throw EngineError.deviceNotBooted(udid: udid)
        }
        guard (device as AnyObject).responds(to: NSSelectorFromString("lookup:error:")) else {
            throw EngineError.symbolNotFound(
                name: "-[SimDevice lookup:error:]",
                framework: PrivateFramework.coreSimulator.rawValue
            )
        }

        let port = device.lookup(WorkspaceOrientation.portName, error: nil)
        guard port != 0 else {
            throw EngineError.capabilityUnavailable(
                name: "\(WorkspaceOrientation.portName), the guest may still be starting"
            )
        }
        defer { mach_port_deallocate(mach_task_self_, port) }
        try WorkspaceOrientation.send(orientation, to: port)
    }

    public func watchDeviceStates() throws -> any DeviceNotifier {
        lock.lock()
        defer { lock.unlock() }

        guard capabilities.contains(.deviceNotifications) else {
            throw EngineError.capabilityUnavailable(name: "device notifications")
        }
        return try SimulatorDeviceNotifier(deviceSet: deviceSet())
    }

    private func deviceSet() throws -> any ODHSimDeviceSet {
        do {
            return try context.defaultDeviceSet()
        } catch {
            throw EngineError.privateCall(
                symbol: "-[SimServiceContext defaultDeviceSetWithError:]",
                message: error.localizedDescription
            )
        }
    }

    private func rawDevice(_ udid: String) throws -> any ODHSimDevice {
        for element in try deviceSet().devices ?? [] {
            let device = unsafeBitCast(element as AnyObject, to: (any ODHSimDevice).self)
            if device.udid?.uuidString.caseInsensitiveCompare(udid) == .orderedSame {
                return device
            }
        }
        throw EngineError.deviceNotFound(udid: udid)
    }

    private static func makeServiceContext(developerDir: String) throws -> any ODHSimServiceContext {
        guard let contextClass = NSClassFromString("SimServiceContext") else {
            throw EngineError.symbolNotFound(name: "SimServiceContext", framework: "CoreSimulator")
        }
        // The message goes to the class object, so it has to be reached as an object. Bit casting
        // the `AnyClass` metatype straight into the existential hands Swift a value it then tries
        // to retain as an object, which segfaults.
        let classObject = contextClass as AnyObject
        let selector = NSSelectorFromString("sharedServiceContextForDeveloperDir:error:")
        guard classObject.responds(to: selector) else {
            throw EngineError.symbolNotFound(
                name: "+[SimServiceContext sharedServiceContextForDeveloperDir:error:]",
                framework: "CoreSimulator"
            )
        }

        let typed = unsafeBitCast(classObject, to: (any ODHSimServiceContextClass).self)
        let context: any ODHSimServiceContext
        do {
            context = try typed.sharedServiceContext(forDeveloperDir: developerDir)
        } catch {
            throw EngineError.privateCall(
                symbol: "+[SimServiceContext sharedServiceContextForDeveloperDir:error:]",
                message: error.localizedDescription
            )
        }

        guard (context as AnyObject).responds(to: NSSelectorFromString("defaultDeviceSetWithError:")) else {
            throw EngineError.symbolNotFound(
                name: "-[SimServiceContext defaultDeviceSetWithError:]",
                framework: "CoreSimulator"
            )
        }
        return context
    }

    private static func detectCapabilities(hasSimulatorKit: Bool) -> Capabilities {
        var capabilities: Capabilities = []
        if NSProtocolFromString("SimDisplayIOSurfaceRenderable") != nil {
            capabilities.insert(.display)
        }
        if hasSimulatorKit, NSClassFromString("SimulatorKit.SimDeviceLegacyHIDClient") != nil {
            capabilities.formUnion([.touch, .keyboard, .hardwareButtons])
        }
        if let device = NSClassFromString("SimDevice"),
           class_getInstanceMethod(device, NSSelectorFromString("simulateMemoryWarning")) != nil {
            capabilities.insert(.memoryWarning)
        }
        // Shake and slow animations are Darwin notifications the guest's UIKit listens for, not
        // private selectors, so they are available whenever simctl can reach the device.
        capabilities.formUnion([.shake, .slowAnimations])
        // Rotation goes through the guest's workspace port, which only exists once the device has
        // booted, so the flag says the route is implemented rather than that it will succeed now.
        if let device = NSClassFromString("SimDevice"),
           class_getInstanceMethod(device, NSSelectorFromString("lookup:error:")) != nil {
            capabilities.insert(.rotation)
        }
        // Both halves have to be there: the selector that makes the change, and the symbol that
        // supplies the keyboard type it wants. One without the other is not a working capability.
        if hasSimulatorKit,
           let device = NSClassFromString("SimDevice"),
           class_getInstanceMethod(
               device, NSSelectorFromString("setHardwareKeyboardEnabled:keyboardType:error:")
           ) != nil {
            capabilities.insert(.hardwareKeyboard)
        }
        // The interface class only exists once SimPasteboardPlus has been loaded, which happens on
        // first use, so the flag turns on the route rather than promising the class is resident.
        if let device = NSClassFromString("SimDevice"),
           class_getInstanceMethod(device, NSSelectorFromString("lookup:error:")) != nil {
            capabilities.insert(.pasteboardSync)
        }
        if let deviceSet = NSClassFromString("SimDeviceSet"),
           class_getInstanceMethod(
               deviceSet, NSSelectorFromString("registerNotificationHandlerOnQueue:handler:")
           ) != nil,
           class_getInstanceMethod(
               deviceSet, NSSelectorFromString("unregisterNotificationHandler:error:")
           ) != nil {
            capabilities.insert(.deviceNotifications)
        }
        return capabilities
    }
}
