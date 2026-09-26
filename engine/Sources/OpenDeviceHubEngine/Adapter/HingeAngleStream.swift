import Foundation
import XPC

/// One reading of the guest's hinge.
public struct HingeSample: Sendable, Hashable {
    /// 0 is shut and 180 is flat open, the scale the guest uses.
    public let degrees: Double
    public let timestamp: Double
}

/// What the guest's motion feature can report.
public struct MotionCapabilities: Sendable, Hashable {
    public let hingeAngle: Bool
    public let deviceMotionState: Bool

    static func parse(_ output: xpc_object_t) -> MotionCapabilities {
        MotionCapabilities(
            hingeAngle: XPCValue.bool(output, "hingeAngle") ?? false,
            deviceMotionState: XPCValue.bool(output, "deviceMotionState") ?? false
        )
    }
}

/// The guest's hinge angle as it changes, whoever is moving it.
///
/// A hinge command only says where this app asked the device to go. The device may be folded by
/// Device Hub, by a pinch in another window, or not at all if the report was ignored, and the
/// model, the toolbar and the active panel all have to follow the guest rather than the command.
/// This is the `streamhingeangle` action that `devicectl device motion hinge-angle` fronts.
public final class HingeAngleStream: @unchecked Sendable {
    public let samples: AsyncStream<HingeSample>
    private let handle: CoreDeviceFeature.StreamHandle

    static let maximumSamplesPerEvent = 64

    init(feature: CoreDeviceFeature) throws {
        var escaping: AsyncStream<HingeSample>.Continuation!
        samples = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { escaping = $0 }
        let continuation = escaping!
        let channel = UUID()
        handle = try feature.stream(
            action: CoreDeviceFeature.hingeStreamAction,
            input: Self.input(channel: channel),
            sideChannel: channel,
            onEvent: { event in
                for sample in Self.samples(in: event) {
                    continuation.yield(sample)
                }
            },
            onEnd: { _ in continuation.finish() }
        )
    }

    public func close() {
        handle.cancel()
    }

    /// Asks for a sample whenever the angle moves a tenth of a degree, at most ten times a second,
    /// pushed back on the named side channel.
    static func input(channel: UUID) -> xpc_object_t {
        let converter = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_double(converter, "coefficient", 1)
        xpc_dictionary_set_double(converter, "constant", 0)
        let unit = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(unit, "symbol", "°")
        xpc_dictionary_set_value(unit, "converter", converter)
        let threshold = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_double(threshold, "value", 0.1)
        xpc_dictionary_set_value(threshold, "unit", unit)

        // A CoreDevice duration: signed high bits then unsigned low bits, in attoseconds.
        let interval = xpc_array_create(nil, 0)
        xpc_array_append_value(interval, xpc_int64_create(0))
        xpc_array_append_value(interval, xpc_uint64_create(100_000_000_000_000_000))

        let actual = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(actual, "changeThreshold", threshold)
        xpc_dictionary_set_value(actual, "updateInterval", interval)
        let proxy = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(proxy, "sideChannel", XPCValue.uuid(channel))

        let input = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(input, "actualInput", actual)
        xpc_dictionary_set_value(input, "streamProxy", proxy)
        return input
    }

    /// The valid samples in one event, in degrees. A sample the guest marks invalid, or one in any
    /// other unit, is not a reading.
    static func samples(in event: xpc_object_t) -> [HingeSample] {
        guard let status = XPCValue.dictionary(event, "CoreDevice.XPCMessageKey.sideChannelStatus"),
              let pushing = XPCValue.dictionary(status, "pushing"),
              let elements = XPCValue.array(pushing, "elements"),
              elements.count <= maximumSamplesPerEvent else { return [] }
        return elements.compactMap { element in
            guard XPCValue.bool(element, "isAngleValid") == true,
                  let timestamp = XPCValue.number(element, "timestamp"),
                  let angle = XPCValue.dictionary(element, "angle"),
                  let value = XPCValue.number(angle, "value"),
                  let unit = XPCValue.dictionary(angle, "unit"),
                  XPCValue.string(unit, "symbol") == "°",
                  value.isFinite else { return nil }
            return HingeSample(degrees: value, timestamp: timestamp)
        }
    }
}
