import BlikCore
import Foundation
import MCP

// MARK: - Граница XPC (мокается в тестах)

protocol MCPMetricsSource {
    func currentMetrics() -> CurrentMetricsPayload?
    func listMetrics() -> [String]?
    func queryHistory(metric: String, from: Date, to: Date) -> HistoryQueryResponse?
    /// nil = успех, иначе текст ошибки.
    func setFanPreset(percentage: Int) -> String?
}

// MARK: - Payload get_current_metrics

struct CurrentMetricsPayload: Codable {
    struct Temperatures: Codable {
        var pCoreAvgCelsius: Double?
        var eCoreAvgCelsius: Double?
        var gpuAvgCelsius: Double?
    }
    struct SensorEntry: Codable {
        var name: String
        var group: String
        var celsius: Double
    }
    struct CPUUsage: Codable {
        var overallBusyPercent: Double
        var pCoreBusyPercent: Double
        var eCoreBusyPercent: Double
    }
    struct Memory: Codable {
        var usedBytes: UInt64
        var totalBytes: UInt64
        var pressurePercent: Double
    }
    struct GPU: Codable {
        var utilizationPercent: Double
        var memoryUsedBytes: UInt64
        var memoryTotalBytes: UInt64
    }
    struct Fan: Codable {
        var id: Int
        var actualRPM: Int
        var targetRPM: Int
        var minRPM: Int
        var maxRPM: Int
        var mode: String   // "auto" | "manual"
    }

    var temperatures: Temperatures
    var sensors: [SensorEntry]
    var cpuUsage: CPUUsage?
    var memory: Memory?
    var gpu: GPU?
    var fans: [Fan]

    /// Чистая сборка из доменных моделей (та же математика агрегатов,
    /// что в MetricSampleMapper/Overview).
    static func build(sensors: [SensorInfo], fans: [FanInfo],
                      reading: ResourceReading?) -> CurrentMetricsPayload {
        func groupAvg(_ group: SensorGroup) -> Double? {
            let inGroup = sensors.filter { $0.group == group }
            guard !inGroup.isEmpty else { return nil }
            return inGroup.map(\.temperature).reduce(0, +) / Double(inGroup.count)
        }

        var cpuUsage: CPUUsage?
        if let r = reading, !r.cpuCores.isEmpty {
            cpuUsage = CPUUsage(
                overallBusyPercent: r.cpuOverallBusyPercent,
                pCoreBusyPercent: r.averagePerformanceBusy,
                eCoreBusyPercent: r.averageEfficiencyBusy)
        }

        return CurrentMetricsPayload(
            temperatures: Temperatures(
                pCoreAvgCelsius: groupAvg(.cpuCores),
                eCoreAvgCelsius: groupAvg(.npuECores),
                gpuAvgCelsius: groupAvg(.gpuCores)),
            sensors: sensors.map {
                SensorEntry(name: $0.name, group: $0.group.title, celsius: $0.temperature)
            },
            cpuUsage: cpuUsage,
            memory: reading.map {
                Memory(usedBytes: $0.memory.used, totalBytes: $0.memory.total,
                       pressurePercent: $0.memory.pressurePercent)
            },
            gpu: reading?.gpu.map {
                GPU(utilizationPercent: $0.utilizationPercent,
                    memoryUsedBytes: $0.memoryUsed, memoryTotalBytes: $0.memoryTotal)
            },
            fans: fans.map {
                Fan(id: $0.id, actualRPM: Int($0.actualSpeed),
                    targetRPM: Int($0.targetSpeed), minRPM: Int($0.minimumSpeed),
                    maxRPM: Int($0.maximumSpeed), mode: $0.isForced ? "manual" : "auto")
            })
    }
}

// MARK: - Инструменты

/// Определения и диспетчер MCP-инструментов. Чистый слой: никакого XPC,
/// источник данных приходит через MCPMetricsSource.
enum BlikMCPTools {
    static let validPresets = [0, 25, 50, 75, 100]
    static let maxHistoryMinutes = 10_080   // 7 дней — глубина ретенции истории
    static let defaultHistoryMinutes = 60

