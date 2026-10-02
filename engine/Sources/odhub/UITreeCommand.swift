import ArgumentParser
import CoreGraphics
import Foundation
import OpenDeviceHubEngine

struct UITree: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ui-tree",
        abstract: "Print the accessibility tree of the app in front on a booted simulator.",
        discussion: """
            Each line ends with the element's centre in the normalized coordinates `tap` takes, so a \
            line such as `Button "Save" @ 0.50,0.91` is tapped with `--x 0.50 --y 0.91`. Elements \
            scrolled off screen have no centre.
            """
    )

    @Argument(help: "The UDID of the simulator.")
    var udid: String

    @Flag(help: "Print the whole tree as JSON, frames in points.")
    var json = false

    @Flag(help: "Only print elements that carry a label, title, identifier or value.")
    var labelled = false

    func run() async throws {
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        let root = try adapter.accessibilityTree(udid)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(root), as: UTF8.self))
            return
        }
        let report = try await adapter.displayReport(udid)
        // Accessibility's display 0 denotes the main screen; CoreDevice uses its own display IDs.
        guard report.isSettled, let display = report.activeIntegrated,
              let orientation = DeviceOrientation.allCases.first(where: { $0.degrees == display.currentRotation }) else {
            throw EngineError.capabilityUnavailable(name: "the accessibility display's rotation")
        }
        printTree(root, screen: root.frame, orientation: orientation, depth: 0)
    }

    private func printTree(_ element: AccessibilityElement, screen: CGRect, orientation: DeviceOrientation, depth: Int) {
        let isLabelled = element.label != nil || element.title != nil
            || element.identifier != nil || element.value != nil
        if !labelled || isLabelled {
            let indent = String(repeating: "  ", count: labelled ? 0 : depth)
            print(indent + describe(element, screen: screen, orientation: orientation))
        }
        for child in element.children {
            printTree(child, screen: screen, orientation: orientation, depth: depth + 1)
        }
    }

    private func describe(_ element: AccessibilityElement, screen: CGRect, orientation: DeviceOrientation) -> String {
        var parts = [role(of: element)]
        if let label = element.label { parts.append("\"\(label)\"") }
        if let title = element.title, title != element.label { parts.append("title=\"\(title)\"") }
        if let value = element.value { parts.append("value=\"\(value)\"") }
        if let identifier = element.identifier { parts.append("id=\(identifier)") }
        if let center = element.normalizedCenter(in: screen, orientation: orientation) {
            parts.append(String(format: "@ %.2f,%.2f", center.x, center.y))
        }
        return parts.joined(separator: " ")
    }

    private func role(of element: AccessibilityElement) -> String {
        guard let role = element.role, !role.isEmpty else {
            return element.roleDescription ?? "Element"
        }
        return role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
    }
}
