import XCTest
@testable import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// Most of the help is prose and cannot be checked mechanically. These cover the parts that go
/// stale silently: a renamed mode leaves the help describing something no longer called that, and
/// nothing else would notice.
@MainActor
final class ControlsHelpTests: XCTestCase {
    private var everything: String {
        ControlsHelp.sections
            .flatMap { $0.entries.map { "\($0.keys) \($0.what)" } }
            .joined(separator: "\n")
    }

    func testEveryScaleModeIsNamedAsItAppearsInTheMenu() {
        for mode in ScaleMode.allCases {
            XCTAssertTrue(everything.contains(mode.displayName), "the help does not mention \(mode.displayName)")
        }
    }

    func testTheTitleCarriesTheProductName() {
        XCTAssertTrue(ControlsHelp.title.contains(Brand.productName))
    }

    func testItSaysWhereSimulatorsComeFrom() {
        XCTAssertTrue(ControlsHelp.footnote.contains("Open Simulator"))
    }

    func testNoSectionIsEmpty() {
        XCTAssertFalse(ControlsHelp.sections.isEmpty)
        for section in ControlsHelp.sections {
            XCTAssertFalse(section.entries.isEmpty, "\(section.title) has no rows")
            XCTAssertFalse(section.title.isEmpty)
        }
    }

    func testNoRowIsHalfWritten() {
        for section in ControlsHelp.sections {
            for entry in section.entries {
                XCTAssertFalse(entry.keys.isEmpty, "a row in \(section.title) has no keys")
                XCTAssertFalse(entry.what.isEmpty, "\(entry.keys) in \(section.title) has no description")
            }
        }
    }
}
