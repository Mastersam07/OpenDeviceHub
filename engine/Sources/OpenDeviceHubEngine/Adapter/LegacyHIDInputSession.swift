//
//  The single touch message construction is adapted from idb (Meta Platforms, MIT) and Siniulator
//  (Krzysztof Magiera, MIT). See THIRD_PARTY_NOTICES.md.
//

import CoreGraphics
import Foundation
import OpenDeviceHubPrivate

/// Sends contacts to a booted device over the legacy Indigo HID path. Sends are serialized because
/// the client is not documented as thread safe.
final class LegacyHIDInputSession: InputSession, @unchecked Sendable {
    private let client: any ODHSimDeviceLegacyHIDClient
    private let buildMouseMessage: IndigoHID.MouseMessageBuilder
    private let queue = DispatchQueue(label: "\(Brand.identifierPrefix).hid")
    private let lock = NSLock()
    private var isClosed = false

    init(device: any ODHSimDevice, simulatorKit: LoadedFramework) throws {
        guard let symbol = simulatorKit.symbol(named: IndigoHID.mouseBuilderSymbol) else {
            throw EngineError.symbolNotFound(
                name: IndigoHID.mouseBuilderSymbol,
                framework: PrivateFramework.simulatorKit.rawValue
            )
        }
        buildMouseMessage = unsafeBitCast(symbol, to: IndigoHID.MouseMessageBuilder.self)

        guard let clientClass = NSClassFromString("SimulatorKit.SimDeviceLegacyHIDClient") else {
            throw EngineError.symbolNotFound(
                name: "SimDeviceLegacyHIDClient",
                framework: PrivateFramework.simulatorKit.rawValue
            )
        }
        let classObject = clientClass as AnyObject
        let allocSelector = NSSelectorFromString("alloc")
        guard let allocMethod = class_getClassMethod(clientClass, allocSelector) else {
            throw EngineError.symbolNotFound(
                name: "+[SimDeviceLegacyHIDClient alloc]",
                framework: PrivateFramework.simulatorKit.rawValue
            )
        }

        // The class is Swift on 17F42, so it is allocated by sending +alloc rather than with
        // class_createInstance, which would not set up its Swift metadata.
        typealias AllocFunction = @convention(c) (AnyObject, Selector) -> AnyObject?
        guard let allocated = unsafeBitCast(method_getImplementation(allocMethod), to: AllocFunction.self)(
            classObject, allocSelector
        ) else {
            throw EngineError.privateCall(
                symbol: "+[SimDeviceLegacyHIDClient alloc]",
                message: "returned nil"
            )
        }

        // Called through the runtime because Swift imports any selector starting with `init` as an
        // initializer, which an existential cannot invoke.
        let initSelector = NSSelectorFromString("initWithDevice:error:")
        guard let initMethod = class_getInstanceMethod(clientClass, initSelector) else {
            throw EngineError.symbolNotFound(
                name: "-[SimDeviceLegacyHIDClient initWithDevice:error:]",
                framework: PrivateFramework.simulatorKit.rawValue
            )
        }
        typealias InitFunction = @convention(c) (
            AnyObject, Selector, AnyObject, UnsafeMutablePointer<AnyObject?>?
        ) -> AnyObject?
        var initError: AnyObject?
        guard let created = unsafeBitCast(method_getImplementation(initMethod), to: InitFunction.self)(
            allocated, initSelector, device as AnyObject, &initError
        ) else {
            throw EngineError.privateCall(
                symbol: "-[SimDeviceLegacyHIDClient initWithDevice:error:]",
                message: (initError as? NSError)?.localizedDescription ?? "returned nil"
            )
        }

        guard created.responds(
            to: NSSelectorFromString("sendWithMessage:freeWhenDone:completionQueue:completion:")
        ) else {
            throw EngineError.symbolNotFound(
                name: "-[SimDeviceLegacyHIDClient sendWithMessage:freeWhenDone:completionQueue:completion:]",
                framework: PrivateFramework.simulatorKit.rawValue
            )
        }
        client = unsafeBitCast(created, to: (any ODHSimDeviceLegacyHIDClient).self)
    }

