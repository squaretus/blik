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
}

/// Чистый рендер таблицы метрик для статус-бара Claude Code.
/// Не делает I/O — источник данных собирает вызывающая сторона.
enum StatuslineRenderer {

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

    private static let labelGray = truecolor(142, 142, 147)   // systemGray — рамка и заголовки
    private static let bold = "\u{1B}[1m"
    private static let reset = ANSIColor.reset.rawValue

    /// Ширина колонки — по самому длинному из заголовка и значения плюс
    /// по пробелу с каждой стороны, чтобы текст не липнул к рамке.
    private static func columnWidths(_ metrics: [StatuslineMetric]) -> [Int] {
        metrics.map { max($0.label.count, $0.valueText.count) + 2 }
    }

    /// Центрирование: лишний пробел при нечётной разнице уходит вправо.
    private static func centered(_ text: String, width: Int) -> String {
        let free = max(0, width - text.count)
        let left = free / 2
        return String(repeating: " ", count: left)
            + text
            + String(repeating: " ", count: free - left)
    }

    private static func rule(_ left: String, _ joint: String, _ right: String,
                             _ widths: [Int]) -> String {
        let segments = widths.map { String(repeating: "─", count: $0) }
        return labelGray + left + segments.joined(separator: joint) + right + reset
    }

    private static func row(_ cells: [String]) -> String {
        let bar = labelGray + "│" + reset
        return bar + cells.joined(separator: bar) + bar
    }

    static func render(_ metrics: [StatuslineMetric]) -> String {
        guard !metrics.isEmpty else { return "" }
        let widths = columnWidths(metrics)

        let headers = row(zip(metrics, widths).map { metric, width in
            labelGray + centered(metric.label, width: width) + reset
        })
        let values = row(zip(metrics, widths).map { metric, width in
            metric.level.foreground + bold + centered(metric.valueText, width: width) + reset
        })

        return [
            rule("┌", "┬", "┐", widths),
            headers,
            rule("├", "┼", "┤", widths),
            values,
            rule("└", "┴", "┘", widths),
        ].joined(separator: "\n")
    }

    /// Сборка метрик из живых данных. Отсутствующие источники пропускаются
    /// (деградация без ошибок) — колонка просто не рисуется.
    static func buildMetrics(sensors: [SensorInfo],
                             snapshot: ResourceSnapshot?) -> [StatuslineMetric] {
        var out: [StatuslineMetric] = []

        let tempBlocks: [(SensorGroup, String)] = [
            (.cpuCores, "CPU"),
            (.npuECores, "E-CORES"),
            (.gpuCores, "GPU"),
        ]
        for (group, label) in tempBlocks {
            let inGroup = sensors.filter { $0.group == group }
            guard !inGroup.isEmpty else { continue }
            let avg = inGroup.map(\.temperature).reduce(0, +) / Double(inGroup.count)
            out.append(StatuslineMetric(
                label: label,
                valueText: "\(Int(avg.rounded()))°",
                level: tempLevel(avg)))
        }

        if let memory = snapshot?.memory {
            out.append(StatuslineMetric(
                label: "RAM",
                valueText: gigabytes(memory.used),
                level: fillLevel(used: Double(memory.used), total: Double(memory.total))))
        }

        if let gpu = snapshot?.gpu {
            out.append(StatuslineMetric(
                label: "VRAM",
                valueText: gigabytes(gpu.memoryUsed),
                level: fillLevel(used: Double(gpu.memoryUsed), total: Double(gpu.memoryTotal))))
        }

        return out
    }
}
