import XCTest
@testable import OpenDeviceHubEngine

private let centre = CGPoint(x: 0.5, y: 0.5)

final class TwoFingerGestureTests: XCTestCase {
    func testContactsSitOppositeEachOtherAboutTheCentre() {
        let contacts = TwoFingerGesture.contacts(centre: centre, spread: 0.4, angle: 0)
        XCTAssertEqual(contacts.count, 2)
        XCTAssertEqual(contacts[0].x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(contacts[1].x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(contacts[0].y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(contacts[1].y, 0.5, accuracy: 0.0001)
    }

    func testTheMidpointIsAlwaysTheCentre() {
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: 0.4) {
            let contacts = TwoFingerGesture.contacts(centre: centre, spread: 0.5, angle: CGFloat(angle))
            XCTAssertEqual((contacts[0].x + contacts[1].x) / 2, 0.5, accuracy: 0.0001)
            XCTAssertEqual((contacts[0].y + contacts[1].y) / 2, 0.5, accuracy: 0.0001)
        }
    }

    func testAQuarterTurnPutsTheContactsOnTheOtherAxis() {
        let contacts = TwoFingerGesture.contacts(centre: centre, spread: 0.4, angle: .pi / 2)
        XCTAssertEqual(contacts[0].x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(contacts[0].y, 0.7, accuracy: 0.0001)
    }

    func testAZeroSpreadPutsBothContactsAtTheCentre() {
        let contacts = TwoFingerGesture.contacts(centre: centre, spread: 0, angle: 0)
        XCTAssertEqual(contacts[0], centre)
        XCTAssertEqual(contacts[1], centre)
    }

    func testContactsAreClampedToTheScreen() {
        let contacts = TwoFingerGesture.contacts(centre: centre, spread: 4, angle: 0)
        for contact in contacts {
            XCTAssertTrue((0...1).contains(contact.x))
            XCTAssertTrue((0...1).contains(contact.y))
        }
    }

    func testANegativeSpreadIsTreatedAsZero() {
        let contacts = TwoFingerGesture.contacts(centre: centre, spread: -1, angle: 0)
        XCTAssertEqual(contacts[0], centre)
    }

    func testMirroringReflectsThroughTheCentre() {
        let mirrored = TwoFingerGesture.mirrored(CGPoint(x: 0.7, y: 0.6), about: centre)
        XCTAssertEqual(mirrored.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(mirrored.y, 0.4, accuracy: 0.0001)
        XCTAssertEqual(TwoFingerGesture.mirrored(centre, about: centre), centre)
    }

    func testMirroringIsClampedAndStaysOnScreen() {
        let mirrored = TwoFingerGesture.mirrored(CGPoint(x: 1, y: 1), about: CGPoint(x: 0.2, y: 0.2))
        XCTAssertTrue((0...1).contains(mirrored.x))
        XCTAssertTrue((0...1).contains(mirrored.y))
    }

    func testTheOffsetPartnerTravelsWithThePointer() {
        let offset = CGSize(width: 0.12, height: 0)
        let a = TwoFingerGesture.offsetPartner(CGPoint(x: 0.3, y: 0.5), by: offset)
        let b = TwoFingerGesture.offsetPartner(CGPoint(x: 0.5, y: 0.5), by: offset)
        XCTAssertEqual(b.x - a.x, 0.2, accuracy: 0.0001, "both fingers move by the same amount")
    }

    func testPanningMovesBothContactsEqually() {
        let contacts = [CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.6, y: 0.6)]
        let panned = TwoFingerGesture.panned(contacts: contacts, by: CGPoint(x: 0.1, y: -0.1))
        XCTAssertEqual(panned[0].x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(panned[0].y, 0.3, accuracy: 0.0001)
        XCTAssertEqual(panned[1].x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(panned[1].y, 0.5, accuracy: 0.0001)
    }
}
