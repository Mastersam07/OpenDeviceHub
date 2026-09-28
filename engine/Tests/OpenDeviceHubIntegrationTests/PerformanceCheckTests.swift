import AppKit
import IOKit
import XCTest
import OpenDeviceHubEngine
@testable import OpenDeviceHubViewer

/// Measures what a device window costs: how long it takes to open, CPU, energy, GPU and drawing
/// while nothing on screen changes, memory, click to frame latency and, on a foldable, how evenly a
/// fold is drawn. Then every booted device's window is opened at once and kept busy to see whether
/// memory keeps growing. It runs only through `scripts/performance-check.sh`, which says where the
/// report goes and what to compare it with.
@MainActor
final class PerformanceCheckTests: XCTestCase {
    private var adapter: (any SimulatorAdapter)!
    private var manager: DeviceWindowManager!
    private var stepTimes: [ContinuousClock.Instant] = []

    static let settleSeconds = 8
    static let idleRounds = 10
    static let idleRoundSeconds = 2
    static let clicks = 20
    static let hostSettleSeconds = 2
    static let closeSettleSeconds = 3
    static let reopens = 3
    static let soakSampleSeconds = 5.0
    static let soakFoldEverySeconds = 20.0
    static let soakClickSeconds = 0.5

    func testMeasureEachKindOfWindow() async throws {
        try IntegrationGate.requireEnabled()
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["ODH_PERFORMANCE_REPORT"] else {
            throw XCTSkip("run scripts/performance-check.sh, which says where the report goes")
        }
        adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        manager = DeviceWindowManager(frameStore: WindowFrameStore(storage: DiscardingStorage()), shutdown: { _ in })

        let soakSeconds = Double(environment["ODH_PERFORMANCE_BUSY_SECONDS"] ?? "") ?? 180
        let processStart = try Self.footprintMB()
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
        let together = booted.count > 1 ? try await measureTogether(booted, soakSeconds: soakSeconds, processStart: processStart) : nil

        let report = PerformanceReport(
            createdAt: ISO8601DateFormatter().string(from: Date()),
            environment: try Self.environment(),
            windows: windows,
            together: together
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
        try await Task.sleep(for: .seconds(Self.hostSettleSeconds))
        let before = try Self.footprintMB()
        var measurement = try await measurePhoneWindow(device, before: before)
        measurement.reopen = try await measureReopen(device, before: before)
        return measurement
    }

    /// Apart from the reopen, so nothing here still holds the window once it closes.
    private func measurePhoneWindow(_ device: DeviceInfo, before: Double) async throws -> WindowMeasurement {
        let opened = try await openWindow(device)
        let controller = opened.controller
        defer { manager.close(device.udid) }
        let window = try XCTUnwrap(controller.window)
        let screen = try XCTUnwrap(Self.find(DeviceScreenView.self, in: window))
        try await Task.sleep(for: .seconds(Self.settleSeconds))
        let windowMemory = try Self.footprintMB() - before

        let idle = try await measureIdle([controller])
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
            processMemoryMB: try Self.footprintMB(),
            clickLatencyMs: latency,
            foldStepGapMs: nil,
            foldCPUPercent: nil,
            idleCPUEnergyMilliwatts: idle.energy,
            idleGPUPercent: idle.gpu,
            open: opened.time
        )
    }

    private func measureFoldable(_ device: DeviceInfo) async throws -> WindowMeasurement {
        try IntegrationHost.install(on: device.udid)
        _ = try run(["simctl", "launch", device.udid, IntegrationHost.bundleID])
        try await Task.sleep(for: .seconds(Self.hostSettleSeconds))
        let before = try Self.footprintMB()
        var measurement = try await measureFoldableWindow(device, before: before)
        measurement.reopen = try await measureReopen(device, before: before)
        return measurement
    }

