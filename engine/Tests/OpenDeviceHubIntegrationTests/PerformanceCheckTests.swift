import AppKit
import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// Measures what a device window costs: CPU and drawing while nothing on screen changes, memory,
/// click to frame latency and, on a foldable, how evenly a fold is drawn. It runs only through
/// `scripts/performance-check.sh`, which says where the report goes and what to compare it with.
@MainActor
final class PerformanceCheckTests: XCTestCase {
    private var adapter: (any SimulatorAdapter)!
    private var manager: DeviceWindowManager!
    private var stepTimes: [ContinuousClock.Instant] = []

    static let settleSeconds = 8
    static let idleRounds = 10
    static let idleRoundSeconds = 2
    static let clicks = 20

    func testMeasureEachKindOfWindow() async throws {
        try IntegrationGate.requireEnabled()
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["ODH_PERFORMANCE_REPORT"] else {
            throw XCTSkip("run scripts/performance-check.sh, which says where the report goes")
        }
        adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        manager = DeviceWindowManager(frameStore: WindowFrameStore(storage: DiscardingStorage()), shutdown: { _ in })

        let booted = try adapter.devices().filter { $0.state == .booted }
        var windows: [WindowMeasurement] = []
        if let phone = booted.first(where: {
            $0.name.hasPrefix("iPhone") && ((try? adapter.panels($0.udid).count) ?? 0) < 2
        }) {
            windows.append(try await measurePhone(phone))
        }
        if let foldable = booted.first(where: { $0.deviceTypeIdentifier.contains("Duo") }) {
            windows.append(try await measureFoldable(foldable))
        }
        guard !windows.isEmpty else { throw XCTSkip("boot an iPhone and an iPhone Duo to measure them") }

        let report = PerformanceReport(
            createdAt: ISO8601DateFormatter().string(from: Date()),
            environment: try Self.environment(),
            windows: windows
        )
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.json(report).write(to: directory.appending(path: "performance.json"))

        var findings: [PerformanceComparison.Finding]?
        if let baselinePath = environment["ODH_PERFORMANCE_BASELINE"] {
            let baseline = try JSONDecoder().decode(
                PerformanceReport.self,
                from: Data(contentsOf: URL(fileURLWithPath: baselinePath))
            )
            do {
                let found = try PerformanceComparison.regressions(current: report, baseline: baseline)
                findings = found
                try Self.json(found).write(to: directory.appending(path: "comparison.json"))
                for finding in found {
                    XCTFail("\(finding.window) \(finding.metric) is \(finding.current), over its limit of \(finding.limit) from a baseline of \(finding.baseline)")
                }
            } catch {
                XCTFail("the baseline cannot be compared with this run: \(error)")
            }
        }
        if let recordPath = environment["ODH_PERFORMANCE_RECORD"] {
            try Self.json(report).write(to: URL(fileURLWithPath: recordPath))
        }
        let text = PerformanceComparison.text(report, findings: findings)
        try Data(text.utf8).write(to: directory.appending(path: "performance.txt"))
        print(text)
    }

    private func measurePhone(_ device: DeviceInfo) async throws -> WindowMeasurement {
        try IntegrationHost.install(on: device.udid)
        _ = try run(["simctl", "launch", device.udid, IntegrationHost.bundleID])
        let before = Self.footprintMB()
        let controller = try manager.open(
            device: device,
            session: try adapter.openDisplay(device.udid, panel: nil),
            input: try adapter.openInput(device.udid),
            scaleMode: .fit,
            bezelEnabled: true,
            keepOnTop: false,
            showFPS: false
        )
        defer { manager.close(device.udid) }
        let window = try XCTUnwrap(controller.window)
        window.orderFront(nil)
        let screen = try XCTUnwrap(Self.find(DeviceScreenView.self, in: window))
        try await Task.sleep(for: .seconds(Self.settleSeconds))
        let windowMemory = Self.footprintMB() - before

        let idle = try await measureIdle(controller)
        let box = screen.bounds
        let spots = Self.spots(around: CGPoint(x: box.midX, y: box.midY), size: box.size)
        let latency = try await measureClicks(controller, on: screen, spots: spots)
        return WindowMeasurement(
            name: "phone",
            device: "\(device.name) (\(device.runtimeName))",
            idleCPUPercent: idle.cpu,
            idleDrawsPerSecond: idle.draws,
            idleFramesPerSecond: idle.frames,
            windowMemoryMB: windowMemory,
            processMemoryMB: Self.footprintMB(),
            clickLatencyMs: latency,
            foldStepGapMs: nil,
            foldCPUPercent: nil
        )
    }

