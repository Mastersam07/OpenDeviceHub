import Foundation

/// What one run of the performance check measured, and the machine it measured it on. Numbers
/// only compare with a baseline taken on the same machine, OS, Xcode and build configuration.
struct PerformanceReport: Codable, Equatable {
    static let schemaVersion = 1

    var schemaVersion = Self.schemaVersion
    let createdAt: String
    let environment: PerformanceEnvironment
    let windows: [WindowMeasurement]
}

struct PerformanceEnvironment: Codable, Equatable {
    let hardwareModel: String
    let macOS: String
    let xcode: String
    let lowPowerMode: Bool
    let buildConfiguration: String
}

/// The median and the nearest rank 95th percentile: the sample at or above that share of the
/// sorted run.
struct Spread: Codable, Equatable {
    let median: Double
    let p95: Double
    let samples: Int

    init(median: Double, p95: Double, samples: Int) {
        self.median = median
        self.p95 = p95
        self.samples = samples
    }

    init(_ values: [Double]) {
        precondition(!values.isEmpty, "a spread needs at least one sample")
        median = Self.percentile(values, 0.5)
        p95 = Self.percentile(values, 0.95)
        samples = values.count
    }

    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        return sorted[max(0, Int((Double(sorted.count) * fraction).rounded(.up)) - 1)]
    }
}

struct WindowMeasurement: Codable, Equatable {
    let name: String
    let device: String
    let idleCPUPercent: Spread
    let idleDrawsPerSecond: Double
    let idleFramesPerSecond: Double
    let windowMemoryMB: Double
    let processMemoryMB: Double
    let clickLatencyMs: Spread
    let foldStepGapMs: Spread?
    let foldCPUPercent: Double?
}

enum PerformanceComparison {
    /// A limit of the baseline plus the larger of a share of it and a fixed amount, so a metric
    /// near zero, idle CPU above all, is not failed for noise.
    struct Tolerance: Equatable {
        let relative: Double
        let absolute: Double

        func limit(for baseline: Double) -> Double {
            baseline + max(baseline * relative, absolute)
        }
    }

    struct Finding: Codable, Equatable {
        let window: String
        let metric: String
        let baseline: Double
        let current: Double
        let limit: Double
    }

    enum Incompatible: Error, Equatable, CustomStringConvertible {
        case schema(baseline: Int, current: Int)
        case environment(baseline: PerformanceEnvironment, current: PerformanceEnvironment)
        case missingWindow(String)

        var description: String {
            switch self {
            case .schema(let baseline, let current):
                "the baseline is schema \(baseline) and this run is schema \(current)"
            case .environment(let baseline, let current):
                "the baseline was measured on \(baseline) and this run on \(current)"
            case .missingWindow(let name):
                "the baseline measured a \(name) window and this run did not"
            }
        }
    }

    /// Every metric is one where less is better.
    static let tolerances: [String: Tolerance] = [
        "idle CPU median (%)": Tolerance(relative: 0.5, absolute: 3),
        "idle draws per second": Tolerance(relative: 0.5, absolute: 5),
        "window memory (MB)": Tolerance(relative: 0.2, absolute: 30),
        "click latency median (ms)": Tolerance(relative: 0.3, absolute: 8),
        "click latency p95 (ms)": Tolerance(relative: 0.3, absolute: 12),
        "fold step gap p95 (ms)": Tolerance(relative: 0.3, absolute: 10),
        "fold CPU (%)": Tolerance(relative: 0.5, absolute: 5),
    ]

    static func metrics(of window: WindowMeasurement) -> [String: Double] {
        var values = [
            "idle CPU median (%)": window.idleCPUPercent.median,
            "idle draws per second": window.idleDrawsPerSecond,
            "window memory (MB)": window.windowMemoryMB,
            "click latency median (ms)": window.clickLatencyMs.median,
            "click latency p95 (ms)": window.clickLatencyMs.p95,
        ]
        if let gaps = window.foldStepGapMs { values["fold step gap p95 (ms)"] = gaps.p95 }
        if let cpu = window.foldCPUPercent { values["fold CPU (%)"] = cpu }
        return values
    }

    static func regressions(
        current: PerformanceReport,
        baseline: PerformanceReport
    ) throws(Incompatible) -> [Finding] {
        guard baseline.schemaVersion == current.schemaVersion else {
            throw .schema(baseline: baseline.schemaVersion, current: current.schemaVersion)
        }
        guard baseline.environment == current.environment else {
            throw .environment(baseline: baseline.environment, current: current.environment)
        }
        var findings: [Finding] = []
        for base in baseline.windows {
            guard let now = current.windows.first(where: { $0.name == base.name }) else {
                throw .missingWindow(base.name)
            }
            let before = metrics(of: base)
            let after = metrics(of: now)
            for (metric, value) in before.sorted(by: { $0.key < $1.key }) {
                guard let measured = after[metric], let tolerance = tolerances[metric] else { continue }
                let limit = tolerance.limit(for: value)
                if measured > limit {
                    findings.append(Finding(window: base.name, metric: metric, baseline: value, current: measured, limit: limit))
                }
            }
        }
        return findings
    }

    /// The report as a person reads it, one window after another.
    static func text(_ report: PerformanceReport, findings: [Finding]? = nil) -> String {
        func number(_ value: Double) -> String { String(format: "%.1f", value) }
        var lines = [
            "Performance check \(report.createdAt)",
            "\(report.environment.hardwareModel), macOS \(report.environment.macOS), \(report.environment.xcode), \(report.environment.buildConfiguration)\(report.environment.lowPowerMode ? ", Low Power Mode" : "")",
            "",
        ]
        for window in report.windows {
            lines.append("\(window.name): \(window.device)")
            lines.append("  idle CPU          median \(number(window.idleCPUPercent.median))%, p95 \(number(window.idleCPUPercent.p95))% over \(window.idleCPUPercent.samples) samples")
            lines.append("  idle drawing      \(number(window.idleDrawsPerSecond)) pictures a second for \(number(window.idleFramesPerSecond)) frames a second from the device")
            lines.append("  memory            \(number(window.windowMemoryMB)) MB for the window, \(number(window.processMemoryMB)) MB for the process")
            lines.append("  click to frame    median \(number(window.clickLatencyMs.median)) ms, p95 \(number(window.clickLatencyMs.p95)) ms over \(window.clickLatencyMs.samples) clicks")
            if let gaps = window.foldStepGapMs {
                lines.append("  fold steps        median gap \(number(gaps.median)) ms, p95 \(number(gaps.p95)) ms over \(gaps.samples) steps")
            }
            if let cpu = window.foldCPUPercent {
                lines.append("  fold CPU          \(number(cpu))%")
            }
            lines.append("")
        }
        if let findings {
            if findings.isEmpty {
                lines.append("No regressions against the baseline.")
            } else {
                lines.append("Regressions against the baseline:")
                for finding in findings {
                    lines.append("  \(finding.window) \(finding.metric): \(number(finding.current)), baseline \(number(finding.baseline)), limit \(number(finding.limit))")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
