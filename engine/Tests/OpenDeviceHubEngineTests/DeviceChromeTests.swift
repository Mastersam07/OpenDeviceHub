import XCTest
@testable import OpenDeviceHubEngine

/// Trimmed from the real `phone11.devicechrome`, keeping the fields the viewer reads.
private let sampleJSON = """
{
  "identifier": "com.apple.dt.devicekit.chrome.phone11",
  "images": {
    "composite": "PhoneComposite",
    "screen": "Screen",
    "sizing": { "leftWidth": 18, "rightWidth": 18, "topHeight": 18, "bottomHeight": 18 },
    "padding": { "width": 9, "height": 0 },
    "devicePadding": { "top": 0, "left": 9, "bottom": 0, "right": 9 }
  },
  "paths": {
    "simpleOutsideBorder": {
      "insets": { "top": 0, "left": 0, "bottom": 0, "right": 0 },
      "cornerRadiusX": 80,
      "cornerRadiusY": 80
    }
  },
  "inputs": [
    { "name": "action", "accessibilityTitle": "Action", "type": "button", "usagePage": 11,
      "usage": 45, "image": "Mute BTN", "imageDown": "Mute BTN Dn", "anchor": "left",
      "offsets": { "normal": { "x": 8, "y": 160 }, "rollover": { "x": 3, "y": 160 } } },
    { "name": "volume-up", "accessibilityTitle": "Volume Up", "type": "button", "usagePage": 12,
      "usage": 233, "image": "Vol BTN", "imageDown": "Vol BTN Dn", "anchor": "left",
      "offsets": { "normal": { "x": 8, "y": 221 }, "rollover": { "x": 3, "y": 221 } } },
    { "name": "power", "accessibilityTitle": "Sleep/Wake", "type": "button", "usagePage": 12,
      "usage": 48, "image": "X_Power BTN", "imageDown": "X_Power BTN Dn", "anchor": "right",
      "offsets": { "normal": { "x": -8, "y": 262 }, "rollover": { "x": -3, "y": 262 } } },
    { "name": "not-a-button", "type": "slider", "anchor": "left" }
  ]
}
"""

private func makeChrome() throws -> DeviceChrome {
    try DeviceChrome.parse(
        json: Data(sampleJSON.utf8),
        bundle: URL(fileURLWithPath: "/tmp/phone11.devicechrome")
    )
}

final class DeviceChromeParsingTests: XCTestCase {
    func testReadsTheIdentifierAndBodyThickness() throws {
        let chrome = try makeChrome()
        XCTAssertEqual(chrome.identifier, "com.apple.dt.devicekit.chrome.phone11")
        XCTAssertEqual(chrome.insets.left, 18)
        XCTAssertEqual(chrome.insets.bottom, 18)
        XCTAssertEqual(chrome.cornerRadius, 80)
        XCTAssertEqual(chrome.compositeImage, "PhoneComposite")
    }

    func testReadsThePaddingThatLetsButtonsStandProud() throws {
        let chrome = try makeChrome()
        XCTAssertEqual(chrome.devicePadding.left, 9)
        XCTAssertEqual(chrome.devicePadding.right, 9)
        XCTAssertEqual(chrome.devicePadding.top, 0)
    }

    func testKeepsOnlyTheButtons() throws {
        let chrome = try makeChrome()
        XCTAssertEqual(chrome.buttons.map(\.name), ["action", "volume-up", "power"])
    }

    /// The chrome names the same consumer page usages the adapter already sends, which is a useful
    /// independent check on values that were read out of idb's header.
    func testTheHIDCodesMatchWhatTheAdapterSends() throws {
        let chrome = try makeChrome()
        let volumeUp = try XCTUnwrap(chrome.buttons.first { $0.name == "volume-up" })
        XCTAssertEqual(volumeUp.usagePage, 0x0c)
        XCTAssertEqual(volumeUp.usage, 0xe9)

        let power = try XCTUnwrap(chrome.buttons.first { $0.name == "power" })
        XCTAssertEqual(power.usagePage, 0x0c)
        XCTAssertEqual(power.usage, 0x30)
    }