    func touch(_ event: TouchEvent) async throws {
        guard event.points.count == 1, let point = event.points.first else {
            throw EngineError.capabilityUnavailable(name: "multi touch")
        }
        let eventType: UInt
        switch event.phase {
        // A moving contact is still a contact down, just at a new position.
        case .began, .moved: eventType = IndigoHID.eventTypeContactDown
        case .ended: eventType = IndigoHID.eventTypeContactUp
        case .cancelled:
            // Nothing in the Indigo surface corresponds to a cancelled contact, and lifting the
            // finger instead would be a different gesture, so this stays unsupported.
            throw EngineError.capabilityUnavailable(name: "touch phase cancelled")
        }

        try ensureOpen()

        let message = try makeSingleTouchMessage(point: point, eventType: eventType)
        try await send(message)
    }

    func close() {
        lock.lock()
        isClosed = true
        lock.unlock()
    }

    private func ensureOpen() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else {
            throw EngineError.capabilityUnavailable(name: "closed input session")
        }
    }

    private func makeSingleTouchMessage(
        point: CGPoint,
        eventType: UInt
    ) throws -> UnsafeMutableRawPointer {
        var contact = CGPoint(x: point.x, y: point.y)
        guard let source = buildMouseMessage(
            &contact,
            nil,
            IndigoHID.touchTarget,
            eventType,
            IndigoHID.unitScreenSize,
            IndigoHID.edgeNone
        ) else {
            throw EngineError.privateCall(
                symbol: IndigoHID.mouseBuilderSymbol,
                message: "returned nil"
            )
        }
        source.storeBytes(of: Double(point.x), toByteOffset: IndigoHID.xRatioOffset, as: Double.self)
        source.storeBytes(of: Double(point.y), toByteOffset: IndigoHID.yRatioOffset, as: Double.self)

        guard let message = calloc(1, IndigoHID.Message.size) else {
            free(source)
            throw EngineError.privateCall(symbol: "calloc", message: "out of memory")
        }

        var innerSize = IndigoHID.Message.innerSize
        var eventKind = IndigoHID.Message.eventKindTouch
        var timestamp = mach_absolute_time()
        memcpy(message.advanced(by: IndigoHID.Message.innerSizeOffset), &innerSize, 4)
        message.storeBytes(
            of: IndigoHID.Message.eventTypeSingleTouch,
            toByteOffset: IndigoHID.Message.eventTypeOffset,
            as: UInt8.self
        )
        memcpy(message.advanced(by: IndigoHID.Message.eventKindOffset), &eventKind, 4)
        memcpy(message.advanced(by: IndigoHID.Message.timestampOffset), &timestamp, 8)
        memcpy(
            message.advanced(by: IndigoHID.Message.contactOffset),
            source.advanced(by: IndigoHID.Message.contactOffset),
            IndigoHID.Message.contactBytes
        )
        free(source)

        memcpy(
            message.advanced(by: IndigoHID.Message.secondPayloadOffset),
            message.advanced(by: IndigoHID.Message.payloadOffset),
            Int(IndigoHID.Message.innerSize)
        )
        var first = IndigoHID.Message.secondContactMarkers.first
        var second = IndigoHID.Message.secondContactMarkers.second
        memcpy(message.advanced(by: IndigoHID.Message.secondContactMarkerOffsets.first), &first, 4)
        memcpy(message.advanced(by: IndigoHID.Message.secondContactMarkerOffsets.second), &second, 4)

        return message
    }

    private func send(_ message: UnsafeMutableRawPointer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Ownership of the buffer passes to the client with freeWhenDone, so nothing here
            // frees it afterwards.
            client.send(withMessage: message, freeWhenDone: true, completionQueue: queue) { error in
                if let error {
                    continuation.resume(throwing: EngineError.privateCall(
                        symbol: "-[SimDeviceLegacyHIDClient sendWithMessage:...]",
                        message: error.localizedDescription
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
