import Foundation

/// What one run of the performance check measured, and the machine it measured it on. Numbers
/// only compare with a baseline taken on the same machine, OS, Xcode and build configuration.
struct PerformanceReport: Codable, Equatable {
    static let schemaVersion = 1

    var schemaVersion = Self.schemaVersion
    let createdAt: String
    let environment: PerformanceEnvironment
    let windows: [WindowMeasurement]
    /// Absent from reports taken before every window was also measured open at once.
    var together: TogetherMeasurement? = nil
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
    /// These are absent from reports taken before they were measured.
    var idleCPUEnergyMilliwatts: Double? = nil
    var idleGPUPercent: Double? = nil
    var open: OpenTime? = nil
    var reopen: Reopen? = nil
}

/// The window opened and closed a few more times after the first closed. What the first left behind
/// can be a cache the next reuses; what grows again with every reopen is kept by every window.
struct Reopen: Codable, Equatable {
    let opens: [OpenTime]
    let keptAfterCloseMB: Double
    /// For each reopen, memory once it closed less memory once the window before it closed.
    let addedByEachReopenMB: [Double]
    /// Whether every reopened window's controller was freed once it closed.
    let freedOnClose: Bool

    var medianOpen: OpenTime {
        let median = Spread(opens.map(\.totalMs)).median
        return opens.first { $0.totalMs == median } ?? opens[0]
    }

    var medianAddedMB: Double { Spread(addedByEachReopenMB).median }
}

/// From starting to open a window, as the app does, to the device's first picture drawn in it.
struct OpenTime: Codable, Equatable {
    /// The panels, the display sessions and the input session.
    let sessionsMs: Double
    let orientationMs: Double
    let windowMs: Double
    let firstPictureMs: Double
    let totalMs: Double

    init(sessionsMs: Double, orientationMs: Double, windowMs: Double, firstPictureMs: Double) {
        self.sessionsMs = sessionsMs
        self.orientationMs = orientationMs
        self.windowMs = windowMs
        self.firstPictureMs = firstPictureMs
        totalMs = sessionsMs + orientationMs + windowMs + firstPictureMs
    }
}

/// Every booted device's window open at once, then kept busy for a while to see whether memory
/// keeps growing.
struct TogetherMeasurement: Codable, Equatable {
    let devices: [String]
    let idleCPUPercent: Spread
    let idleCPUEnergyMilliwatts: Double
    let idleGPUPercent: Double
    let idleDrawsPerSecond: Double
    let idleFramesPerSecond: Double
    /// Over the process before any window opened, since what the windows measured alone kept after
    /// closing is reused by these and would otherwise be left out.
    let windowsMemoryMB: Double
    let processMemoryMB: Double
    let soak: MemorySoak
}

struct MemorySoak: Codable, Equatable {
    let seconds: Double
    let clicks: Int
    let folds: Int
    let startMB: Double
    let endMB: Double
    /// The least squares slope of the samples taken after the first quarter, at most 30 seconds,
    /// which is when caches are still filling.
    let growthMBPerMinute: Double

    static func slope(_ samples: [(seconds: Double, megabytes: Double)]) -> Double {
        guard samples.count > 1 else { return 0 }
        let count = Double(samples.count)
        let meanTime = samples.map(\.seconds).reduce(0, +) / count
        let meanSize = samples.map(\.megabytes).reduce(0, +) / count
        let covariance = samples.map { ($0.seconds - meanTime) * ($0.megabytes - meanSize) }.reduce(0, +)
        let variance = samples.map { ($0.seconds - meanTime) * ($0.seconds - meanTime) }.reduce(0, +)
        return variance > 0 ? covariance / variance * 60 : 0
    }
}

enum PerformanceComparison {
    /// A limit of the baseline plus the larger of a share of it and a fixed amount, so a metric
    /// near zero, idle CPU above all, is not failed for noise. A baseline below zero, memory that
    /// shrank, is held to zero plus the fixed amount for the same reason.
    struct Tolerance: Equatable {
        let relative: Double
        let absolute: Double

