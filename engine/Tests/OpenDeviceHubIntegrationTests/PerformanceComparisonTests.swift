import XCTest

final class PerformanceComparisonTests: XCTestCase {
    private let environment = PerformanceEnvironment(
        hardwareModel: "Mac16,7", macOS: "27.0", xcode: "Xcode 27.0 (27A266a)",
        lowPowerMode: false, buildConfiguration: "release"
    )

    private func window(
        _ name: String = "foldable",
        cpu: Double = 10,
        draws: Double = 60,
        memory: Double = 350,
        latency: Double = 20,
        gap: Double? = 34,
        energy: Double? = nil,
        gpu: Double? = nil,
        open: Double? = nil,
        kept: Double? = nil,
        device: String = "iPhone Duo (iOS 27.1)"
    ) -> WindowMeasurement {
        WindowMeasurement(
            name: name,
            device: device,
            idleCPUPercent: Spread(median: cpu, p95: cpu * 2, samples: 10),
            idleDrawsPerSecond: draws,
            idleFramesPerSecond: 0.1,
            windowMemoryMB: memory,
            processMemoryMB: memory + 60,
            clickLatencyMs: Spread(median: latency, p95: latency * 1.5, samples: 15),
            foldStepGapMs: gap.map { Spread(median: $0 / 2, p95: $0, samples: 60) },
            foldCPUPercent: gap == nil ? nil : 15,
            idleCPUEnergyMilliwatts: energy,
            idleGPUPercent: gpu,
            open: open.map(openTime),
            reopen: kept.map {
                Reopen(
                    opens: [openTime(420), openTime(380), openTime(400)],
                    keptAfterCloseMB: 250,
                    addedByEachReopenMB: [$0 * 3, $0, 0],
                    freedOnClose: true
                )
            }
        )
    }

    private func openTime(_ total: Double) -> OpenTime {
        OpenTime(sessionsMs: total / 4, orientationMs: total / 2, windowMs: total / 8, firstPictureMs: total / 8)
    }

    private func together(
        cpu: Double = 12,
        growth: Double = 1,
        seconds: Double = 180,
        devices: [String] = ["iPhone 17 (iOS 27.1)", "iPhone Duo (iOS 27.1)"]
    ) -> TogetherMeasurement {
        TogetherMeasurement(
            devices: devices,
            idleCPUPercent: Spread(median: cpu, p95: cpu * 2, samples: 10),
            idleCPUEnergyMilliwatts: 150,
            idleGPUPercent: 3,
            idleDrawsPerSecond: 30,
            idleFramesPerSecond: 0.2,
            windowsMemoryMB: 400,
            processMemoryMB: 520,
            soak: MemorySoak(seconds: seconds, clicks: 300, folds: 8, startMB: 520, endMB: 530, growthMBPerMinute: growth)
        )
    }

    private func report(
        _ windows: [WindowMeasurement],
        together: TogetherMeasurement? = nil,
        environment: PerformanceEnvironment? = nil
    ) -> PerformanceReport {
        PerformanceReport(createdAt: "now", environment: environment ?? self.environment, windows: windows, together: together)
    }

    func testTheLimitIsTheLargerOfAShareAndAFixedAmount() {
        let tolerance = PerformanceComparison.Tolerance(relative: 0.5, absolute: 3)
        XCTAssertEqual(tolerance.limit(for: 1), 4, "near zero the fixed amount decides")
        XCTAssertEqual(tolerance.limit(for: 20), 30, "further up the share decides")
    }

    func testAReopenIsJudgedByItsMedians() {
        let reopen = Reopen(
            opens: [openTime(420), openTime(380), openTime(400)],
            keptAfterCloseMB: 250,
            addedByEachReopenMB: [24, 0.5, -1],
            freedOnClose: true
        )
        XCTAssertEqual(reopen.medianOpen, openTime(400))
        XCTAssertEqual(reopen.medianAddedMB, 0.5, "only the first reopen growing is a cache, not a leak")
    }

    func testABaselineBelowZeroIsHeldToZeroPlusTheFixedAmount() {
        let tolerance = PerformanceComparison.Tolerance(relative: 0.5, absolute: 5)
        XCTAssertEqual(tolerance.limit(for: -6.8), 5, "memory that shrank is not a limit below zero")
    }

