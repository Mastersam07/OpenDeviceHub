import XCTest
@testable import OpenDeviceHubEngine

final class KeyboardMapTests: XCTestCase {
    func testTheLettersFollowTheHIDKeyboardPage() {
        // kVK_ANSI_A is 0x00 and HID usage 0x04 is "a"; the rest of the alphabet follows.
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x00), 0x04)
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x06), 0x1D, "z")
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x08), 0x06, "c")
    }

    func testDigitsMapOneThroughNineThenZero() {
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x12), 0x1E, "1")
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x1D), 0x27, "0")
    }

    func testCommonControlKeys() {
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x24), 0x28, "return")
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x35), 0x29, "escape")
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x33), 0x2A, "delete")
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x31), 0x2C, "space")
    }

    func testArrowKeys() {
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x7B), 0x50, "left")
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x7C), 0x4F, "right")
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x7D), 0x51, "down")
        XCTAssertEqual(KeyboardMap.usage(forVirtualKeyCode: 0x7E), 0x52, "up")
    }

    func testAnUnknownKeyCodeHasNoUsage() {
        XCTAssertNil(KeyboardMap.usage(forVirtualKeyCode: 0xFF))
    }

    func testEveryUsageIsDistinct() {
        let usages = Array(KeyboardMap.usageByVirtualKeyCode.values)
        XCTAssertEqual(Set(usages).count, usages.count, "two key codes map to the same usage")
    }

    func testEveryUsageIsOnTheKeyboardPage() {
        for usage in KeyboardMap.usageByVirtualKeyCode.values {
            XCTAssertTrue((0x04...0x73).contains(usage), "usage \(usage) is outside the keyboard page")
        }
    }

    func testTypingASimpleString() throws {
        let usages = try XCTUnwrap(KeyboardMap.usages(forTyping: "abc 12"))
        XCTAssertEqual(usages, [0x04, 0x05, 0x06, 0x2C, 0x1E, 0x1F])
    }

    func testTypingIsCaseInsensitiveBecauseThereIsNoShiftYet() {
        XCTAssertEqual(KeyboardMap.usages(forTyping: "ABC"), KeyboardMap.usages(forTyping: "abc"))
    }

    func testTypingRefusesCharactersWithNoUnshiftedKey() {
        XCTAssertNil(KeyboardMap.usages(forTyping: "hello!"))
        XCTAssertNil(KeyboardMap.usages(forTyping: "caf\u{e9}"))
    }

    func testTypingAnEmptyStringProducesNoKeys() {
        XCTAssertEqual(KeyboardMap.usages(forTyping: ""), [])
    }
}
