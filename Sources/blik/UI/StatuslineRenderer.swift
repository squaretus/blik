import BlikCore
import Foundation

enum StatuslineLevel {
    case ok, warn, crit

    /// Truecolor (24-bit): базовые ANSI-16 коды перекрашиваются палитрой
    /// темы терминала (у некоторых тем «green» — синий), RGB идёт как есть.
    /// Цвета — системная палитра macOS (dark), как в GUI приложения.
    var foreground: String {
        switch self {
        case .ok: return StatuslineRenderer.truecolor(48, 209, 88)     // systemGreen
        case .warn: return StatuslineRenderer.truecolor(255, 214, 10)  // systemYellow
        case .crit: return StatuslineRenderer.truecolor(255, 69, 58)   // systemRed
        }
    }
}

struct StatuslineMetric {
    let label: String
    let valueText: String
    let level: StatuslineLevel
    let spark: [Double]
}

/// Чистый рендер строки для статус-бара Claude Code: значения → ANSI-строка.
/// Не делает I/O — источник данных собирает вызывающая сторона.
enum StatuslineRenderer {
    private static let blocks: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    /// Окно истории для спарклайнов.
    static let historyWindow: TimeInterval = 30 * 60
    /// Точек на спарклайн (maxPointsPerSeries запроса истории).
    static let sparkPoints = 20

    static func sparkline(_ values: [Double]) -> String {
        guard let minV = values.min(), let maxV = values.max() else { return "" }
        guard maxV > minV else { return String(repeating: "▄", count: values.count) }
        let span = maxV - minV
        return String(values.map { value in
            let idx = Int(((value - minV) / span * 7).rounded())
            return blocks[max(0, min(7, idx))]
        })
    }

    static func tempLevel(_ celsius: Double) -> StatuslineLevel {
        switch celsius {
        case ..<70: return .ok
        case ..<90: return .warn
        default: return .crit
        }
    }

    static func fillLevel(used: Double, total: Double) -> StatuslineLevel {
        guard total > 0 else { return .ok }
        switch used / total {
        case ..<0.7: return .ok
        case ..<0.9: return .warn
        default: return .crit
        }
    }

    /// Байты → компактные гигабайты: "16,2G" (десятичная запятая, как в GUI).
    static func gigabytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return String(format: "%.1f", gb).replacingOccurrences(of: ".", with: ",") + "G"
    }

    static func truecolor(_ r: Int, _ g: Int, _ b: Int) -> String {
        "\u{1B}[38;2;\(r);\(g);\(b)m"
    }

    private static let labelGray = truecolor(142, 142, 147)   // systemGray
    private static let valueWhite = truecolor(255, 255, 255)
    private static let bold = "\u{1B}[1m"
    private static let reset = ANSIColor.reset.rawValue

    static func render(_ metrics: [StatuslineMetric]) -> String {
        metrics.map { m in
            var parts = [
                labelGray + m.label + reset,
                valueWhite + bold + m.valueText + reset,
            ]
            if !m.spark.isEmpty {
                parts.append(m.level.foreground + sparkline(m.spark) + reset)
            }
            return parts.joined(separator: " ")
        }.joined(separator: "  ")
    }

    /// Сборка метрик из живых данных + истории. Отсутствующие источники
    /// пропускаются (деградация без ошибок).
    static func buildMetrics(sensors: [SensorInfo], snapshot: ResourceSnapshot?,
                             history: HistoryQueryResponse?) -> [StatuslineMetric] {
        var spark: [String: [Double]] = [:]
        for series in history?.series ?? [] {
            spark[series.metric] = series.points.map(\.avg)
        }

        var out: [StatuslineMetric] = []

        let tempBlocks: [(SensorGroup, String, String)] = [
            (.cpuCores, "CPU", MetricKey.tempPCoreAvg),
            (.npuECores, "E", MetricKey.tempECoreAvg),
            (.gpuCores, "GPU", MetricKey.tempGPUAvg),
        ]
        for (group, label, metricKey) in tempBlocks {
            let inGroup = sensors.filter { $0.group == group }
            guard !inGroup.isEmpty else { continue }
            let avg = inGroup.map(\.temperature).reduce(0, +) / Double(inGroup.count)
            out.append(StatuslineMetric(
                label: label,
                valueText: "\(Int(avg.rounded()))°",
                level: tempLevel(avg),
                spark: spark[metricKey] ?? []))
        }

        if let memory = snapshot?.memory {
            out.append(StatuslineMetric(
                label: "RAM",
                valueText: gigabytes(memory.used),
                level: fillLevel(used: Double(memory.used), total: Double(memory.total)),
                spark: spark[MetricKey.memoryUsed] ?? []))
        }

        if let gpu = snapshot?.gpu {
            out.append(StatuslineMetric(
                label: "VRAM",
                valueText: gigabytes(gpu.memoryUsed),
                level: fillLevel(used: Double(gpu.memoryUsed), total: Double(gpu.memoryTotal)),
                spark: spark[MetricKey.gpuMemoryUsed] ?? []))
        }

        return out
    }
}
