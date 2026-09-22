//
//  Adapted from idb (Meta Platforms, MIT) and Siniulator (Krzysztof Magiera, MIT). From idb: the
//  single touch message layout, the hardware button event sources and targets, the down and up
//  values, the volume consumer usages and the edge values. From Siniulator: the same envelope,
//  reached independently, and the argument order the button builder actually takes. See
//  THIRD_PARTY_NOTICES.md.
//

import CoreGraphics
import Foundation

/// Every Indigo wire constant lives here so that a new Xcode can be checked against one file.
///
/// The touch layout was found by observation. The button and edge values came from idb's header
/// and were then confirmed on the build named beside each one, by pressing the button or making
/// the gesture and watching the device respond. Where a value is carried from prior art without
/// that confirmation, it says so.
enum IndigoHID {
    /// The HID service that handles mouse and touch contacts. Verified on Xcode 26.5 (17F42).
    /// Deliberately not `IndigoHIDTargetForScreen`, which binds to the screen digitizer and
    /// requires the screen to be registered first.
    static let touchTarget: UInt32 = 0x32

    /// Contact down and contact up, passed to the builder as its event type.
    /// Verified on Xcode 26.5 (17F42).
    ///
    /// There is no separate "moved" type. The builder accepts only 1, 2, 3 and 4, and 3 and 4
    /// produce byte identical messages to 1 and 2: same `eventMask` 0x3, same range and touch
    /// flags. A drag is therefore a contact down message repeated at each new position, which was
    /// confirmed by scrolling a list.
    static let eventTypeContactDown: UInt = 1
    static let eventTypeContactUp: UInt = 2

    /// Which edge a contact started at. Verified on Xcode 26.5 (17F42).
    static let edgeNone: UInt32 = 0

    static func edgeValue(for edge: TouchEvent.Edge) -> UInt32 {
        switch edge {
        case .none: 0
        case .top: 1
        case .left: 2
        case .bottom: 3
        case .right: 4
        }
    }

    /// The builder normalizes the point by this size, so a unit size leaves an already normalized
    /// point untouched. Verified on Xcode 26.5 (17F42).
    static let unitScreenSize = CGSize(width: 1, height: 1)

    /// Offsets of the contact ratio inside the builder's message. The struct is four byte packed,
    /// so these doubles are not eight byte aligned. Verified on Xcode 26.5 (17F42).
    static let xRatioOffset = 0x3c
    static let yRatioOffset = 0x44

    /// The hand built single touch message. The builder only ever emits a multi-touch message with
    /// an implicit second contact, which the guest reads as a two finger gesture rather than a tap,
    /// so a fresh envelope is built and the contact copied into it.
    /// Every offset and size verified on Xcode 26.5 (17F42).
    enum Message {
        static let size = 320
        static let innerSizeOffset = 0x18
        /// Also the payload stride used by this buffer, which is why the second payload sits at
        /// `secondPayloadOffset` rather than the 0xa0 stride SimulatorKit uses for its own messages.
        static let innerSize: UInt32 = 144
        static let eventTypeOffset = 0x1c
        static let eventTypeSingleTouch: UInt8 = 2
        static let payloadOffset = 0x20
        static let eventKindOffset = 0x20
        static let eventKindTouch: UInt32 = 11
        static let timestampOffset = 0x24
        static let contactOffset = 0x30
        /// `IndigoTouch` is 116 bytes packed, and the trailing field at 0xa0 is left zero.
        static let contactBytes = 112
        static let secondPayloadOffset = 0xb0
        static let secondContactMarkerOffsets = (first: 0xc0, second: 0xc4)
        static let secondContactMarkers: (first: UInt32, second: UInt32) = (1, 2)
        /// The builder's own multi-touch message, which two finger gestures send unchanged. It is
        /// 512 bytes with an event type byte of 3 and an inner size of 160, and carries three
        /// payloads: the first finger, a duplicate of it at 0xc0, and the second finger at 0x160.
        /// Found by writing distinct ratios and scanning for them, on Xcode 26.5 (17F42).
        static let firstContactRatioOffsets = (x: 0x3c, y: 0x44)
        static let duplicatedFirstContactRatioOffsets = (x: 0xdc, y: 0xe4)
        static let secondContactRatioOffsets = (x: 0x17c, y: 0x184)
    }

    /// `IndigoHIDMessageForMouseNSEvent`, resolved from SimulatorKit with `dlsym`.
    /// Verified on Xcode 26.5 (17F42).
    static let mouseBuilderSymbol = "IndigoHIDMessageForMouseNSEvent"

    /// `IndigoHIDMessageForKeyboardArbitrary(usage, isDown)` returns a complete 192 byte message
    /// that is sent unchanged, no envelope needed. Verified on Xcode 26.5 (17F42), where
    /// `IndigoHIDStringForKeyUsageCode` names 0x04 "A", 0x28 the return arrow and 0x2c "space",
    /// confirming these are standard USB HID keyboard usages.
    static let keyboardBuilderSymbol = "IndigoHIDMessageForKeyboardArbitrary"

    typealias KeyboardMessageBuilder = @convention(c) (Int32, Int32) -> UnsafeMutableRawPointer?

    /// `IndigoHIDMessageForButton(eventSource, direction, target)`. The argument order matters and
    /// is not the one the name suggests: the target comes last and is always `buttonTarget`, while
    /// the button itself is chosen by the event source. Verified on Xcode 26.5 (17F42) by pressing
    /// Home and Lock and watching the device respond.
    static let buttonBuilderSymbol = "IndigoHIDMessageForButton"
    static let buttonTarget: Int32 = 0x33

    /// `IndigoHIDMessageForHIDArbitrary(target, usagePage, usage, direction)`, used for the volume
    /// keys, which travel on the consumer page rather than as buttons.
    static let arbitraryBuilderSymbol = "IndigoHIDMessageForHIDArbitrary"
    static let consumerUsagePage: UInt32 = 0x0c

    /// Down and up for buttons and consumer usages, which is 1 and 2 rather than the 1 and 0 a
    /// boolean would suggest.
    static let buttonDown: Int32 = 1
    static let buttonUp: Int32 = 2

    typealias ButtonMessageBuilder = @convention(c) (Int32, Int32, Int32) -> UnsafeMutableRawPointer?
    typealias ArbitraryMessageBuilder = @convention(c) (Int32, UInt32, UInt32, Int32) -> UnsafeMutableRawPointer?

    /// How each hardware button reaches the guest. Every value confirmed on Xcode 26.5 (17F42).
    enum Button {
        /// Buttons identified by their event source, sent through the button builder.
        static let eventSources: [HardwareButton: Int32] = [
            .home: 0,
            .lock: 1,
            .siri: 0x400002,
        ]

        /// Buttons that are consumer page usages instead.
        static let consumerUsages: [HardwareButton: UInt32] = [
            .volumeUp: 0xe9,
            .volumeDown: 0xea,
        ]
    }

    typealias MouseMessageBuilder = @convention(c) (
        UnsafeMutablePointer<CGPoint>?,
        UnsafeMutablePointer<CGPoint>?,
        UInt32,
        UInt,
        CGSize,
        UInt32
    ) -> UnsafeMutableRawPointer?
}