    private func measureFoldable(_ device: DeviceInfo) async throws -> WindowMeasurement {
        try IntegrationHost.install(on: device.udid)
        let panels = try adapter.panels(device.udid)
        let unfolded = try XCTUnwrap(panels.first { $0.name == "Unfolded" })
        let cover = try XCTUnwrap(panels.first { $0.name == "Cover" })
        let input = try adapter.openInput(device.udid, screenID: unfolded.screenID)
        let targeted = try XCTUnwrap(input as? PanelInputSession, "touches must be panel targeted")
        let before = Self.footprintMB()
        let controller = try manager.open(
            device: device,
            session: try adapter.openDisplay(device.udid, panel: unfolded),
            input: input,
            scaleMode: .fit,
            bezelEnabled: true,
            keepOnTop: false,
            showFPS: false,
            foldsAtHinge: true,
            chrome: unfolded.chromeIdentifier.flatMap { ChromeLocator.chrome(identifier: $0) },
            panelNativeRotation: unfolded.nativeRotation,
            unfoldedPanel: unfolded,
            cover: FoldableCover(panel: cover, session: try adapter.openDisplay(device.udid, panel: cover)),
            retarget: { targeted.setTarget(screenID: $0) }
        )
        let window = try XCTUnwrap(controller.window)
        window.orderFront(nil)
        let model = try XCTUnwrap(Self.find(DuoModelView.self, in: window))

        let adapter = self.adapter!
        let shared = try await IntegrationFoldable.shared.control(for: device.udid, adapter: adapter)
        let foldables = FoldableController(
            open: { _ in shared },
            hingeStream: { try adapter.openHingeStream($0) },
            displayReport: { try await adapter.displayReport($0) }
        )
        let udid = device.udid
        defer {
            foldables.setAngle(DeviceControlBar.FoldMode.fullyOpen.angle, for: udid)
            foldables.forget(udid)
            manager.close(udid)
        }
        controller.onHingeAngle = { angle in foldables.setAngle(angle, for: udid) }
        controller.onFoldPreset = { angle in foldables.setAngle(angle, for: udid, eased: true) }
        foldables.onMove = { [weak controller, weak self] _, event in
            switch event {
            case .began(let target): controller?.beginFold(to: target)
            case .angle(let angle):
                self?.stepTimes.append(ContinuousClock.now)
                controller?.showHingeAngle(angle)
            case .ended: controller?.endFold()
            }
        }
        foldables.follow(
            udid,
            onPanel: { [weak controller] panel in controller?.setActivePanel(screenID: panel.displayID) },
            onHinge: { [weak controller] degrees in controller?.showHingeAngle(degrees) }
        )
        let open = DeviceControlBar.FoldMode.fullyOpen.angle
        controller.showHingeAngle(open)
        foldables.setAngle(open, for: udid)
        _ = try run(["simctl", "launch", udid, IntegrationHost.bundleID])
        try await Task.sleep(for: .seconds(Self.settleSeconds))
        let windowMemory = Self.footprintMB() - before

        let idle = try await measureIdle(controller)
        let box = model.bounds
        let spots = Self.spots(around: CGPoint(x: box.midX, y: box.midY), size: box.size)
            .filter { model.screenPoint(at: $0) != nil }
        XCTAssertFalse(spots.isEmpty, "no click lands on the open screen")
        let latency = try await measureClicks(controller, on: model, spots: spots)

        let control = try XCTUnwrap(Self.find(NSSegmentedControl.self, in: window), "the window's fold positions")
        stepTimes.removeAll()
        var gaps: [Double] = []
        let cpuStart = Self.cpuSeconds()
        let wallStart = ContinuousClock.now
        for mode in [DeviceControlBar.FoldMode.cover, .fullyOpen] {
            stepTimes.removeAll()
            control.selectedSegment = mode.rawValue
            control.sendAction(control.action, to: control.target)
            try await Task.sleep(for: .seconds(3))
            gaps += zip(stepTimes.dropFirst(), stepTimes).map { later, earlier in Self.milliseconds(later - earlier) }
        }
        let foldCPU = (Self.cpuSeconds() - cpuStart) / Self.seconds(ContinuousClock.now - wallStart) * 100
        XCTAssertGreaterThan(gaps.count, 10, "the window drew no run of fold steps")

        return WindowMeasurement(
            name: "foldable",
            device: "\(device.name) (\(device.runtimeName))",
            idleCPUPercent: idle.cpu,
            idleDrawsPerSecond: idle.draws,
            idleFramesPerSecond: idle.frames,
            windowMemoryMB: windowMemory,
            processMemoryMB: Self.footprintMB(),
            clickLatencyMs: latency,
            foldStepGapMs: gaps.isEmpty ? nil : Spread(gaps),
            foldCPUPercent: foldCPU
        )
    }

