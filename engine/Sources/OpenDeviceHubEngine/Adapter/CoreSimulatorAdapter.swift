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

        let deviceSet: any ODHSimDeviceSet
        do {
            deviceSet = try context.defaultDeviceSet()
        } catch {
            throw EngineError.privateCall(
                symbol: "-[SimServiceContext defaultDeviceSetWithError:]",
                message: error.localizedDescription
            )
        }

        return deviceSet.devices.map { element in
            let device = unsafeBitCast(element as AnyObject, to: (any ODHSimDevice).self)
            let runtimeIdentifier = device.runtimeIdentifier
            return DeviceInfo(
                udid: device.udid.uuidString,
                name: device.name,
                deviceTypeIdentifier: device.deviceType?.identifier ?? "",
                runtimeIdentifier: runtimeIdentifier,
                runtimeName: device.runtime?.name
                    ?? RuntimeIdentifier.readableName(for: runtimeIdentifier),
                state: DeviceState.from(state: device.state, stateString: device.stateString),
                isAvailable: device.available
            )
        }
    }

    public func openDisplay(_ udid: String) throws -> any DisplaySession {
        lock.lock()
        defer { lock.unlock() }

        let device = try rawDevice(udid)
        let state = DeviceState.from(state: device.state, stateString: device.stateString)
        guard state == .booted else {
            throw EngineError.deviceNotBooted(udid: udid)
        }
        guard let io = device.io else {
            throw EngineError.capabilityUnavailable(name: "device IO")
        }

        let scale = CGFloat(device.deviceType?.mainScreenScale ?? 1)
        let ports = unsafeBitCast(io as AnyObject, to: (any ODHSimDeviceIO).self).ioPorts

        guard let renderableProtocol = NSProtocolFromString("SimDisplayRenderable"),
              let surfaceProtocol = NSProtocolFromString("SimDisplayIOSurfaceRenderable"),
              let stateProtocol = NSProtocolFromString("SimDisplayDescriptorState") else {
            throw EngineError.symbolNotFound(name: "SimDisplay protocols", framework: "CoreSimDeviceIO")
        }

        for element in ports {
            let port = unsafeBitCast(element as AnyObject, to: (any ODHSimDeviceIOPort).self)
            guard let descriptor = port.descriptor as AnyObject?,
                  descriptor.conforms(to: renderableProtocol),
                  descriptor.conforms(to: surfaceProtocol) else { continue }

            let typedDescriptor = unsafeBitCast(descriptor, to: (any ODHSimDeviceIOPortDescriptor).self)
            guard let portState = typedDescriptor.state as AnyObject?,
                  portState.conforms(to: stateProtocol) else { continue }

            // Two ports share the identifier com.apple.framebuffer.display on 17F42. Class 0 is the
            // device's own screen; class 1 is a secondary display that stays empty while unused.
            let displayState = unsafeBitCast(portState, to: (any ODHSimDisplayDescriptorState).self)
            guard displayState.displayClass == 0 else { continue }

            // The bezel is on by default, matching what the simulator itself shows. The caller
            // turns it off through the session.
            return try SimulatorDisplaySession(
                descriptor: descriptor,
                pointScale: scale,
                bezelEnabled: true
            )
        }

        throw EngineError.capabilityUnavailable(name: "main display port")
    }

    public func openInput(_ udid: String) throws -> any InputSession {
        lock.lock()
        defer { lock.unlock() }

        let device = try rawDevice(udid)
        let state = DeviceState.from(state: device.state, stateString: device.stateString)
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
        guard DeviceState.from(state: device.state, stateString: device.stateString) == .booted else {
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

    public func setOrientation(_ orientation: DeviceOrientation, udid: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let device = try rawDevice(udid)
        guard DeviceState.from(state: device.state, stateString: device.stateString) == .booted else {
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

    private func rawDevice(_ udid: String) throws -> any ODHSimDevice {
        let deviceSet: any ODHSimDeviceSet
        do {
            deviceSet = try context.defaultDeviceSet()
        } catch {
            throw EngineError.privateCall(
                symbol: "-[SimServiceContext defaultDeviceSetWithError:]",
                message: error.localizedDescription
            )
        }
        for element in deviceSet.devices {
            let device = unsafeBitCast(element as AnyObject, to: (any ODHSimDevice).self)
            if device.udid.uuidString.caseInsensitiveCompare(udid) == .orderedSame {
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
        return capabilities
    }
}
