//
//  The single touch message layout below is adapted from idb (Meta Platforms, MIT) and Siniulator
//  (Krzysztof Magiera, MIT), which arrived at the same envelope independently. See
//  THIRD_PARTY_NOTICES.md.
//

import CoreGraphics
import Foundation

/// Every Indigo wire constant lives here so that a new Xcode can be checked against one file.
/// Each value was confirmed on the build named beside it, by sending a tap that visibly landed,
/// not by reading prior art.
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

    /// The contact did not originate at a screen edge. Verified on Xcode 26.5 (17F42).
    static let edgeNone: UInt32 = 0

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

    typealias MouseMessageBuilder = @convention(c) (
        UnsafeMutablePointer<CGPoint>?,
        UnsafeMutablePointer<CGPoint>?,
        UInt32,
        UInt,
        CGSize,
        UInt32
    ) -> UnsafeMutableRawPointer?
}