    func testMemoryKeptByEachReopenBeyondItsLimitIsReported() throws {
        let findings = try PerformanceComparison.regressions(
            current: report([window(kept: 40)]),
            baseline: report([window(kept: 2)])
        )
        XCTAssertEqual(findings.map(\.metric), ["memory kept by each reopen (MB)"])
        XCTAssertEqual(findings.first?.limit, 12)
    }

    func testTheSpreadTakesTheSampleAtEachPercentile() {
        let spread = Spread([5, 1, 4, 2, 3, 9, 8, 7, 6, 10])
        XCTAssertEqual(spread.median, 5)
        XCTAssertEqual(spread.p95, 10)
        XCTAssertEqual(spread.samples, 10)
    }

    func testARunWithinToleranceHasNoRegressions() throws {
        let findings = try PerformanceComparison.regressions(
            current: report([window(cpu: 12, memory: 380, latency: 24)]),
            baseline: report([window()])
        )
        XCTAssertEqual(findings, [])
    }

    func testAnImprovementIsNotARegression() throws {
        let findings = try PerformanceComparison.regressions(
            current: report([window(cpu: 0.5, draws: 0.2, memory: 120)]),
            baseline: report([window()])
        )
        XCTAssertEqual(findings, [])
    }

    func testEachMetricBeyondItsLimitIsReported() throws {
        let findings = try PerformanceComparison.regressions(
            current: report([window(cpu: 16, draws: 60, memory: 450, latency: 40, gap: 60)]),
            baseline: report([window()])
        )
        XCTAssertEqual(Set(findings.map(\.metric)), [
            "idle CPU median (%)", "window memory (MB)", "click latency median (ms)",
            "click latency p95 (ms)", "fold step gap p95 (ms)",
        ])
        let cpu = try XCTUnwrap(findings.first { $0.metric == "idle CPU median (%)" })
        XCTAssertEqual(cpu.baseline, 10)
        XCTAssertEqual(cpu.current, 16)
        XCTAssertEqual(cpu.limit, 15)
    }

    func testAWindowWithoutFoldMetricsIsComparedOnTheRest() throws {
        let findings = try PerformanceComparison.regressions(
            current: report([window("phone", cpu: 0, draws: 0, memory: 60, gap: nil)]),
            baseline: report([window("phone", cpu: 0, draws: 0, memory: 60, gap: nil)])
        )
        XCTAssertEqual(findings, [])
    }

