import XCTest
@testable import OpenDeviceHubViewer

/// A 1512x982 laptop screen minus the menu bar, in AppKit coordinates.
private let visible = CGRect(x: 0, y: 0, width: 1512, height: 957)
private let phone = CGSize(width: 402, height: 906)
private let pad = CGSize(width: 744, height: 1165)

final class WindowPlacementTests: XCTestCase {
    func testTheFirstWindowGoesToTheTopLeft() {
        let origin = WindowPlacement.nextOrigin(for: phone, placed: [], in: visible, gap: 12)
        XCTAssertEqual(origin, CGPoint(x: 0, y: 957 - 906))
    }

    func testTheSecondWindowGoesToTheRightOfTheFirst() {
        let first = CGRect(origin: CGPoint(x: 0, y: 51), size: phone)
        let origin = WindowPlacement.nextOrigin(for: phone, placed: [first], in: visible, gap: 12)
        XCTAssertEqual(origin.x, 414)
        XCTAssertEqual(origin.y, 51)
    }

    func testWindowsDoNotOverlapWhenTheyFitSideBySide() {
        var placed: [CGRect] = []
        for _ in 0..<3 {
            let origin = WindowPlacement.nextOrigin(for: phone, placed: placed, in: visible, gap: 12)
            placed.append(CGRect(origin: origin, size: phone))
        }
        for (i, a) in placed.enumerated() {
            for b in placed[(i + 1)...] {
                XCTAssertFalse(a.intersects(b), "\(a) overlaps \(b)")
            }
        }
    }

    func testItWrapsToANewRowWhenThereIsNoWidthLeft() {
        let a = CGRect(origin: CGPoint(x: 0, y: -208), size: pad)
        let b = CGRect(origin: CGPoint(x: 756, y: -208), size: pad)
        let origin = WindowPlacement.nextOrigin(for: pad, placed: [a, b], in: visible, gap: 12)
        XCTAssertEqual(origin.x, 0, "a wrapped window starts at the left edge")
        XCTAssertLessThan(origin.y, a.minY, "and sits below the existing row")
    }

    func testAWindowWiderThanTheScreenStillGetsAnOrigin() {
        let huge = CGSize(width: 2000, height: 900)
        let origin = WindowPlacement.nextOrigin(for: huge, placed: [], in: visible, gap: 12)
        XCTAssertEqual(origin, CGPoint(x: 0, y: 57))
    }
}

final class WindowFrameCodecTests: XCTestCase {
    func testRoundTripsAFrame() {
        let frame = CGRect(x: 120, y: 44, width: 402, height: 906)
        let decoded = WindowFrameCodec.decode(WindowFrameCodec.encode(frame))
        XCTAssertEqual(decoded, frame)
    }

    func testRoundTripsNegativeOrigins() {
        let frame = CGRect(x: -50.5, y: -12.25, width: 402, height: 906)
        XCTAssertEqual(WindowFrameCodec.decode(WindowFrameCodec.encode(frame)), frame)
    }

    func testRejectsMalformedText() {
        XCTAssertNil(WindowFrameCodec.decode(""))
        XCTAssertNil(WindowFrameCodec.decode("1,2,3"))
        XCTAssertNil(WindowFrameCodec.decode("1,2,3,4,5"))
        XCTAssertNil(WindowFrameCodec.decode("a,b,c,d"))
    }

    func testRejectsAFrameWithNoArea() {
        XCTAssertNil(WindowFrameCodec.decode("0,0,0,900"))
        XCTAssertNil(WindowFrameCodec.decode("0,0,400,0"))
        XCTAssertNil(WindowFrameCodec.decode("0,0,-400,900"))
    }
}

private final class InMemoryFrameStorage: PreferenceStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func text(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func setText(_ text: String, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = text
    }

    func removeText(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = nil
    }

    func keys(withPrefix prefix: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return values.keys.filter { $0.hasPrefix(prefix) }
    }
}

final class WindowFrameStoreTests: XCTestCase {
    private func makeStore() -> WindowFrameStore {
        WindowFrameStore(storage: InMemoryFrameStorage(), prefix: "t.")
    }

    func testItCountsWhatItRemembers() {
        let store = makeStore()
        XCTAssertEqual(store.rememberedCount, 0)
        store.save(CGRect(x: 0, y: 0, width: 400, height: 900), for: "a")
        store.save(CGRect(x: 10, y: 10, width: 400, height: 900), for: "b")
        XCTAssertEqual(store.rememberedCount, 2)
    }

    /// By prefix rather than by asking the adapter which devices exist, because a device deleted
    /// since its window was placed still has a key and would otherwise be left behind for ever.
    func testForgettingEverythingLeavesNothingBehind() {
        let store = makeStore()
        store.save(CGRect(x: 0, y: 0, width: 400, height: 900), for: "a")
        store.save(CGRect(x: 10, y: 10, width: 400, height: 900), for: "deleted-device")
        store.forgetAll()
        XCTAssertEqual(store.rememberedCount, 0)
        XCTAssertNil(store.frame(for: "a"))
        XCTAssertNil(store.frame(for: "deleted-device"))
    }

    func testForgettingEverythingLeavesOtherSettingsAlone() {
        let storage = InMemoryFrameStorage()
        storage.setText("keep me", forKey: "other.thing")
        let store = WindowFrameStore(storage: storage, prefix: "t.")
        store.save(CGRect(x: 0, y: 0, width: 400, height: 900), for: "a")
        store.forgetAll()
        XCTAssertEqual(storage.text(forKey: "other.thing"), "keep me")
    }

    func testRemembersAFramePerDevice() {
        let store = makeStore()
        let a = CGRect(x: 10, y: 20, width: 402, height: 906)
        let b = CGRect(x: 500, y: 20, width: 744, height: 1165)
        store.save(a, for: "UDID-A")
        store.save(b, for: "UDID-B")
        XCTAssertEqual(store.frame(for: "UDID-A"), a)
        XCTAssertEqual(store.frame(for: "UDID-B"), b)
    }

    func testAnUnknownDeviceHasNoFrame() {
        XCTAssertNil(makeStore().frame(for: "UDID-MISSING"))
    }

    func testForgettingOneDeviceLeavesTheOther() {
        let store = makeStore()
        store.save(CGRect(x: 1, y: 2, width: 3, height: 4), for: "A")
        store.save(CGRect(x: 5, y: 6, width: 7, height: 8), for: "B")
        store.forget("A")
        XCTAssertNil(store.frame(for: "A"))
        XCTAssertNotNil(store.frame(for: "B"))
    }

    func testAFrameSurvivesAStoreRecreatedOverTheSameStorage() {
        let storage = InMemoryFrameStorage()
        let frame = CGRect(x: 900, y: -197, width: 335, height: 759)
        WindowFrameStore(storage: storage, prefix: "t.").save(frame, for: "A")
        XCTAssertEqual(WindowFrameStore(storage: storage, prefix: "t.").frame(for: "A"), frame)
    }

    func testCorruptStoredTextIsIgnoredRatherThanCrashing() {
        let storage = InMemoryFrameStorage()
        storage.setText("not a frame", forKey: "t.A")
        XCTAssertNil(WindowFrameStore(storage: storage, prefix: "t.").frame(for: "A"))
    }
}
