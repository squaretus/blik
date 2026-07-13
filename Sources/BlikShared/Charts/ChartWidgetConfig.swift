import Foundation
import BlikCore

/// Тип визуализации виджета графиков.
public enum ChartWidgetKind: String, Codable, Sendable {
    /// Кольцо заполнения (память): единственная метрика в байтах.
    case memoryRadial
    /// Стрелочный индикатор с порогами (CPU/GPU нагрузка).
    case gauge
    /// Наложенные области нескольких метрик одного unit'а.
    case multiArea
    /// Область одной метрики.
    case singleArea
}

/// Конфигурация одного виджета графиков. Набор виджетов фиксирован (зеркало
/// веб-«Избранного»), добавление/удаление не предусмотрено — редактируется
/// только содержимое (выбор метрик, пороги).
public struct ChartWidgetConfig: Codable, Identifiable, Equatable, Sendable {
    /// Стабильный строковый id (совпадает с дефолтным ключом виджета).
    public var id: String
    public var kind: ChartWidgetKind
    public var title: String
    /// Все метрики, доступные виджету (для мультивыбора в редакторе).
    public var metrics: [String]
    /// Включённые (видимые) метрики — toggle легенды, персистится.
    public var enabledMetrics: Set<String>
    /// Порог «предупреждение» (для gauge). `nil` — не задан.
    public var warnThreshold: Double?
    /// Порог «критично» (для gauge). `nil` — не задан.
    public var critThreshold: Double?

    public init(id: String, kind: ChartWidgetKind, title: String,
                metrics: [String], enabledMetrics: Set<String>? = nil,
                warnThreshold: Double? = nil, critThreshold: Double? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.metrics = metrics
        self.enabledMetrics = enabledMetrics ?? Set(metrics)
        self.warnThreshold = warnThreshold
        self.critThreshold = critThreshold
    }

    /// Фиксированный набор виджетов по умолчанию — зеркало веб-страницы
    /// «Избранное». Порядок = порядок отображения в сетке.
    public static let defaults: [ChartWidgetConfig] = [
        ChartWidgetConfig(id: "memory", kind: .memoryRadial, title: "Память",
                          metrics: [MetricKey.memoryUsed]),
        ChartWidgetConfig(id: "gpu", kind: .gauge, title: "GPU",
                          metrics: [MetricKey.gpuUsage],
                          warnThreshold: 80, critThreshold: 95),
        ChartWidgetConfig(id: "cpu", kind: .gauge, title: "CPU",
                          metrics: [MetricKey.cpuUsageOverall],
                          warnThreshold: 70, critThreshold: 90),
        ChartWidgetConfig(id: "load", kind: .multiArea, title: "Нагрузка",
                          metrics: [MetricKey.cpuUsageOverall, MetricKey.gpuUsage, MetricKey.memoryPressure]),
        ChartWidgetConfig(id: "temps", kind: .multiArea, title: "Температуры",
                          metrics: [MetricKey.tempPCoreAvg, MetricKey.tempECoreAvg, MetricKey.tempGPUAvg]),
        ChartWidgetConfig(id: "gpuMemory", kind: .singleArea, title: "Память GPU",
                          metrics: [MetricKey.gpuMemoryUsed]),
        ChartWidgetConfig(id: "ramUsed", kind: .singleArea, title: "Занято RAM",
                          metrics: [MetricKey.memoryUsed]),
    ]
}