    func testCarriesBothArtworkNamesAndTheAnchor() throws {
        let chrome = try makeChrome()
        let power = try XCTUnwrap(chrome.buttons.first { $0.name == "power" })
        XCTAssertEqual(power.anchor, .right)
        XCTAssertEqual(power.offset, CGPoint(x: -8, y: 262))
        XCTAssertEqual(power.image, "X_Power BTN")
        XCTAssertEqual(power.imageDown, "X_Power BTN Dn")
        XCTAssertEqual(power.title, "Sleep/Wake")
    }

    /// Side buttons sit under the body so only the part standing proud shows, while the Home
    /// button is drawn over it.
    func testTheSideButtonsAreUnderTheBodyAndHomeIsOverIt() throws {
        let chrome = try makeChrome()
        for name in ["action", "volume-up", "power"] {
            let button = try XCTUnwrap(chrome.buttons.first { $0.name == name })
            XCTAssertFalse(button.onTop, "\(name) belongs under the body")
        }
    }

    func testTheRolloverOffsetIsKeptSeparately() throws {
        let chrome = try makeChrome()
        let volume = try XCTUnwrap(chrome.buttons.first { $0.name == "volume-up" })
        XCTAssertEqual(volume.offset.x, 8)
        XCTAssertEqual(volume.rolloverOffset.x, 3)
    }

    func testAButtonWithNoRolloverKeepsItsNormalOffset() throws {
        let json = """
        {"identifier":"x","images":{},"inputs":[
          {"name":"b","type":"button","image":"B","anchor":"left","offsets":{"normal":{"x":5,"y":6}}}
        ]}
        """
        let chrome = try DeviceChrome.parse(json: Data(json.utf8), bundle: URL(fileURLWithPath: "/tmp/x"))
        XCTAssertEqual(chrome.buttons.first?.rolloverOffset, CGPoint(x: 5, y: 6))
    }

    func testAButtonWithNoImageDownFallsBackToItsNormalArtwork() throws {
        let json = """
        {"identifier":"x","images":{},"inputs":[
          {"name":"b","type":"button","image":"B","anchor":"left","offsets":{"normal":{"x":1,"y":2}}}
        ]}
        """
        let chrome = try DeviceChrome.parse(json: Data(json.utf8), bundle: URL(fileURLWithPath: "/tmp/x"))
        XCTAssertEqual(chrome.buttons.first?.imageDown, "B")
    }

    func testRejectsSomethingThatIsNotAChromeDescription() {
        XCTAssertThrowsError(
            try DeviceChrome.parse(json: Data("{}".utf8), bundle: URL(fileURLWithPath: "/tmp/x"))
        )
    }

    func testResourcesResolveInsideTheBundle() throws {
        let chrome = try makeChrome()
        XCTAssertEqual(
            chrome.compositeURL?.path,
            "/tmp/phone11.devicechrome/Contents/Resources/PhoneComposite.pdf"
        )
    }

    /// The home button phones ship the eight pieces and no single body, so a bundle with no
    /// composite still has to describe itself completely.
    func testABundleWithNoCompositeStillCarriesItsPieces() throws {
        let json = """
        {"identifier":"com.apple.dt.devicekit.chrome.phone","images":{
          "topLeft":"Phone TL","top":"PhoneTop","topRight":"Phone TR",
          "left":"PhoneLeft","right":"PhoneRight",
          "bottomLeft":"Phone BL","bottom":"PhoneBase","bottomRight":"Phone BR",
          "sizing":{"leftWidth":28,"rightWidth":28,"topHeight":111,"bottomHeight":111},
          "devicePadding":{"top":0,"left":9,"bottom":0,"right":9}}}
        """
        let chrome = try DeviceChrome.parse(
            json: Data(json.utf8), bundle: URL(fileURLWithPath: "/tmp/phone.devicechrome")
        )
        XCTAssertNil(chrome.compositeImage)
        XCTAssertNil(chrome.compositeURL)
        let slices = try XCTUnwrap(chrome.slices)
        XCTAssertEqual(slices.top, "PhoneTop")
        XCTAssertEqual(slices.bottom, "PhoneBase")
        XCTAssertEqual(chrome.insets.top, 111)
    }

