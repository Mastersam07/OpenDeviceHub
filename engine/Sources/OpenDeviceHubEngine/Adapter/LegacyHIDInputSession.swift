//
//  The single touch message construction, and the button and edge values it sends, are adapted
//  from idb (Meta Platforms, MIT) and Siniulator (Krzysztof Magiera, MIT). See
//  THIRD_PARTY_NOTICES.md.
//

import CoreGraphics
import Foundation
import OpenDeviceHubPrivate

/// Sends contacts to a booted device over the legacy Indigo HID path. Sends are serialized because
/// the client is not documented as thread safe.
final class LegacyHIDInputSession: InputSession, @unchecked Sendable {
    private let client: any ODHSimDeviceLegacyHIDClient
    private let buildMouseMessage: IndigoHID.MouseMessageBuilder
    private let buildKeyboardMessage: IndigoHID.KeyboardMessageBuilder
    private let buildButtonMessage: IndigoHID.ButtonMessageBuilder
    private let buildArbitraryMessage: IndigoHID.ArbitraryMessageBuilder
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

        guard let keyboardSymbol = simulatorKit.symbol(named: IndigoHID.keyboardBuilderSymbol) else {
            throw EngineError.symbolNotFound(
                name: IndigoHID.keyboardBuilderSymbol,
                framework: PrivateFramework.simulatorKit.rawValue
            )
        }
        buildKeyboardMessage = unsafeBitCast(keyboardSymbol, to: IndigoHID.KeyboardMessageBuilder.self)

        guard let buttonSymbol = simulatorKit.symbol(named: IndigoHID.buttonBuilderSymbol),
              let arbitrarySymbol = simulatorKit.symbol(named: IndigoHID.arbitraryBuilderSymbol) else {
            throw EngineError.symbolNotFound(
                name: "\(IndigoHID.buttonBuilderSymbol) or \(IndigoHID.arbitraryBuilderSymbol)",
                framework: PrivateFramework.simulatorKit.rawValue
            )
        }
        buildButtonMessage = unsafeBitCast(buttonSymbol, to: IndigoHID.ButtonMessageBuilder.self)
        buildArbitraryMessage = unsafeBitCast(arbitrarySymbol, to: IndigoHID.ArbitraryMessageBuilder.self)

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
        guard (1...2).contains(event.points.count) else {
            throw EngineError.capabilityUnavailable(
                name: "\(event.points.count) contacts, one or two are supported"
            )
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

        let edge = IndigoHID.edgeValue(for: event.edge)
        let message = event.points.count == 1
            ? try makeSingleTouchMessage(point: event.points[0], eventType: eventType, edge: edge)
            : try makeTwoTouchMessage(
                first: event.points[0], second: event.points[1], eventType: eventType, edge: edge
            )
        try await send(message)
    }

    /// Two contacts use the builder's own multi-touch message unchanged. That envelope is exactly
    /// what the single touch path has to undo, so here it is what we want.
    private func makeTwoTouchMessage(
        first: CGPoint,
        second: CGPoint,
        eventType: UInt,
        edge: UInt32
    ) throws -> UnsafeMutableRawPointer {
        var a = CGPoint(x: first.x, y: first.y)
        var b = CGPoint(x: second.x, y: second.y)
        guard let message = buildMouseMessage(
            &a, &b, IndigoHID.touchTarget, eventType, IndigoHID.unitScreenSize, edge
        ) else {
            throw EngineError.privateCall(symbol: IndigoHID.mouseBuilderSymbol, message: "returned nil")
        }
        // The duplicate of the first finger is written too, because the guest reads that payload
        // rather than the first one for the leading contact.
        for (offsets, point) in [
            (IndigoHID.Message.firstContactRatioOffsets, first),
            (IndigoHID.Message.duplicatedFirstContactRatioOffsets, first),
            (IndigoHID.Message.secondContactRatioOffsets, second),
        ] {
            var x = Double(point.x)
            var y = Double(point.y)
            memcpy(message.advanced(by: offsets.x), &x, 8)
            memcpy(message.advanced(by: offsets.y), &y, 8)
        }
        return message
    }

    func key(_ event: KeyEvent) async throws {
        try ensureOpen()
        guard let message = buildKeyboardMessage(Int32(event.usage), event.phase == .down ? 1 : 0) else {
            throw EngineError.privateCall(
                symbol: IndigoHID.keyboardBuilderSymbol,
                message: "returned nil for usage \(event.usage)"
            )
        }
        try await send(message)
    }

    func button(_ button: HardwareButton, phase: ButtonPhase) async throws {
        try ensureOpen()
        let direction = phase == .down ? IndigoHID.buttonDown : IndigoHID.buttonUp

        let message: UnsafeMutableRawPointer?
        if let source = IndigoHID.Button.eventSources[button] {
            message = buildButtonMessage(source, direction, IndigoHID.buttonTarget)
        } else if let usage = IndigoHID.Button.consumerUsages[button] {
            message = buildArbitraryMessage(
                Int32(IndigoHID.touchTarget), IndigoHID.consumerUsagePage, usage, direction
            )
        } else {
            throw EngineError.capabilityUnavailable(name: "hardware button \(button)")
        }

        guard let message else {
            throw EngineError.privateCall(
                symbol: IndigoHID.buttonBuilderSymbol,
                message: "returned nil for \(button)"
            )
        }
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
        eventType: UInt,
        edge: UInt32
    ) throws -> UnsafeMutableRawPointer {
        var contact = CGPoint(x: point.x, y: point.y)
        guard let source = buildMouseMessage(
            &contact,
            nil,
            IndigoHID.touchTarget,
            eventType,
            IndigoHID.unitScreenSize,
            edge
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
