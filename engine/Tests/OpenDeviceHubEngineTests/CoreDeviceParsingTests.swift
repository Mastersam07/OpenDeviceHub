import Foundation
import Testing
import XPC
@testable import OpenDeviceHubEngine

/// The guest's hinge events and HID service listing, read the way it writes them.
@Suite struct CoreDeviceParsingTests {
    private func hingeEvent(_ readings: [(valid: Bool, degrees: Double, unit: String)]) -> xpc_object_t {
        let elements = xpc_array_create(nil, 0)
        for (index, reading) in readings.enumerated() {
            let converter = xpc_dictionary_create(nil, nil, 0)
            xpc_dictionary_set_double(converter, "coefficient", 1)
            xpc_dictionary_set_double(converter, "constant", 0)
            let unit = xpc_dictionary_create(nil, nil, 0)
            xpc_dictionary_set_string(unit, "symbol", reading.unit)
            xpc_dictionary_set_value(unit, "converter", converter)
            let angle = xpc_dictionary_create(nil, nil, 0)
            xpc_dictionary_set_double(angle, "value", reading.degrees)
            xpc_dictionary_set_value(angle, "unit", unit)
            let element = xpc_dictionary_create(nil, nil, 0)
            xpc_dictionary_set_bool(element, "isAngleValid", reading.valid)
            xpc_dictionary_set_double(element, "timestamp", Double(index))
            xpc_dictionary_set_value(element, "angle", angle)
            xpc_array_append_value(elements, element)
        }
        let pushing = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(pushing, "elements", elements)
        let status = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(status, "pushing", pushing)
        let event = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(event, "XPCSideChannel.uniqueIdentifier", UUID().uuidString)
        xpc_dictionary_set_value(event, "CoreDevice.XPCMessageKey.sideChannelStatus", status)
        return event
    }

    @Test func keepsOnlyValidReadingsInDegrees() {
        let samples = HingeAngleStream.samples(in: hingeEvent([
            (true, 120, "°"),
            (false, 90, "°"),
            (true, 2.1, "rad"),
            (true, 180, "°"),
        ]))
        #expect(samples.map(\.degrees) == [120, 180])
        #expect(samples.map(\.timestamp) == [0, 3])
    }

    @Test func anEventWithoutAStatusIsNoReading() {
        let event = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(event, "XPCSideChannel.uniqueIdentifier", "x")
        #expect(HingeAngleStream.samples(in: event).isEmpty)
    }

    @Test func theStreamInputNamesItsChannelAndItsUnit() {
        let channel = UUID()
        let input = HingeAngleStream.input(channel: channel)
        let proxy = try? #require(XPCValue.dictionary(input, "streamProxy"))
        let side = proxy.flatMap { xpc_dictionary_get_value($0, "sideChannel") }
        #expect(side.map { xpc_get_type($0) == XPC_TYPE_UUID } == true)
        let actual = XPCValue.dictionary(input, "actualInput")
        let threshold = actual.flatMap { XPCValue.dictionary($0, "changeThreshold") }
        #expect(threshold.flatMap { XPCValue.number($0, "value") } == 0.1)
        let interval = actual.flatMap { XPCValue.array($0, "updateInterval") }
        #expect(interval?.count == 2)
    }

    private func service(page: Int64, usage: Int64, id: UInt64, display: String?) -> xpc_object_t {
        let entry = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_int64(entry, "PrimaryUsagePage", page)
        xpc_dictionary_set_int64(entry, "PrimaryUsage", usage)
        xpc_dictionary_set_uint64(entry, "_ServiceID", id)
        if let display { xpc_dictionary_set_string(entry, "displayUUID", display) }
        return entry
    }

    private func listing(_ services: [xpc_object_t]) -> xpc_object_t {
        let array = xpc_array_create(nil, 0)
        for service in services { xpc_array_append_value(array, service) }
        let reply = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(reply, "connectedServices", array)
        return reply
    }

    @Test func touchscreensAreJoinedToTheirDisplays() throws {
        let touchscreens = try Touchscreen.parse(listing([
            service(page: 0x0D, usage: 0x04, id: 0x101, display: "cover"),
            service(page: 0x01, usage: 0x06, id: 0x64, display: nil),
            service(page: 0x0D, usage: 0x04, id: 0x103, display: "inner"),
        ]))
        #expect(touchscreens.map(\.target) == [1, 3])
        #expect(touchscreens.map(\.displayUniqueID) == ["cover", "inner"])
    }

    @Test func aTouchscreenWithoutAnExplicitTargetIsRefused() {
        #expect(throws: (any Error).self) {
            try Touchscreen.parse(listing([service(page: 0x0D, usage: 0x04, id: 0x32, display: "cover")]))
        }
    }

    @Test func theRequestSpeaksTheServicesOwnDialect() {
        let request = Touchscreen.request()
        #expect(XPCValue.bool(request, "isBarrier") == false)
        let payload = XPCValue.dictionary(request, "payload")
        #expect(payload.flatMap { XPCValue.dictionary($0, "connectedServices") } != nil)
    }
}
