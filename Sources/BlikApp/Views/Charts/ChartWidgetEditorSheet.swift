import SwiftUI
import BlikShared
import BlikCore
import BlikDesign

/// Редактор виджета графиков: мультивыбор метрик (фильтр по совместимости unit'а
/// с типом виджета), пороги для gauge и «Сбросить».
///
/// Каталог метрик строится из текущего снимка сенсоров/вентиляторов/ресурсов
/// (`MetricCatalog`), отображаемые имена — через `MetricNameStore` (переименования
/// применяются). Метрики виджета, отсутствующие в текущем снимке, всё равно
/// показываются (чтобы их можно было снять).
struct ChartWidgetEditorSheet: View {
    let config: ChartWidgetConfig
    /// Колбэк сохранения изменённой конфигурации.
    var onSave: (ChartWidgetConfig) -> Void = { _ in }
    /// Колбэк сброса виджета к дефолту.
    var onReset: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppCoordinator.self) private var coordinator

    @State private var selected: Set<String>
    @State private var warn: Double
    @State private var crit: Double

    init(config: ChartWidgetConfig,
         onSave: @escaping (ChartWidgetConfig) -> Void = { _ in },
         onReset: @escaping () -> Void = {}) {
        self.config = config
        self.onSave = onSave
        self.onReset = onReset
        _selected = State(initialValue: Set(config.metrics))
        _warn = State(initialValue: config.warnThreshold ?? 80)
        _crit = State(initialValue: config.critThreshold ?? 95)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(config.title)
                .font(DesignTokens.fontPrimaryMedium)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            List {
                Section("Метрики") {
                    ForEach(options) { entry in
                        metricRow(entry)
                    }
                }
                .listRowInsets(BlikPageMetrics.rowInsets)

                if showsThresholds {
                    Section("Пороги") {
                        thresholdRow("Предупреждение", value: $warn)
                        thresholdRow("Критично", value: $crit)
                    }
                    .listRowInsets(BlikPageMetrics.rowInsets)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            footer
        }
        .frame(width: 400, height: 460)
    }

    // MARK: - Rows

    private func metricRow(_ entry: MetricCatalogEntry) -> some View {
        Button {
            toggle(entry.key)
        } label: {
            HStack {
                Text(entry.displayName)
                    .font(DesignTokens.fontPrimary)
                    .foregroundStyle(.primary)
                Spacer()
                if selected.contains(entry.key) {
                    Image(systemName: "checkmark")
                        .font(DesignTokens.fontPrimaryMedium)
                        .foregroundStyle(DesignTokens.accent.resolve(colorScheme))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func thresholdRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .font(DesignTokens.fontPrimary)
            Spacer()
            Text(verbatim: "\(Int(value.wrappedValue.rounded()))%")
                .font(DesignTokens.fontPrimaryMedium)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
            Stepper("", value: value, in: 0...100, step: 5)
                .labelsHidden()
        }
    }

    private var footer: some View {
        HStack {
            Button(role: .destructive) {
                onReset()
                dismiss()
            } label: {
                Text("Сбросить")
                    .font(DesignTokens.fontPrimaryMedium)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.red)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Отмена")
                    .font(DesignTokens.fontPrimaryMedium)
            }
            .buttonStyle(.bordered)

            Button {
                save()
            } label: {
                Text("Сохранить")
                    .font(DesignTokens.fontPrimaryMedium)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.accent.resolve(colorScheme))
            .disabled(selected.isEmpty)
        }
        .padding(20)
    }

    // MARK: - Logic

    /// Единица измерения виджета — метрики каталога фильтруются по совместимости.
    private var widgetUnit: MetricUnit {
        switch config.kind {
        case .memoryRadial: return .bytes
        case .gauge:        return .percent
        case .multiArea, .singleArea:
            return MetricCatalog.unit(for: config.metrics.first ?? "")
        }
    }

    /// Мультивыбор только для наложенных областей; остальные типы — одна метрика.
    private var isMultiSelect: Bool { config.kind == .multiArea }

    private var showsThresholds: Bool { config.kind == .gauge }

    /// Совместимые метрики: каталог по unit'у + текущие метрики виджета,
    /// которых нет в снимке (чтобы их можно было снять).
    private var options: [MetricCatalogEntry] {
        var list = MetricCatalog.entries(
            fans: coordinator.fan.fans,
            sensors: coordinator.fan.sensors,
            reading: coordinator.resource.resources,
            names: coordinator.metricNames,
        ).filter { $0.unit == widgetUnit }

        let present = Set(list.map(\.key))
        for m in config.metrics where !present.contains(m) {
            let def = MetricNaming.fallback(m)
            list.append(MetricCatalogEntry(
                key: m, defaultName: def,
                displayName: coordinator.metricNames.displayName(for: m, default: def),
                unit: widgetUnit,
            ))
        }
        return list
    }

    private func toggle(_ key: String) {
        if isMultiSelect {
            if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
        } else {
            selected = [key]
        }
    }

    private func save() {
        // Порядок метрик — прежний порядок, затем новые (стабильность индексов цвета).
        let ordered = config.metrics.filter { selected.contains($0) }
            + options.map(\.key).filter { selected.contains($0) && !config.metrics.contains($0) }

        var cfg = config
        cfg.metrics = ordered
        cfg.enabledMetrics = Set(ordered)
        if showsThresholds {
            cfg.warnThreshold = min(warn, crit)
            cfg.critThreshold = max(warn, crit)
        }
        onSave(cfg)
        dismiss()
    }
}