    static let toolList: [Tool] = [
        Tool(
            name: "get_current_metrics",
            description: """
            Текущие метрики Mac: температуры (средние по P-cores/E-cores/GPU и все \
            сенсоры), загрузка CPU/GPU, память RAM/VRAM, обороты вентиляторов.
            """,
            inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
            annotations: .init(readOnlyHint: true)),
        Tool(
            name: "list_metrics",
            description: "Ключи метрик, доступных в локальной истории (для query_metric_history).",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
            annotations: .init(readOnlyHint: true)),
        Tool(
            name: "query_metric_history",
            description: "История метрики: точки min/avg/max за период. Ретенция: raw 24 ч, минутные роллапы 7 дней.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "metric_key": .object([
                        "type": .string("string"),
                        "description": .string("Ключ метрики из list_metrics, например cpu.pcore.avg"),
                    ]),
                    "minutes": .object([
                        "type": .string("integer"),
                        "description": .string("Период в минутах назад от текущего момента (по умолчанию 60, максимум 10080 = 7 дней)"),
                    ]),
                ]),
                "required": .array([.string("metric_key")]),
            ]),
            annotations: .init(readOnlyHint: true)),
        Tool(
            name: "set_fan_preset",
            description: """
            Управляет ФИЗИЧЕСКИМИ вентиляторами Mac: ставит все кулеры на пресет \
            скорости. 0 — вернуть автоматическое управление системе, \
            25/50/75/100 — процент диапазона RPM.
            """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "percent": .object([
                        "type": .string("integer"),
                        "enum": .array(validPresets.map { .int($0) }),
                        "description": .string("0 = авто, иначе процент скорости"),
                    ]),
                ]),
                "required": .array([.string("percent")]),
            ]),
            annotations: .init(readOnlyHint: false, idempotentHint: true)),
    ]

    static func handle(name: String, arguments: [String: Value]?,
                       source: MCPMetricsSource) -> CallTool.Result {
        switch name {
        case "get_current_metrics":
            guard let payload = source.currentMetrics() else {
                return failure("Daemon blik недоступен — метрики не получены.")
            }
            return success(jsonText(payload))

        case "list_metrics":
            guard let metrics = source.listMetrics() else {
                return failure("Daemon blik недоступен — список метрик не получен.")
            }
            return success(jsonText(metrics.sorted()))

        case "query_metric_history":
            guard let metric = arguments?["metric_key"]?.stringValue, !metric.isEmpty else {
                return failure("Аргумент metric_key обязателен (см. list_metrics).")
            }
            let minutes = min(max(arguments?["minutes"]?.intValue ?? defaultHistoryMinutes, 1),
                              maxHistoryMinutes)
            let now = Date()
            guard let response = source.queryHistory(
                metric: metric,
                from: now.addingTimeInterval(-Double(minutes) * 60),
                to: now) else {
                return failure("Daemon blik недоступен — история не получена.")
            }
            return success(jsonText(response))

        case "set_fan_preset":
            guard let percent = arguments?["percent"]?.intValue else {
                return failure("Аргумент percent обязателен: один из \(validPresets).")
            }
            guard validPresets.contains(percent) else {
                return failure("Недопустимый percent \(percent): один из \(validPresets).")
            }
            if let error = source.setFanPreset(percentage: percent) {
                return failure("Не удалось применить пресет: \(error)")
            }
            let action = percent == 0
                ? "Кулеры возвращены в автоматический режим."
                : "Все кулеры переведены на \(percent)% диапазона скорости."
            return success(action)

        default:
            return failure("Неизвестный инструмент: \(name)")
        }
    }

    // MARK: - Helpers

    private static func success(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)],
                        isError: false)
    }

    private static func failure(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)],
                        isError: true)
    }

    private static func jsonText<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
