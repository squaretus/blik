import SwiftUI
import Charts
import BlikShared
import BlikCore
import BlikDesign

// MARK: - Module header

/// Header модуля: заголовок · текущее значение · (мин/сред/макс) · меню «…».
/// Меню открывает `ChartWidgetEditorSheet` (Настроить/Сбросить) — если задан config.
struct ModuleHeader: View {
    let title: String
    var currentText: String? = nil
    var currentColor: Color = DesignTokens.accent.resolve(.dark)
    /// Пары (метка, значение) для строки статистики, напр. [("мин","14%"),…].
    var stats: [(String, String)] = []
    var config: ChartWidgetConfig? = nil

    @Environment(AppCoordinator.self) private var coordinator
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(DesignTokens.fontPrimaryMedium)
                if let currentText {
                    Text(verbatim: currentText)
                        .font(DesignTokens.fontPrimaryMedium)
                        .foregroundStyle(currentColor)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                if let config {
                    menu(config)
                }
            }
            if !stats.isEmpty {
                HStack(spacing: 14) {
                    ForEach(stats, id: \.0) { stat in
                        HStack(spacing: 4) {
                            Text(stat.0)
                                .font(DesignTokens.fontSecondary)
                                .foregroundStyle(.tertiary)
                            Text(verbatim: stat.1)
                                .font(DesignTokens.fontSecondary)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func menu(_ config: ChartWidgetConfig) -> some View {
        Menu {
            Button {
                editing = true
            } label: {
                Label("Настроить", systemImage: "slider.horizontal.3")
            }
            Button {
                coordinator.chartWidgets.reset(id: config.id)
            } label: {
                Label("Сбросить", systemImage: "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(DesignTokens.fontPrimaryMedium)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .menuIndicator(.hidden)
        .sheet(isPresented: $editing) {
            ChartWidgetEditorSheet(
                config: config,
                onSave: { coordinator.chartWidgets.update($0) },
                onReset: { coordinator.chartWidgets.reset(id: config.id) },
            )
        }
    }
}

// MARK: - Summary stat tile

/// Компактная плитка summary-strip: метка · крупное текущее значение (цвет по
/// порогу) · микро-спарклайн. Живёт и в live, и в range (значение = среднее).
struct StatTile: View {
    let title: String
    let metric: String
    let unit: MetricUnit
    var warn: Double? = nil
    var crit: Double? = nil

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let _ = observeSummary(coordinator)
        BlikPanel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(DesignTokens.fontSecondary)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: valueText)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(valueColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let suffix = unitSuffix {
                        Text(verbatim: suffix)
                            .font(DesignTokens.fontSecondary)
                            .foregroundStyle(.secondary)
                    }
                }
                sparkline
                    .frame(height: 24)
                    .opacity(hasData ? 1 : 0.25)
            }
        }
    }

    private var sparkline: some View {
        Chart {
            ForEach(segments) { seg in
                ForEach(seg.points) { p in
                    LineMark(
                        x: .value("t", p.ts),
                        y: .value("v", p.value),
                        series: .value("s", seg.id),
                    )
                    .foregroundStyle(valueColor.opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: sparkDomain)
    }

    private var segments: [ChartSeriesSegment] {
        ChartData.segments(coordinator.charts, metric: metric)
    }

    private var hasData: Bool { segments.contains { !$0.points.isEmpty } }

    private var current: Double? { ChartData.current(coordinator.charts, metric: metric) }

    private var valueText: String {
        guard let current else { return "—" }
        switch unit {
        case .percent:                     return "\(Int(current.rounded()))"
        case .celsius:                     return "\(Int(current.rounded()))"
        case .bytes, .bytesPerSec:         return ChartFormatting.bytes(current)
        case .rpm:                         return "\(Int(current.rounded()))"
        }
    }

    private var unitSuffix: String? {
        switch unit {
        case .percent: return "%"
        case .celsius: return "°"
        case .rpm:     return "RPM"
        case .bytes, .bytesPerSec: return nil
        }
    }

    private var valueColor: Color {
        guard let current, unit == .percent || unit == .celsius else {
            return DesignTokens.accent.resolve(scheme)
        }
        if warn != nil || crit != nil {
            return ChartSeriesColor.threshold(value: current, warn: warn, crit: crit)
        }
        return DesignTokens.accent.resolve(scheme)
    }

    private var sparkDomain: ClosedRange<Double> {
        if unit == .percent { return 0...100 }
        let vals = segments.flatMap { $0.points }.map(\.value)
        guard let hi = vals.max(), let lo = vals.min(), hi > lo else { return 0...1 }
        let pad = (hi - lo) * 0.2
        return (lo - pad)...(hi + pad)
    }
}

// MARK: - Legend

/// Компактная легенда-чипы под графиком: toggle видимости серий (`enabledMetrics`).
struct SeriesLegend: View {
    let config: ChartWidgetConfig
    let color: (String) -> Color
    let name: (String) -> String
    /// Опциональное текущее значение серии — рендерится после имени (компактный
    /// per-series readout прямо в легенде).
    var value: ((String) -> String?)? = nil

    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(config.metrics, id: \.self) { metric in
                let on = config.enabledMetrics.contains(metric)
                Button {
                    toggle(metric)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(metric))
                            .frame(width: 7, height: 7)
                            .opacity(on ? 1 : 0.3)
                        Text(name(metric))
                            .font(DesignTokens.fontSecondary)
                            .foregroundStyle(on ? .secondary : .tertiary)
                        if on, let value, let v = value(metric) {
                            Text(verbatim: v)
                                .font(DesignTokens.fontSecondary)
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(on ? color(metric).opacity(0.12) : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ metric: String) {
        var cfg = config
        if cfg.enabledMetrics.contains(metric) {
            cfg.enabledMetrics.remove(metric)
        } else {
            cfg.enabledMetrics.insert(metric)
        }
        coordinator.chartWidgets.update(cfg)
    }
}

// MARK: - Live redraw trigger

/// Подписка тяжёлого графика на throttled chart-тик (перерисовка ~2 с, не каждый
/// 1s-poll) — вместо широкой подписки на сырые `resources`/`sensors`, которая
/// инвалидировала всю страницу каждую секунду. Вызывать в `body` как
/// `let _ = observeChart(coordinator)`.
@MainActor
func observeChart(_ coordinator: AppCoordinator) {
    _ = coordinator.charts.chartTick
}

/// Подписка summary-плитки на тик каждого poll (текущее значение — чаще, чем
/// тяжёлые графики; плитка дешёвая).
@MainActor
func observeSummary(_ coordinator: AppCoordinator) {
    _ = coordinator.charts.summaryTick
}

// MARK: - Metric naming fallback

/// Fallback-имена метрик для легенд, когда каталог не под рукой (агрегаты без
/// сенсора). Кастомные имена приходят из `MetricNameStore` — это лишь дефолт.
enum MetricNaming {
    static func fallback(_ key: String) -> String {
        switch key {
        case MetricKey.cpuUsageOverall: return "CPU нагрузка"
        case MetricKey.gpuUsage:        return "GPU нагрузка"
        case MetricKey.gpuMemoryUsed:   return "Память GPU"
        case MetricKey.memoryUsed:      return "Память"
        case MetricKey.memoryPressure:  return "Давление памяти"
        case MetricKey.tempPCoreAvg:    return "CPU P-ядра"
        case MetricKey.tempECoreAvg:    return "CPU E-ядра"
        case MetricKey.tempGPUAvg:      return "GPU"
        case MetricKey.diskReadTotal:   return "Диск: чтение"
        case MetricKey.diskWriteTotal:  return "Диск: запись"
        default:
            if key.hasPrefix(MetricKey.tempPrefix) {
                return String(key.dropFirst(MetricKey.tempPrefix.count))
            }
            return key
        }
    }
}

// MARK: - Flow layout

/// Перенос по строкам для легенды-чипов (SwiftUI не имеет wrapping-HStack).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x - bounds.minX + size.width > maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