        func limit(for baseline: Double) -> Double {
            let base = max(baseline, 0)
            return base + max(base * relative, absolute)
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
        case differentDevices(window: String, baseline: String, current: String)
        case differentSoak(baseline: Double, current: Double)

        var description: String {
            switch self {
            case .schema(let baseline, let current):
                "the baseline is schema \(baseline) and this run is schema \(current)"
            case .environment(let baseline, let current):
                "the baseline was measured on \(baseline) and this run on \(current)"
            case .missingWindow(let name):
                "the baseline measured a \(name) window and this run did not"
            case .differentDevices(let window, let baseline, let current):
                "the baseline measured the \(window) window on \(baseline) and this run on \(current)"
            case .differentSoak(let baseline, let current):
                "the baseline kept the windows busy for \(Int(baseline)) seconds and this run for \(Int(current))"
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
        "idle CPU energy (mW)": Tolerance(relative: 0.5, absolute: 10),
        "idle GPU (%)": Tolerance(relative: 0.5, absolute: 2),
        // The first open in a process pays for loading what the rest reuse and moved by more than
        // half between runs, so only a doubling fails it.
        "open to first picture (ms)": Tolerance(relative: 1, absolute: 300),
        "open again to first picture (ms)": Tolerance(relative: 0.3, absolute: 150),
        "memory kept by each reopen (MB)": Tolerance(relative: 0.5, absolute: 10),
        // Three busy minutes with nothing leaking read from -9 to 13 MB a minute over nine runs, as
        // the model's memory dips and comes back by tens of MB.
        "memory growth (MB per minute)": Tolerance(relative: 0.5, absolute: 15),
    ]

    /// Where one kind of window is noisier than the rest, keyed by window and then metric.
    static let windowTolerances: [String: [String: Tolerance]] = [
        "foldable": [
            // The model's memory moves by up to 50 MB from one reopen to the next with nothing
            // leaking (27A9269), while a whole window is about 300 MB.
            "memory kept by each reopen (MB)": Tolerance(relative: 0.5, absolute: 60),
        ],
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
        if let energy = window.idleCPUEnergyMilliwatts { values["idle CPU energy (mW)"] = energy }
        if let gpu = window.idleGPUPercent { values["idle GPU (%)"] = gpu }
        if let open = window.open { values["open to first picture (ms)"] = open.totalMs }
        if let reopen = window.reopen {
            values["open again to first picture (ms)"] = reopen.medianOpen.totalMs
            values["memory kept by each reopen (MB)"] = reopen.medianAddedMB
        }
        return values
    }

    static func metrics(of together: TogetherMeasurement) -> [String: Double] {
        [
            "idle CPU median (%)": together.idleCPUPercent.median,
            "idle draws per second": together.idleDrawsPerSecond,
            "window memory (MB)": together.windowsMemoryMB,
            "idle CPU energy (mW)": together.idleCPUEnergyMilliwatts,
            "idle GPU (%)": together.idleGPUPercent,
            "memory growth (MB per minute)": together.soak.growthMBPerMinute,
        ]
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
            guard now.device == base.device else {
                throw .differentDevices(window: base.name, baseline: base.device, current: now.device)
            }
            findings += compare(base.name, metrics(of: base), metrics(of: now))
        }
        if let base = baseline.together {
            guard let now = current.together else { throw .missingWindow(togetherName) }
            guard now.devices == base.devices else {
                throw .differentDevices(
                    window: togetherName,
                    baseline: base.devices.joined(separator: ", "),
                    current: now.devices.joined(separator: ", ")
                )
            }
            guard now.soak.seconds == base.soak.seconds else {
                throw .differentSoak(baseline: base.soak.seconds, current: now.soak.seconds)
            }
            findings += compare(togetherName, metrics(of: base), metrics(of: now))
        }
        return findings
    }

    static let togetherName = "together"

    /// A metric only the baseline or only this run has is skipped, so a baseline taken before a
    /// metric existed still checks the rest.
    private static func compare(_ window: String, _ before: [String: Double], _ after: [String: Double]) -> [Finding] {
        before.sorted(by: { $0.key < $1.key }).compactMap { metric, value in
            guard let measured = after[metric],
                  let tolerance = windowTolerances[window]?[metric] ?? tolerances[metric] else { return nil }
            let limit = tolerance.limit(for: value)
            guard measured > limit else { return nil }
            return Finding(window: window, metric: metric, baseline: value, current: measured, limit: limit)
        }
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
            if let energy = window.idleCPUEnergyMilliwatts, let gpu = window.idleGPUPercent {
                lines.append("  idle energy       \(number(energy)) mW of CPU, GPU busy \(number(gpu))% of the time")
            }
            func parts(_ open: OpenTime) -> String {
                "\(number(open.totalMs)) ms to the first picture: \(number(open.sessionsMs)) ms sessions, \(number(open.orientationMs)) ms orientation, \(number(open.windowMs)) ms window, \(number(open.firstPictureMs)) ms first picture"
            }
            if let open = window.open {
                lines.append("  open              \(parts(open))")
            }
            if let reopen = window.reopen {
                lines.append("  open again        median of \(reopen.opens.count), \(parts(reopen.medianOpen))")
                lines.append("  after closing     \(number(reopen.keptAfterCloseMB)) MB kept by the first window, then \(reopen.addedByEachReopenMB.map(number).joined(separator: ", ")) MB by each reopen; \(reopen.freedOnClose ? "every reopened window was freed" : "a reopened window outlived its window")")
            }
            lines.append("")
        }
        if let together = report.together {
            let alone = together.devices.compactMap { device in report.windows.first { $0.device == device } }
            let sum = alone.count == together.devices.count
                ? ", the windows alone add up to \(number(alone.map(\.idleCPUPercent.median).reduce(0, +)))%"
                : ""
            lines.append("All \(together.devices.count) windows together: \(together.devices.joined(separator: ", "))")
            lines.append("  idle CPU          median \(number(together.idleCPUPercent.median))%, p95 \(number(together.idleCPUPercent.p95))%\(sum)")
            lines.append("  idle drawing      \(number(together.idleDrawsPerSecond)) pictures a second for \(number(together.idleFramesPerSecond)) frames a second from the devices")
            lines.append("  idle energy       \(number(together.idleCPUEnergyMilliwatts)) mW of CPU, GPU busy \(number(together.idleGPUPercent))% of the time")
            lines.append("  memory            \(number(together.windowsMemoryMB)) MB over the process before any window opened, \(number(together.processMemoryMB)) MB for the process")
            let soak = together.soak
            lines.append("  kept busy         \(Int(soak.seconds)) s, \(soak.clicks) clicks, \(soak.folds) folds: \(number(soak.startMB)) MB to \(number(soak.endMB)) MB, growing \(number(soak.growthMBPerMinute)) MB a minute")
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
