import CoreGraphics
import Foundation
import XCTest
import Testing
@testable import OpenDeviceHubEngine

private func makeElement(frame: CGRect, children: [AccessibilityElement] = []) -> AccessibilityElement {
    AccessibilityElement(
        role: "AXButton",
        roleDescription: "button",
        label: "Save",
        title: nil,
        identifier: "save",
        value: nil,
        frame: frame,
        children: children
    )
}

private let screen = CGRect(x: 0, y: 0, width: 402, height: 874)

final class AccessibilityElementCenterTests: XCTestCase {
    func testCenterIsAFractionOfTheScreen() throws {
        let element = makeElement(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let center = try XCTUnwrap(element.normalizedCenter(in: screen))
        XCTAssertEqual(center.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)
    }

    func testCenterOfASmallElement() throws {
        let element = makeElement(frame: CGRect(x: 20, y: 60, width: 40, height: 40))
        let center = try XCTUnwrap(element.normalizedCenter(in: screen))
        XCTAssertEqual(center.x, 40.0 / 402.0, accuracy: 0.0001)
        XCTAssertEqual(center.y, 80.0 / 874.0, accuracy: 0.0001)
    }

    func testCenterFollowsAScreenThatDoesNotStartAtTheOrigin() throws {
        let offset = CGRect(x: 100, y: 200, width: 402, height: 874)
        let element = makeElement(frame: CGRect(x: 100, y: 200, width: 402, height: 874))
        let center = try XCTUnwrap(element.normalizedCenter(in: offset))
        XCTAssertEqual(center.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)
    }

    func testAnElementScrolledOffScreenHasNoCenter() {
        let element = makeElement(frame: CGRect(x: 20, y: 1_200, width: 40, height: 40))
        XCTAssertNil(element.normalizedCenter(in: screen))
    }

    func testAScreenWithNoSizeGivesNoCenter() {
        let element = makeElement(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertNil(element.normalizedCenter(in: .zero))
    }
}

final class AccessibilityElementCodingTests: XCTestCase {
    func testRoundTripsThroughJSON() throws {
        let tree = makeElement(
            frame: screen,
            children: [makeElement(frame: CGRect(x: 20, y: 60, width: 40, height: 40))]
        )
        let data = try JSONEncoder().encode(tree)
        XCTAssertEqual(try JSONDecoder().decode(AccessibilityElement.self, from: data), tree)
    }
}

struct AccessibilityElementCoordinateTests {
    @Test(arguments: [
        CGRect.zero,
        CGRect(x: 20, y: 60, width: 0, height: 40),
        CGRect(x: 20, y: 60, width: 40, height: 0),
    ])
    func emptyFramesHaveNoCenter(frame: CGRect) {
        let element = makeElement(frame: frame)
        #expect(element.normalizedCenter(in: screen) == nil)
    }

    @Test(arguments: [
        (DeviceOrientation.portrait, CGPoint(x: 0.2, y: 0.3)),
        (.landscapeLeft, CGPoint(x: 0.3, y: 0.8)),
        (.portraitUpsideDown, CGPoint(x: 0.8, y: 0.7)),
        (.landscapeRight, CGPoint(x: 0.7, y: 0.2)),
    ])
    func centersUsePortraitNativeCoordinates(orientation: DeviceOrientation, expected: CGPoint) throws {
        let displayedSize = orientation.displayedSize(portraitNative: screen.size)
        let displayedScreen = CGRect(origin: .zero, size: displayedSize)
        let element = makeElement(frame: CGRect(
            x: displayedSize.width * 0.2 - 10,
            y: displayedSize.height * 0.3 - 10,
            width: 20, height: 20
        ))

        let center = try #require(element.normalizedCenter(in: displayedScreen, orientation: orientation))

        #expect(abs(center.x - expected.x) < 0.0001)
        #expect(abs(center.y - expected.y) < 0.0001)
    }
}

struct AccessibilitySelectorCheckTests {
    @Test func availableSelectorsAreAccepted() throws {
        try AccessibilitySelectorCheck.require(on: NSObject(), selectors: ["description", "respondsToSelector:"])
    }

    @Test func missingSelectorsReportTheUnsupportedCapability() {
        let object = NSObject()
        let error = EngineError.symbolNotFound(
            name: "-[NSObject setBridgeDelegateToken:]",
            framework: PrivateFramework.accessibilityPlatformTranslation.rawValue
        )

        #expect(throws: error) {
            try AccessibilitySelectorCheck.require(on: object, selectors: ["description", "setBridgeDelegateToken:"])
        }
    }
}
