import AppKit
import OpenDeviceHubEngine

/// The simulators of one runtime, as the chooser lists them.
public struct RuntimeGroup: Equatable, Sendable {
    public let runtimeName: String
    public let devices: [DeviceInfo]

    public init(runtimeName: String, devices: [DeviceInfo]) {
        self.runtimeName = runtimeName
        self.devices = devices
    }
}

/// Newest runtime first, and inside each runtime the devices in the order a person reads them.
public func runtimeGroups(from devices: [DeviceInfo]) -> [RuntimeGroup] {
    let byRuntime = Dictionary(grouping: devices.filter(\.isAvailable), by: \.runtimeName)
    return byRuntime.keys
        .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        .map { runtime in
            RuntimeGroup(
                runtimeName: runtime,
                devices: (byRuntime[runtime] ?? []).sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            )
        }
}

/// Runtimes, and under each the simulators it can run, with a click starting one. It hangs off the
/// Dock icon and off the menu bar, and rebuilds itself every time it opens so a simulator created
/// or deleted while the app runs is not missing from it.
@MainActor
public final class DeviceChooser: NSObject, NSMenuDelegate {
    private let devices: () -> [DeviceInfo]
    private let open: (String) -> Void

    /// The runtime list on its own, for a menu bar item to hold.
    public let menu = NSMenu(title: "Open Simulator")

    public init(devices: @escaping () -> [DeviceInfo], open: @escaping (String) -> Void) {
        self.devices = devices
        self.open = open
        super.init()
        menu.delegate = self
    }

    /// The Dock menu, which nests the same list under one item, as the simulator this replaces does.
    public func dockMenu() -> NSMenu {
        let dock = NSMenu()
        let item = NSMenuItem(title: "Device", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        fill(submenu)
        item.submenu = submenu
        dock.addItem(item)
        return dock
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        fill(menu)
    }

    private func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        let groups = runtimeGroups(from: devices())
        guard !groups.isEmpty else {
            let empty = NSMenuItem(title: "No Available Simulators", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for group in groups {
            let runtimeItem = NSMenuItem(title: group.runtimeName, action: nil, keyEquivalent: "")
            let runtimeMenu = NSMenu(title: group.runtimeName)
            for device in group.devices {
                let item = NSMenuItem(title: device.name, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device.udid
                item.state = device.state == .booted ? .on : .off
                runtimeMenu.addItem(item)
            }
            runtimeItem.submenu = runtimeMenu
            menu.addItem(runtimeItem)
        }
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let udid = sender.representedObject as? String else { return }
        open(udid)
    }
}
