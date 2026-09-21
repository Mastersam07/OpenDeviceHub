import Foundation
import OpenDeviceHubPrivate

/// CoreSimulator makes no thread safety promise, so every call into it is serialized here. The
/// stored context is an Objective-C object and cannot be `Sendable` on its own.
public final class Xcode26Adapter: SimulatorAdapter, @unchecked Sendable {
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
        return capabilities
    }
}