    func testAHomeButtonPhoneLeavesRoomForItsTallTopAndBottom() throws {
        let json = """
        {"identifier":"x","images":{
          "topLeft":"a","top":"b","topRight":"c","left":"d","right":"e",
          "bottomLeft":"f","bottom":"g","bottomRight":"h",
          "sizing":{"leftWidth":28,"rightWidth":28,"topHeight":111,"bottomHeight":111},
          "devicePadding":{"top":0,"left":9,"bottom":0,"right":9}}}
        """
        let chrome = try DeviceChrome.parse(
            json: Data(json.utf8), bundle: URL(fileURLWithPath: "/tmp/x")
        )
        let content = ChromeGeometry.contentSize(
            screen: CGSize(width: 375, height: 667), chrome: chrome
        )
        XCTAssertEqual(content.width, 375 + 56 + 18)
        XCTAssertEqual(content.height, 667 + 222)
    }
}

final class ChromeGeometryTests: XCTestCase {
    private let screen = CGSize(width: 402, height: 874)

    func testTheWindowAllowsForTheBodyAndTheProudButtons() throws {
        let content = ChromeGeometry.contentSize(screen: screen, chrome: try makeChrome())
        // 402 + 18 + 18 body, plus 9 either side for the buttons.
        XCTAssertEqual(content.width, 456)
        XCTAssertEqual(content.height, 910)
    }

    func testTheBodySitsInsideThePadding() throws {
        let chrome = try makeChrome()
        let content = ChromeGeometry.contentSize(screen: screen, chrome: chrome)
        let body = ChromeGeometry.bodyRect(content: content, chrome: chrome)
        XCTAssertEqual(body, CGRect(x: 9, y: 0, width: 438, height: 910))
    }

    func testTheScreenEndsUpItsOriginalSize() throws {
        let chrome = try makeChrome()
        let content = ChromeGeometry.contentSize(screen: screen, chrome: chrome)
        let rect = ChromeGeometry.screenRect(content: content, chrome: chrome)
        XCTAssertEqual(rect.size, screen)
        XCTAssertEqual(rect.origin, CGPoint(x: 27, y: 18))
    }

    func testARightAnchoredButtonIsMeasuredBackFromTheRightEdge() throws {
        let chrome = try makeChrome()
        let content = ChromeGeometry.contentSize(screen: screen, chrome: chrome)
        let power = try XCTUnwrap(chrome.buttons.first { $0.name == "power" })
        let rect = ChromeGeometry.buttonRect(
            power, imageSize: CGSize(width: 16, height: 101), content: content, chrome: chrome
        )
        XCTAssertEqual(rect.minX, 456 - 16 - 8)
        XCTAssertEqual(rect.maxY, 910 - 262)
    }

    func testALeftAnchoredButtonIsMeasuredFromTheLeftEdge() throws {
        let chrome = try makeChrome()
        let content = ChromeGeometry.contentSize(screen: screen, chrome: chrome)
        let volume = try XCTUnwrap(chrome.buttons.first { $0.name == "volume-up" })
        let rect = ChromeGeometry.buttonRect(
            volume, imageSize: CGSize(width: 16, height: 64), content: content, chrome: chrome
        )
        XCTAssertEqual(rect.minX, 8)
        XCTAssertEqual(rect.maxY, 910 - 221)
    }

    func testAClickOnAButtonFindsIt() throws {
        let chrome = try makeChrome()
        let content = ChromeGeometry.contentSize(screen: screen, chrome: chrome)
        let sizes = ["Vol BTN": CGSize(width: 16, height: 64), "X_Power BTN": CGSize(width: 16, height: 101)]
        let volume = try XCTUnwrap(chrome.buttons.first { $0.name == "volume-up" })
        let rect = ChromeGeometry.buttonRect(
            volume, imageSize: sizes["Vol BTN"]!, content: content, chrome: chrome
        )
        let hit = ChromeGeometry.button(
            at: CGPoint(x: rect.midX, y: rect.midY), sizes: sizes, content: content, chrome: chrome
        )
        XCTAssertEqual(hit?.name, "volume-up")
    }