    private struct Idle {
        let cpu: Spread
        let draws: Double
        let frames: Double
    }

    /// The whole process's CPU, which with one window open is that window's: the test runner itself
    /// sits idle while it waits.
    private func measureIdle(_ controller: DeviceWindowController) async throws -> Idle {
        var cpu: [Double] = []
        let draws = controller.drawCount
        let frames = controller.framesReceived
        let started = ContinuousClock.now
        for _ in 0..<Self.idleRounds {
            let cpuStart = Self.cpuSeconds()
            let wallStart = ContinuousClock.now
            try await Task.sleep(for: .seconds(Self.idleRoundSeconds))
            cpu.append((Self.cpuSeconds() - cpuStart) / Self.seconds(ContinuousClock.now - wallStart) * 100)
        }
        let elapsed = Self.seconds(ContinuousClock.now - started)
        return Idle(
            cpu: Spread(cpu),
            draws: Double(controller.drawCount - draws) / elapsed,
            frames: Double(controller.framesReceived - frames) / elapsed
        )
    }

    /// Each click lands on the test host, which writes where it was touched and so always redraws.
    /// The first contact pays for turning the input feature on, so it is not one of the readings.
    private func measureClicks(
        _ controller: DeviceWindowController,
        on view: NSView,
        spots: [CGPoint]
    ) async throws -> Spread {
        let window = try XCTUnwrap(view.window)
        var samples: [Double] = []
        for index in -1..<Self.clicks {
            let counted = controller.latencyReading?.sampleCount ?? 0
            let inWindow = view.convert(spots[(index + spots.count) % spots.count], to: nil)
            view.mouseDown(with: try Self.mouse(.leftMouseDown, at: inWindow, in: window))
            try await Task.sleep(for: .milliseconds(60))
            view.mouseUp(with: try Self.mouse(.leftMouseUp, at: inWindow, in: window))
            for _ in 0..<40 where (controller.latencyReading?.sampleCount ?? 0) <= counted {
                try await Task.sleep(for: .milliseconds(25))
            }
            if index >= 0, let reading = controller.latencyReading, reading.sampleCount > counted {
                samples.append(reading.lastMilliseconds)
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        XCTAssertGreaterThanOrEqual(samples.count, Self.clicks * 2 / 3, "most clicks drew no frame")
        guard !samples.isEmpty else { throw XCTSkip("no click drew a frame, so latency could not be measured") }
        return Spread(samples)
    }

    private static func spots(around centre: CGPoint, size: CGSize) -> [CGPoint] {
        let step = CGSize(width: size.width * 0.15, height: size.height * 0.15)
        return [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)].map { dx, dy in
            CGPoint(x: centre.x + CGFloat(dx) * step.width, y: centre.y + CGFloat(dy) * step.height)
        }
    }

    static func environment() throws -> PerformanceEnvironment {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        let model = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let xcode = try XcodeLocator.locate()
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        return PerformanceEnvironment(
            hardwareModel: model,
            macOS: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            xcode: "Xcode \(xcode.version) (\(xcode.build))",
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            buildConfiguration: configuration
        )
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        seconds(duration) * 1000
    }

    private static func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private static func find<T: NSView>(_ type: T.Type, in window: NSWindow) -> T? {
        func search(_ view: NSView) -> T? {
            if let found = view as? T { return found }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return window.contentView.flatMap(search)
    }

    private static func mouse(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    @discardableResult
    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

private final class DiscardingStorage: PreferenceStorage, @unchecked Sendable {
    func text(forKey key: String) -> String? { nil }
    func setText(_ text: String, forKey key: String) {}
    func removeText(forKey key: String) {}
    func keys(withPrefix prefix: String) -> [String] { [] }
}
