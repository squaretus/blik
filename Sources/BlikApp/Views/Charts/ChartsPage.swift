import SwiftUI
import BlikShared
import BlikCore
import BlikDesign

/// Вкладка «Графики» — модульный dashboard мониторинга:
/// toolbar (Live/период) → summary-strip (Память/CPU/GPU/Темп) → главный график
/// «Нагрузка» → сетка компактных модулей → отдельный блок «Температуры».
///
/// Композиция фиксирована; содержимое модулей (метрики/пороги) редактируется через
/// меню «…». Live-капчер работает только пока страница видима (`setVisible`).
struct ChartsPage: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.searchQuery) private var searchQuery

    // Контент на всю ширину detail-панели (одинаковый горизонтальный отступ даёт
    // BlikPageContainer). Сетки заполняют ширину: 4 плитки summary и 2 компактных
    // модуля равными долями.
    private let tileColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private let moduleColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)

    var body: some View {
        BlikPageContainer {
            ScrollView {
                // LazyVStack: off-screen модули не рендерятся и не крутят live-тик —
                // видимых графиков меньше → скролл не конкурирует с перерисовкой.
                LazyVStack(alignment: .leading, spacing: 22) {
                    ChartRangePicker(
                        mode: coordinator.charts.mode,
                        liveWindowSeconds: coordinator.charts.liveWindowSeconds,
                        onLive: enterLive,
                        onRange: enterRange,
                    )

                    if rangeUnavailable {
                        unavailableBanner
                    }

                    if visible("summary") {
                        summaryStrip
                    }

                    if let load = widget("load"), matches(load) {
                        multiModule(load, height: 244)
                    }

                    let compact = ["gpuMemory", "ramUsed"].compactMap(widget).filter(matches)
                    if !compact.isEmpty {
                        LazyVGrid(columns: moduleColumns, spacing: 16) {
                            ForEach(compact) { cfg in
                                singleModule(cfg, height: 168)
                            }
                        }
                    }

                    if let temps = widget("temps"), matches(temps) {
                        multiModule(temps, height: 216)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollPhaseChange { _, phase, _ in
                // Во время скролла ставим перерисовку тяжёлых графиков на паузу.
                coordinator.charts.setScrolling(phase != .idle)
            }
        }
        .onAppear {
            syncMetricsToQuery()
            coordinator.charts.setVisible(true)
        }
        .onDisappear { coordinator.charts.setVisible(false) }
    }

    // MARK: - Summary strip

    private var summaryStrip: some View {
        LazyVGrid(columns: tileColumns, spacing: 12) {
            if let m = widget("memory") {
                StatTile(title: "Память", metric: m.metrics.first ?? MetricKey.memoryUsed, unit: .bytes)
            }
            if let c = widget("cpu") {
                StatTile(title: "CPU", metric: c.metrics.first ?? MetricKey.cpuUsageOverall,
                         unit: .percent, warn: c.warnThreshold, crit: c.critThreshold)
            }
            if let g = widget("gpu") {
                StatTile(title: "GPU", metric: g.metrics.first ?? MetricKey.gpuUsage,
                         unit: .percent, warn: g.warnThreshold, crit: g.critThreshold)
            }
            if let t = widget("temps") {
                StatTile(title: "Температура", metric: t.metrics.first ?? MetricKey.tempPCoreAvg, unit: .celsius)
            }
        }
    }

    // MARK: - Modules

    /// Модуль одной серии: header с текущим значением + мин/сред/макс, график.
    private func singleModule(_ cfg: ChartWidgetConfig, height: CGFloat) -> some View {
        BlikPanel {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader(
                    title: cfg.title,
                    currentText: currentText(cfg),
                    currentColor: DesignTokens.accent.resolve(.dark),
                    stats: statsRow(cfg),
                    config: cfg,
                )
                MetricChart(config: cfg, height: height)
            }
        }
    }

    /// Модуль нескольких серий: header + график + легенда с текущими значениями.
    private func multiModule(_ cfg: ChartWidgetConfig, height: CGFloat) -> some View {
        BlikPanel {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader(title: cfg.title, config: cfg)
                MetricChart(config: cfg, height: height)
                SeriesLegend(config: cfg, color: seriesColor(cfg), name: seriesName, value: seriesValue(cfg))
            }
        }
    }

    private var unavailableBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(DesignTokens.amber)
            Text("История недоступна: хелпер не установлен или устарел. Доступен только Live.")
                .font(DesignTokens.fontSecondary)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.amber.opacity(0.10)),
        )
    }

    // MARK: - Helpers

    private var rangeUnavailable: Bool {
        if case .range = coordinator.charts.mode { return !coordinator.charts.helperAvailable }
        return false
    }

    private func widget(_ id: String) -> ChartWidgetConfig? {
        coordinator.chartWidgets.widgets.first { $0.id == id }
    }

    /// Фильтр по поиску: модуль виден, если query пуст или совпадает с названием
    /// модуля / отображаемым именем любой его метрики.
    private func matches(_ cfg: ChartWidgetConfig) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        if cfg.title.localizedCaseInsensitiveContains(q) { return true }
        return cfg.metrics.contains { seriesName($0).localizedCaseInsensitiveContains(q) }
    }

    /// Summary-strip виден, если query пуст или совпадает с любой tile-меткой.
    private func visible(_ id: String) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return ["память", "cpu", "gpu", "температура"].contains { $0.localizedCaseInsensitiveContains(q) }
    }

    private func currentText(_ cfg: ChartWidgetConfig) -> String? {
        guard let metric = cfg.metrics.first,
              let v = ChartData.current(coordinator.charts, metric: metric) else { return "—" }
        return ChartFormatting.value(v, unit: MetricCatalog.unit(for: metric))
    }

    private func statsRow(_ cfg: ChartWidgetConfig) -> [(String, String)] {
        guard let metric = cfg.metrics.first,
              let stats = ChartData.stats(ChartData.points(coordinator.charts, metric: metric)) else {
            return []
        }
        let unit = MetricCatalog.unit(for: metric)
        return [
            ("мин", ChartFormatting.value(stats.min, unit: unit)),
            ("сред", ChartFormatting.value(stats.avg, unit: unit)),
            ("макс", ChartFormatting.value(stats.max, unit: unit)),
        ]
    }

    private func seriesColor(_ cfg: ChartWidgetConfig) -> (String) -> Color {
        { metric in ChartSeriesColor.color(cfg.metrics.firstIndex(of: metric) ?? 0) }
    }

    private func seriesName(_ metric: String) -> String {
        coordinator.metricNames.displayName(for: metric, default: MetricNaming.fallback(metric))
    }

    private func seriesValue(_ cfg: ChartWidgetConfig) -> (String) -> String? {
        { metric in
            guard let v = ChartData.current(coordinator.charts, metric: metric) else { return nil }
            return ChartFormatting.value(v, unit: MetricCatalog.unit(for: metric))
        }
    }

    /// Union включённых метрик всех виджетов — нужен и для range-запроса, и для
    /// подтяжки daemon-истории в широком live-окне.
    private func syncMetricsToQuery() {
        let union = coordinator.chartWidgets.widgets.flatMap { $0.enabledMetrics }
        coordinator.charts.metricsToQuery = Array(Set(union))
    }

    private func enterLive(_ window: TimeInterval) {
        syncMetricsToQuery()
        let wasLive: Bool = { if case .live = coordinator.charts.mode { return true }; return false }()
        coordinator.charts.setLiveWindow(window)
        if !wasLive { coordinator.charts.setMode(.live) }
    }

    private func enterRange(_ range: ChartTimeRange) {
        syncMetricsToQuery()
        coordinator.charts.setMode(.range(range))
    }
}