    /// The Home button is anchored to the bottom and its y is negative, measured up from there,
    /// which is not how the side buttons are described.
    func testABottomAnchoredButtonSitsInsideTheBottomBezel() throws {
        let json = """
        {"identifier":"x","images":{
          "topLeft":"a","top":"b","topRight":"c","left":"d","right":"e",
          "bottomLeft":"f","bottom":"g","bottomRight":"h",
          "sizing":{"leftWidth":28,"rightWidth":28,"topHeight":111,"bottomHeight":111},
          "devicePadding":{"top":0,"left":9,"bottom":0,"right":9}},
         "inputs":[{"name":"home","type":"button","image":"Home BTN","anchor":"bottom",
                    "offsets":{"normal":{"x":0,"y":-90}}}]}
        """
        let chrome = try DeviceChrome.parse(
            json: Data(json.utf8), bundle: URL(fileURLWithPath: "/tmp/x")
        )
        let content = ChromeGeometry.contentSize(
            screen: CGSize(width: 375, height: 667), chrome: chrome
        )
        let home = try XCTUnwrap(chrome.buttons.first)
        let rect = ChromeGeometry.buttonRect(
            home, imageSize: CGSize(width: 67, height: 67), content: content, chrome: chrome
        )
        XCTAssertEqual(rect.maxY, 90)
        XCTAssertEqual(rect.midX, content.width / 2, accuracy: 0.5)
        XCTAssertTrue(rect.minY > 0, "must sit inside the bottom bezel, not below the window")
    }

    /// Hovering slides a side button further out of the body, which is what makes it look like it
    /// rises under the pointer.
    func testHoveringMovesASideButtonFurtherOut() throws {
        let chrome = try makeChrome()
        let content = ChromeGeometry.contentSize(screen: screen, chrome: chrome)
        let volume = try XCTUnwrap(chrome.buttons.first { $0.name == "volume-up" })
        let size = CGSize(width: 16, height: 64)
        let resting = ChromeGeometry.buttonRect(volume, imageSize: size, content: content, chrome: chrome)
        let raised = ChromeGeometry.buttonRect(
            volume, imageSize: size, content: content, chrome: chrome, hovered: true
        )
        XCTAssertLessThan(raised.minX, resting.minX, "a left button moves towards the window edge")
        XCTAssertEqual(raised.minY, resting.minY, "and does not move along the body")
    }

    func testHoveringMovesARightButtonOutwardsToo() throws {
        let chrome = try makeChrome()
        let content = ChromeGeometry.contentSize(screen: screen, chrome: chrome)
        let power = try XCTUnwrap(chrome.buttons.first { $0.name == "power" })
        let size = CGSize(width: 16, height: 101)
        let resting = ChromeGeometry.buttonRect(power, imageSize: size, content: content, chrome: chrome)
        let raised = ChromeGeometry.buttonRect(
            power, imageSize: size, content: content, chrome: chrome, hovered: true
        )
        XCTAssertGreaterThan(raised.minX, resting.minX)
    }

    func testAClickOnTheScreenFindsNoButton() throws {
        let chrome = try makeChrome()
        let content = ChromeGeometry.contentSize(screen: screen, chrome: chrome)
        let sizes = ["Vol BTN": CGSize(width: 16, height: 64), "X_Power BTN": CGSize(width: 16, height: 101)]
        let middle = ChromeGeometry.screenRect(content: content, chrome: chrome)
        let hit = ChromeGeometry.button(
            at: CGPoint(x: middle.midX, y: middle.midY), sizes: sizes, content: content, chrome: chrome
        )
        XCTAssertNil(hit)
    }
}