    private func measureFoldableWindow(_ device: DeviceInfo, before: Double) async throws -> WindowMeasurement {
        let opened = try await openWindow(device)
        let controller = opened.controller
        let udid = device.udid
        XCTAssertNotNil(opened.input as? PanelInputSession, "touches must be panel targeted")
        let foldables = try await followFolds(of: controller, udid: udid)
        defer {
            foldables.setAngle(DeviceControlBar.FoldMode.fullyOpen.angle, for: udid)
            foldables.forget(udid)
            manager.close(udid)
        }
        let window = try XCTUnwrap(controller.window)
        let model = try XCTUnwrap(Self.find(DuoModelView.self, in: window))
        try await Task.sleep(for: .seconds(Self.settleSeconds))
        let windowMemory = try Self.footprintMB() - before

        let idle = try await measureIdle([controller])
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
            processMemoryMB: try Self.footprintMB(),
            clickLatencyMs: latency,
            foldStepGapMs: gaps.isEmpty ? nil : Spread(gaps),
            foldCPUPercent: foldCPU,
            idleCPUEnergyMilliwatts: idle.energy,
            idleGPUPercent: idle.gpu,
            open: opened.time
        )
    }

    /// Called once the first window has closed. The reopened windows are not wired for folding: the
    /// point is what opening and closing costs.
    private func measureReopen(_ device: DeviceInfo, before: Double) async throws -> Reopen {
        try await Task.sleep(for: .seconds(Self.closeSettleSeconds))
        let afterFirst = try Self.footprintMB()
        var opens: [OpenTime] = []
        var added: [Double] = []
        var freed = true
        var previous = afterFirst
        for _ in 0..<Self.reopens {
            weak var reopened: DeviceWindowController?
            do {
                let opened = try await openWindow(device)
                reopened = opened.controller
                opens.append(opened.time)
                try await Task.sleep(for: .seconds(2))
                manager.close(device.udid)
            }
            try await Task.sleep(for: .seconds(Self.closeSettleSeconds))
            let now = try Self.footprintMB()
            added.append(now - previous)
            previous = now
            freed = freed && reopened == nil
        }
        return Reopen(opens: opens, keptAfterCloseMB: afterFirst - before, addedByEachReopenMB: added, freedOnClose: freed)
    }

    private func measureTogether(
        _ devices: [DeviceInfo],
        soakSeconds: Double,
        processStart: Double
    ) async throws -> TogetherMeasurement {
        var controllers: [DeviceWindowController] = []
        var foldables: [(controller: FoldableController, udid: String)] = []
        defer {
            for foldable in foldables {
                foldable.controller.setAngle(DeviceControlBar.FoldMode.fullyOpen.angle, for: foldable.udid)
                foldable.controller.forget(foldable.udid)
            }
            for device in devices { manager.close(device.udid) }
        }
        for device in devices {
            let opened = try await openWindow(device)
            controllers.append(opened.controller)
            if opened.controller.foldsAtHinge {
                foldables.append((try await followFolds(of: opened.controller, udid: device.udid), device.udid))
            }
        }
        try await Task.sleep(for: .seconds(Self.settleSeconds))
        let windowsMemory = try Self.footprintMB() - processStart
        let idle = try await measureIdle(controllers)
        let soak = try await keepBusy(controllers, seconds: soakSeconds)
        return TogetherMeasurement(
            devices: devices.map { "\($0.name) (\($0.runtimeName))" },
            idleCPUPercent: idle.cpu,
            idleCPUEnergyMilliwatts: idle.energy,
            idleGPUPercent: idle.gpu,
            idleDrawsPerSecond: idle.draws,
            idleFramesPerSecond: idle.frames,
            windowsMemoryMB: windowsMemory,
            processMemoryMB: try Self.footprintMB(),
            soak: soak
        )
    }

    private struct OpenedWindow {
        let controller: DeviceWindowController
        let input: any InputSession
        let time: OpenTime
    }

    /// In the app's own order: panels, display and input sessions, the orientation from the guest,
    /// then the window. The first picture is the first draw after the first frame from the device.
    private func openWindow(_ device: DeviceInfo) async throws -> OpenedWindow {
        let started = ContinuousClock.now
        let panels = (try? adapter.panels(device.udid)) ?? []
        let foldsAtHinge = panels.count > 1
        let unfolded = foldsAtHinge ? panels.first { $0.name == "Unfolded" } : nil
        let coverPanel = foldsAtHinge ? panels.first { $0.name == "Cover" } : nil
        let session = try adapter.openDisplay(device.udid, panel: unfolded)
        session.setBezelEnabled(true)
        var cover: FoldableCover?
        if let coverPanel {
            let coverSession = try adapter.openDisplay(device.udid, panel: coverPanel)
            coverSession.setBezelEnabled(true)
            cover = FoldableCover(panel: coverPanel, session: coverSession)
        }
        let input = try adapter.openInput(device.udid, screenID: unfolded?.screenID ?? 0)
        let retarget: ((Int) -> Void)? = (input as? PanelInputSession).map { targeted in
            { targeted.setTarget(screenID: $0) }
        }
        let sessionsOpened = ContinuousClock.now
        let orientation = DevicectlService().orientation(udid: device.udid) ?? .portrait
        let oriented = ContinuousClock.now
        let controller = try manager.open(
            device: device,
            session: session,
            input: input,
            scaleMode: .fit,
            bezelEnabled: true,
            keepOnTop: false,
            showFPS: false,
            foldsAtHinge: foldsAtHinge,
            chrome: unfolded?.chromeIdentifier.flatMap { ChromeLocator.chrome(identifier: $0) },
            panelNativeRotation: unfolded?.nativeRotation ?? 0,
            unfoldedPanel: unfolded,
            cover: cover,
            retarget: retarget,
            orientation: orientation
        )
        if let unfolded, !controller.foldsAtHinge {
            controller.nativeRotation = unfolded.nativeRotation
        }
        _ = controller.applyScaleMode(.fit)
        controller.window?.orderFront(nil)
        let shown = ContinuousClock.now
        var drawsBeforeFrame = controller.drawCount
        while controller.framesReceived == 0 || controller.drawCount <= drawsBeforeFrame {
            if controller.framesReceived == 0 { drawsBeforeFrame = controller.drawCount }
            guard ContinuousClock.now - shown < .seconds(10) else {
                manager.close(device.udid)
                throw MeasurementUnavailable(what: "\(device.name)'s first picture after 10 seconds")
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        let drawn = ContinuousClock.now
        return OpenedWindow(
            controller: controller,
            input: input,
            time: OpenTime(
                sessionsMs: Self.milliseconds(sessionsOpened - started),
                orientationMs: Self.milliseconds(oriented - sessionsOpened),
                windowMs: Self.milliseconds(shown - oriented),
                firstPictureMs: Self.milliseconds(drawn - shown)
            )
        )
    }

    /// Wired as the app wires a foldable's window, and left fully open.
    private func followFolds(of controller: DeviceWindowController, udid: String) async throws -> FoldableController {
        let adapter = self.adapter!
        let shared = try await IntegrationFoldable.shared.control(for: udid, adapter: adapter)
        let foldables = FoldableController(
            open: { _ in shared },
            hingeStream: { try adapter.openHingeStream($0) },
            displayReport: { try await adapter.displayReport($0) }
        )
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
        return foldables
    }

    private struct Idle {
        let cpu: Spread
        let draws: Double
        let frames: Double
        let energy: Double
        let gpu: Double
    }

    /// The whole process's CPU, energy and GPU, which are the open windows': the test runner itself
    /// sits idle while it waits.
    private func measureIdle(_ controllers: [DeviceWindowController]) async throws -> Idle {
        func draws() -> Int { controllers.map(\.drawCount).reduce(0, +) }
        func frames() -> Int { controllers.map(\.framesReceived).reduce(0, +) }
        var cpu: [Double] = []
        let drawsStart = draws()
        let framesStart = frames()
        let energyStart = try Self.cpuEnergyJoules()
        let gpuStart = try Self.gpuSeconds()
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
            draws: Double(draws() - drawsStart) / elapsed,
            frames: Double(frames() - framesStart) / elapsed,
            energy: (try Self.cpuEnergyJoules() - energyStart) / elapsed * 1000,
            gpu: (try Self.gpuSeconds() - gpuStart) / elapsed * 100
        )
    }

    /// Clicks on each window in turn, every half second, with a fold to the cover and back on each
    /// foldable every 20 seconds, sampling the process's memory every 5 seconds.
    private func keepBusy(_ controllers: [DeviceWindowController], seconds: Double) async throws -> MemorySoak {
        var targets: [(controller: DeviceWindowController, view: NSView, spots: [CGPoint])] = []
        var folds: [NSSegmentedControl] = []
        for controller in controllers {
            let window = try XCTUnwrap(controller.window)
            if let model = Self.find(DuoModelView.self, in: window) {
                let box = model.bounds
                let spots = Self.spots(around: CGPoint(x: box.midX, y: box.midY), size: box.size)
                    .filter { model.screenPoint(at: $0) != nil }
                if !spots.isEmpty { targets.append((controller, model, spots)) }
                folds.append(try XCTUnwrap(Self.find(NSSegmentedControl.self, in: window), "the window's fold positions"))
            } else {
                let screen = try XCTUnwrap(Self.find(DeviceScreenView.self, in: window))
                let box = screen.bounds
                targets.append((controller, screen, Self.spots(around: CGPoint(x: box.midX, y: box.midY), size: box.size)))
            }
        }
        XCTAssertFalse(targets.isEmpty, "no window has a spot to click")

        let started = ContinuousClock.now
        func elapsed() -> Double { Self.seconds(ContinuousClock.now - started) }
        var samples = [(seconds: 0.0, megabytes: try Self.footprintMB())]
        var nextSample = Self.soakSampleSeconds
        var nextFold = Self.soakFoldEverySeconds
        var clicks = 0
        var foldCount = 0
        while elapsed() < seconds {
            if !folds.isEmpty, elapsed() >= nextFold {
                for mode in [DeviceControlBar.FoldMode.cover, .fullyOpen] {
                    for control in folds {
                        control.selectedSegment = mode.rawValue
                        control.sendAction(control.action, to: control.target)
                    }
                    try await Task.sleep(for: .seconds(3))
                }
                foldCount += folds.count
                nextFold += Self.soakFoldEverySeconds
            }
            if !targets.isEmpty {
                let target = targets[clicks % targets.count]
                let spot = target.spots[(clicks / targets.count) % target.spots.count]
                let window = try XCTUnwrap(target.view.window)
                let inWindow = target.view.convert(spot, to: nil)
                target.view.mouseDown(with: try Self.mouse(.leftMouseDown, at: inWindow, in: window))
                try await Task.sleep(for: .milliseconds(60))
                target.view.mouseUp(with: try Self.mouse(.leftMouseUp, at: inWindow, in: window))
                clicks += 1
            }
            try await Task.sleep(for: .seconds(Self.soakClickSeconds))
            while elapsed() >= nextSample {
                samples.append((elapsed(), try Self.footprintMB()))
                nextSample += Self.soakSampleSeconds
            }
        }
        let warmUp = min(30, seconds / 4)
        return MemorySoak(
            seconds: seconds,
            clicks: clicks,
            folds: foldCount,
            startMB: samples[0].megabytes,
            endMB: samples[samples.count - 1].megabytes,
            growthMBPerMinute: MemorySoak.slope(samples.filter { $0.seconds >= warmUp })
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

    private static func footprintMB() throws -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw MeasurementUnavailable(what: "the process's memory footprint") }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// The CPU's energy alone: a GPU bound Metal loop barely moves it (macOS 27.0, Mac15,6).
    private static func cpuEnergyJoules() throws -> Double {
        var info = task_power_info_v2()
        var count = mach_msg_type_number_t(MemoryLayout<task_power_info_v2>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO_V2), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw MeasurementUnavailable(what: "the process's energy") }
        return Double(info.task_energy) / 1e9
    }

    /// The GPU driver's own undocumented count of each process's GPU time, kept on its user clients
    /// in the I/O Registry. For frame sized work it read within a third of Metal's own timing, and
    /// no closer (macOS 27.0, Mac15,6).
    private static func gpuSeconds() throws -> Double {
        func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        let creator = "pid \(getpid()),"
        var accelerators: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &accelerators) == KERN_SUCCESS else {
            throw MeasurementUnavailable(what: "the GPU")
        }
        defer { IOObjectRelease(accelerators) }
        var nanoseconds: UInt64 = 0
        var found = false
        while case let accelerator = IOIteratorNext(accelerators), accelerator != 0 {
            defer { IOObjectRelease(accelerator) }
            var clients: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &clients) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(clients) }
            while case let client = IOIteratorNext(clients), client != 0 {
                defer { IOObjectRelease(client) }
                guard let owner = property(client, "IOUserClientCreator") as? String, owner.hasPrefix(creator),
                      let usage = property(client, "AppUsage") as? [[String: Any]] else { continue }
                found = true
                nanoseconds += usage.compactMap { ($0["accumulatedGPUTime"] as? NSNumber)?.uint64Value }.reduce(0, +)
            }
        }
        guard found else { throw MeasurementUnavailable(what: "this process's GPU time") }
        return Double(nanoseconds) / 1e9
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

private struct MeasurementUnavailable: Error, CustomStringConvertible {
    let what: String
    var description: String { "could not read \(what)" }
}

private final class DiscardingStorage: PreferenceStorage, @unchecked Sendable {
    func text(forKey key: String) -> String? { nil }
    func setText(_ text: String, forKey key: String) {}
    func removeText(forKey key: String) {}
    func keys(withPrefix prefix: String) -> [String] { [] }
}