    func testABaselineFromAnotherMachineIsRefused() {
        var other = environment
        other = PerformanceEnvironment(
            hardwareModel: other.hardwareModel, macOS: other.macOS, xcode: "Xcode 26.5 (17F42)",
            lowPowerMode: other.lowPowerMode, buildConfiguration: other.buildConfiguration
        )
        XCTAssertThrowsError(try PerformanceComparison.regressions(
            current: report([window()]),
            baseline: report([window()], environment: other)
        )) { error in
            guard case PerformanceComparison.Incompatible.environment = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    func testAWindowTheBaselineMeasuredMustBeMeasuredAgain() {
        XCTAssertThrowsError(try PerformanceComparison.regressions(
            current: report([window("phone", gap: nil)]),
            baseline: report([window("phone", gap: nil), window("foldable")])
        )) { error in
            XCTAssertEqual(error as? PerformanceComparison.Incompatible, .missingWindow("foldable"))
        }
    }

    func testTheReportRoundTripsThroughJSON() throws {
        let original = report(
            [window(energy: 120, gpu: 4, open: 900, kept: 3), window("phone", gap: nil)],
            together: together()
        )
        let decoded = try JSONDecoder().decode(PerformanceReport.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testEnergyGPUAndOpenTimeBeyondTheirLimitsAreReported() throws {
        let findings = try PerformanceComparison.regressions(
            current: report([window(energy: 200, gpu: 7, open: 1700)]),
            baseline: report([window(energy: 100, gpu: 4, open: 800)])
        )
        XCTAssertEqual(Set(findings.map(\.metric)), [
            "idle CPU energy (mW)", "idle GPU (%)", "open to first picture (ms)",
        ])
        let open = try XCTUnwrap(findings.first { $0.metric == "open to first picture (ms)" })
        XCTAssertEqual(open.limit, 1600, "the first open fails only once it doubles")
    }

    func testABaselineFromBeforeTheNewerMetricsStillChecksTheRest() throws {
        let json = String(decoding: try JSONEncoder().encode(report([window()])), as: UTF8.self)
        XCTAssertFalse(json.contains("idleGPUPercent"))
        XCTAssertFalse(json.contains("together"))
        let baseline = try JSONDecoder().decode(PerformanceReport.self, from: Data(json.utf8))
        let findings = try PerformanceComparison.regressions(
            current: report([window(cpu: 16, energy: 900, gpu: 50, open: 9000)], together: together()),
            baseline: baseline
        )
        XCTAssertEqual(findings.map(\.metric), ["idle CPU median (%)"])
    }

    func testTheWindowsOpenedTogetherAreComparedUnderTheirOwnName() throws {
        let findings = try PerformanceComparison.regressions(
            current: report([window()], together: together(cpu: 20, growth: 9)),
            baseline: report([window()], together: together())
        )
        XCTAssertEqual(findings.map(\.window), ["together", "together"])
        XCTAssertEqual(Set(findings.map(\.metric)), ["idle CPU median (%)", "memory growth (MB per minute)"])
    }

    func testTheWindowsOpenedTogetherMustBeMeasuredAgain() {
        XCTAssertThrowsError(try PerformanceComparison.regressions(
            current: report([window()]),
            baseline: report([window()], together: together())
        )) { error in
            XCTAssertEqual(error as? PerformanceComparison.Incompatible, .missingWindow("together"))
        }
    }

    func testOtherBootedDevicesAreRefused() {
        XCTAssertThrowsError(try PerformanceComparison.regressions(
            current: report([window()], together: together(devices: ["iPhone 17 (iOS 27.1)"])),
            baseline: report([window()], together: together())
        )) { error in
            XCTAssertEqual(error as? PerformanceComparison.Incompatible, .differentDevices(
                window: "together",
                baseline: "iPhone 17 (iOS 27.1), iPhone Duo (iOS 27.1)",
                current: "iPhone 17 (iOS 27.1)"
            ))
        }
    }

    func testAWindowOnAnotherDeviceIsRefused() {
        XCTAssertThrowsError(try PerformanceComparison.regressions(
            current: report([window(device: "iPhone Duo (iOS 27.0)")]),
            baseline: report([window()])
        )) { error in
            XCTAssertEqual(error as? PerformanceComparison.Incompatible, .differentDevices(
                window: "foldable", baseline: "iPhone Duo (iOS 27.1)", current: "iPhone Duo (iOS 27.0)"
            ))
        }
    }

    func testAnotherBusyTimeIsRefused() {
        XCTAssertThrowsError(try PerformanceComparison.regressions(
            current: report([window()], together: together(seconds: 60)),
            baseline: report([window()], together: together())
        )) { error in
            XCTAssertEqual(error as? PerformanceComparison.Incompatible, .differentSoak(baseline: 180, current: 60))
        }
    }

    func testTheGrowthIsTheSlopeInMegabytesAMinute() {
        XCTAssertEqual(MemorySoak.slope([(0, 100), (30, 101), (60, 102)]), 2, accuracy: 1e-9)
        XCTAssertEqual(MemorySoak.slope([(0, 100), (5, 104), (10, 100), (15, 104)]), 9.6, accuracy: 1e-9)
        XCTAssertEqual(MemorySoak.slope([(10, 100), (20, 100)]), 0)
        XCTAssertEqual(MemorySoak.slope([(10, 100)]), 0, "one sample has no slope")
    }

    func testTheOpenTimeIsTheSumOfItsParts() {
        let open = OpenTime(sessionsMs: 40, orientationMs: 700, windowMs: 60, firstPictureMs: 25)
        XCTAssertEqual(open.totalMs, 825)
    }

    func testTheReportSetsTheWindowsTogetherBesideTheirSumAlone() {
        let phone = window("phone", cpu: 0.5, gap: nil, device: "iPhone 17 (iOS 27.1)")
        let text = PerformanceComparison.text(report([phone, window(cpu: 6)], together: together(cpu: 7)))
        XCTAssertTrue(text.contains("All 2 windows together: iPhone 17 (iOS 27.1), iPhone Duo (iOS 27.1)"), text)
        XCTAssertTrue(text.contains("median 7.0%, p95 14.0%, the windows alone add up to 6.5%"), text)
    }
}
