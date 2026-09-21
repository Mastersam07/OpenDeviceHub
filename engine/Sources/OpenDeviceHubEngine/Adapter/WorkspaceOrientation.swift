import Darwin
import Foundation

/// Turns the device by sending a GSEvent to the guest's workspace port, which is what the classic
/// Simulator does. Nothing in CoreSimulator or simctl sets orientation on Xcode 26, and `devicectl`
/// does not see simulators there, so this is the only route.
///
/// The message layout is adapted from Siniulator (MIT), which documents it from idb's notes.
/// Verified on Xcode 26.5 (17F42): the guest reported the new orientation afterwards.
enum WorkspaceOrientation {
    static let portName = "PurpleWorkspacePort"

    private static let messageSize: mach_msg_size_t = 108
    private static let bufferSize = 112
    private static let sendTimeoutMilliseconds: mach_msg_timeout_t = 2000

    /// Offsets inside the message, all verified on 17F42.
    private enum Offset {
        static let bits = 0
        static let size = 4
        static let remotePort = 8
        static let identifier = 20
        static let eventType = 0x18
        static let subtype = 0x48
        static let orientation = 0x4c
    }

    private static let headerBits: UInt32 = 0x13
    private static let messageIdentifier: UInt32 = 0x7b
    private static let gsEventType: UInt32 = 50 | 0x20000
    private static let subtypeValue: UInt32 = 4

    static func send(_ orientation: DeviceOrientation, to port: mach_port_t) throws {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: bufferSize)

        func write(_ value: UInt32, at offset: Int) {
            buffer.storeBytes(of: value, toByteOffset: offset, as: UInt32.self)
        }
        write(headerBits, at: Offset.bits)
        write(messageSize, at: Offset.size)
        write(port, at: Offset.remotePort)
        write(messageIdentifier, at: Offset.identifier)
        write(gsEventType, at: Offset.eventType)
        write(subtypeValue, at: Offset.subtype)
        write(orientation.gsEventValue, at: Offset.orientation)

        let result = mach_msg(
            buffer.assumingMemoryBound(to: mach_msg_header_t.self),
            MACH_SEND_MSG | MACH_SEND_TIMEOUT,
            messageSize,
            0,
            mach_port_name_t(MACH_PORT_NULL),
            sendTimeoutMilliseconds,
            mach_port_name_t(MACH_PORT_NULL)
        )
        guard result == KERN_SUCCESS else {
            throw EngineError.privateCall(
                symbol: "mach_msg to \(portName)",
                message: String(cString: mach_error_string(result))
            )
        }
    }
}
