import SwiftUI
import Charts
import BlikShared
import BlikCore
import BlikDesign

/// Переиспользуемый time-series график (line + лёгкая area) для модулей дашборда.
///
/// - Кадрированный Y (проценты 0…100, остальное — вокруг данных).
/// - Приглушённая сетка, читаемые оси, адаптивный формат времени.
/// - Разрывы данных видимы (серия разбита на сегменты, без интерполяции сквозь gap).
/// - Hover-crosshair: вертикальная линия + аннотация (время + значения серий) —
///   ключевой для macOS паттерн читаемости точки под курсором.
/// - Состояния загрузки/пустоты — внутри графика, не на весь экран.
struct MetricChart: View {
    let config: ChartWidgetConfig
    var height: CGFloat = 200

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var scheme
    @State private var hoverDate: Date?
    @State private var plotWidth: CGFloat = 600

    var body: some View {
        let _ = observeChart(coordinator)
        Group {
            if coordinator.charts.isLoading && !hasData {
                loading
            } else if !hasData {
                empty
            } else {
                chart
            }
        }
        .frame(height: height)
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(allSegments) { seg in
                ForEach(seg.points) { p in
                    LineMark(x: .value("Время", p.ts), y: .value("Значение", p.value),
                             series: .value("Сегмент", seg.id))
                        .foregroundStyle(color(seg.metric))
                        .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
            if let snap = hoverSnapshot {
                RuleMark(x: .value("Время", snap.ts))
                    .foregroundStyle(BlikPalette.muted.resolve(scheme).opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(snap)
                    }
                ForEach(snap.values, id: \.metric) { v in
                    PointMark(x: .value("Время", snap.ts), y: .value("Значение", v.value))
                        .foregroundStyle(color(v.metric))
                        .symbolSize(30)
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: window.from...window.to)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { mark in
                AxisGridLine().foregroundStyle(gridColor)
                AxisValueLabel {
                    if let v = mark.as(Double.self) {
                        Text(verbatim: ChartFormatting.axis(v, unit: unit))
                            .font(DesignTokens.fontSecondary)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: ChartTimeAxis.niceTicks(from: window.from, to: window.to, target: tickTarget)) { value in
                AxisGridLine().foregroundStyle(gridColor)
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(verbatim: ChartTimeAxis.axisLabel(d, rangeSeconds: rangeSeconds))
                            .font(DesignTokens.fontSecondary)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            guard let plot = proxy.plotFrame else { return }
                            let x = loc.x - geo[plot].origin.x
                            hoverDate = proxy.value(atX: x, as: Date.self)
                        case .ended:
                            hoverDate = nil
                        }
                    }
                    .onChange(of: geo.size.width, initial: true) { _, w in plotWidth = w }
                    .accessibilityHidden(true)
            }
        }
        // Live-тик не анимирует перестройку линий (иначе морфинг каждые ~2 с).
        .transaction { $0.animation = nil }
    }

    /// Видимое окно `[from, to]` (домен оси X). Range → фиксированный диапазон на
    /// весь период. Live → следит за `now`, но левую границу не растягиваем за
    /// пределы реально доступных данных: без daemon-истории (или в первые секунды
    /// до её подгрузки) короткий буфер иначе «схлопывается» в полоску на широкой оси.
    private var window: (from: Date, to: Date) {
        let base = coordinator.charts.visibleRange()
        if case .live = coordinator.charts.mode,
           let earliest = allSegments.flatMap({ $0.points }).map(\.ts).min(),
           earliest > base.from {
            let pad = min(base.to.timeIntervalSince(earliest) * 0.03, 30)
            return (earliest.addingTimeInterval(-pad), base.to)
        }
        return base
    }
    private var rangeSeconds: TimeInterval { window.to.timeIntervalSince(window.from) }
    /// Адаптивное число тиков — по ширине графика (компактные модули → реже).
    private var tickTarget: Int { ChartTimeAxis.targetTickCount(width: plotWidth, rangeSeconds: rangeSeconds) }

    // MARK: - States

    private var loading: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        Text(hasEnabled ? "Нет данных за период" : "Метрики скрыты")
            .font(DesignTokens.fontSecondary)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tooltip

    private func tooltip(_ snap: HoverSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: ChartTimeAxis.tooltipLabel(snap.ts, rangeSeconds: rangeSeconds))
                .font(DesignTokens.fontSecondary)
                .foregroundStyle(.secondary)
            ForEach(snap.values, id: \.metric) { v in
                HStack(spacing: 6) {
                    Circle().fill(color(v.metric)).frame(width: 6, height: 6)
                    Text(name(v.metric)).font(DesignTokens.fontSecondary)
                    Spacer(minLength: 10)
                    Text(verbatim: ChartFormatting.value(v.value, unit: unit))
                        .font(DesignTokens.fontSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(BlikPalette.surface2.resolve(scheme)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(BlikPalette.line.resolve(scheme), lineWidth: 1),
        )
        .fixedSize()
    }

    // MARK: - Data

    private var enabledMetrics: [String] {
        config.metrics.filter { config.enabledMetrics.contains($0) }
    }

    private var hasEnabled: Bool { !enabledMetrics.isEmpty }

    private var pointsByMetric: [String: [ChartPlotPoint]] {
        var out: [String: [ChartPlotPoint]] = [:]
        for m in enabledMetrics {
            out[m] = ChartData.points(coordinator.charts, metric: m)
        }
        return out
    }

    private var allSegments: [ChartSeriesSegment] {
        enabledMetrics.flatMap { ChartData.segments(coordinator.charts, metric: $0) }
    }

    private var hasData: Bool { allSegments.contains { !$0.points.isEmpty } }

    private var hoverSnapshot: HoverSnapshot? {
        guard let hoverDate else { return nil }
        let byMetric = pointsByMetric
        let allTs = byMetric.values.flatMap { $0 }.map(\.ts)
        guard let nearest = allTs.min(by: {
            abs($0.timeIntervalSince(hoverDate)) < abs($1.timeIntervalSince(hoverDate))
        }) else { return nil }
        var values: [HoverValue] = []
        for m in enabledMetrics {
            guard let p = (byMetric[m] ?? []).min(by: {
                abs($0.ts.timeIntervalSince(nearest)) < abs($1.ts.timeIntervalSince(nearest))
            }) else { continue }
            values.append(HoverValue(metric: m, value: p.value))
        }
        return HoverSnapshot(ts: nearest, values: values)
    }

    // MARK: - Scales / formatting

    private var unit: MetricUnit { MetricCatalog.unit(for: config.metrics.first ?? "") }

    private var yDomain: ClosedRange<Double> {
        if unit == .percent { return 0...100 }
        let values = allSegments.flatMap { $0.points }.map(\.value)
        guard let hi = values.max(), let lo = values.min() else { return 0...1 }
        guard hi > lo else { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.15
        return (lo - pad)...(hi + pad)
    }

    private var gridColor: Color { BlikPalette.muted.resolve(scheme).opacity(0.15) }

    private func color(_ metric: String) -> Color {
        ChartSeriesColor.color(config.metrics.firstIndex(of: metric) ?? 0)
    }

    private func name(_ metric: String) -> String {
        coordinator.metricNames.displayName(for: metric, default: MetricNaming.fallback(metric))
    }

    private struct HoverValue { let metric: String; let value: Double }
    private struct HoverSnapshot { let ts: Date; let values: [HoverValue] }
}
