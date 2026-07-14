import BlikCore
import Foundation

enum StatuslineLevel {
    case ok, warn, crit

    var color: ANSIColor {
        switch self {
        case .ok: return .green
        case .warn: return .yellow
        case .crit: return .brightRed
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

    static func render(_ metrics: [StatuslineMetric]) -> String {
        metrics.map { m in
            var parts = [
                ANSIRenderer.color(m.label, .gray),
                ANSIRenderer.color(m.valueText, m.level.color, .bold),
            ]
            if !m.spark.isEmpty {
                parts.append(ANSIRenderer.color(sparkline(m.spark), m.level.color))
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
