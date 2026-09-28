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
        gap: Double? = 34
    ) -> WindowMeasurement {
        WindowMeasurement(
            name: name,
            device: "iPhone Duo (iOS 27.1)",
            idleCPUPercent: Spread(median: cpu, p95: cpu * 2, samples: 10),
            idleDrawsPerSecond: draws,
            idleFramesPerSecond: 0.1,
            windowMemoryMB: memory,
            processMemoryMB: memory + 60,
            clickLatencyMs: Spread(median: latency, p95: latency * 1.5, samples: 15),
            foldStepGapMs: gap.map { Spread(median: $0 / 2, p95: $0, samples: 60) },
            foldCPUPercent: gap == nil ? nil : 15
        )
    }

    private func report(_ windows: [WindowMeasurement], environment: PerformanceEnvironment? = nil) -> PerformanceReport {
        PerformanceReport(createdAt: "now", environment: environment ?? self.environment, windows: windows)
    }

    func testTheLimitIsTheLargerOfAShareAndAFixedAmount() {
        let tolerance = PerformanceComparison.Tolerance(relative: 0.5, absolute: 3)
        XCTAssertEqual(tolerance.limit(for: 1), 4, "near zero the fixed amount decides")
        XCTAssertEqual(tolerance.limit(for: 20), 30, "further up the share decides")
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
        let original = report([window(), window("phone", gap: nil)])
        let decoded = try JSONDecoder().decode(PerformanceReport.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}
