import Foundation
@preconcurrency import BlikCore

/// Единица измерения метрики — определяет форматтер значений/осей и
/// совместимость метрики с типом виджета в редакторе.
public enum MetricUnit: String, Codable, Sendable, CaseIterable {
    case celsius
    case percent
    case rpm
    case bytes
    case bytesPerSec
}

/// Элемент каталога метрик: стабильный ключ + дефолтное и отображаемое имя + unit.
public struct MetricCatalogEntry: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public let defaultName: String
    public let displayName: String
    public let unit: MetricUnit

    public init(key: String, defaultName: String, displayName: String, unit: MetricUnit) {
        self.key = key
        self.defaultName = defaultName
        self.displayName = displayName
        self.unit = unit
    }
}

/// Каталог доступных для графиков метрик — для редактора виджетов и легенд.
/// Строится из текущего снимка сенсоров/вентиляторов/ресурсов + агрегатов;
/// отображаемые имена берутся из `MetricNameStore` (кастомные переименования).
public enum MetricCatalog {

    /// Собирает каталог из текущих данных VM. `@MainActor` — читает `MetricNameStore`.
    @MainActor
    public static func entries(fans: [FanInfo], sensors: [SensorInfo],
                               reading: ResourceReading?,
                               names: MetricNameStore) -> [MetricCatalogEntry] {
        var raw: [(key: String, name: String, unit: MetricUnit)] = []

        // Температура на каждый сенсор.
        for s in sensors {
            raw.append((MetricKey.temp(s.key), s.name, .celsius))
        }
        // Температурные агрегаты.
        raw.append((MetricKey.tempPCoreAvg, "CPU P-ядра (сред.)", .celsius))
        raw.append((MetricKey.tempECoreAvg, "CPU E-ядра (сред.)", .celsius))
        raw.append((MetricKey.tempGPUAvg, "GPU (сред.)", .celsius))

        // Вентиляторы.
        for f in fans {
            raw.append((MetricKey.fanRPM(f.id), "Вентилятор \(f.id + 1)", .rpm))
        }

        // Ресурсные метрики.
        raw.append((MetricKey.cpuUsageOverall, "CPU нагрузка", .percent))
        if let reading {
            for core in reading.cpuCores.sorted(by: { $0.index < $1.index }) {
                raw.append((MetricKey.cpuCoreUsage(core.index), "CPU ядро \(core.index)", .percent))
            }
        }
        raw.append((MetricKey.gpuUsage, "GPU нагрузка", .percent))
        raw.append((MetricKey.gpuMemoryUsed, "Память GPU (занято)", .bytes))
        raw.append((MetricKey.memoryUsed, "Память (занято)", .bytes))
        raw.append((MetricKey.memoryPressure, "Давление памяти", .percent))
        raw.append((MetricKey.diskReadTotal, "Диск: чтение", .bytesPerSec))
        raw.append((MetricKey.diskWriteTotal, "Диск: запись", .bytesPerSec))

        // Дедуп по ключу с сохранением порядка.
        var seen = Set<String>()
        return raw.compactMap { entry in
            guard seen.insert(entry.key).inserted else { return nil }
            return MetricCatalogEntry(
                key: entry.key,
                defaultName: entry.name,
                displayName: names.displayName(for: entry.key, default: entry.name),
                unit: entry.unit,
            )
        }
    }

    /// Быстрое определение unit'а по ключу метрики — для форматтеров/легенд,
    /// когда полный каталог не нужен.
    public static func unit(for key: String) -> MetricUnit {
        if key.hasPrefix(MetricKey.tempPrefix)
            || key == MetricKey.tempPCoreAvg
            || key == MetricKey.tempECoreAvg
            || key == MetricKey.tempGPUAvg {
            return .celsius
        }
        if key.hasPrefix("fan.") { return .rpm }
        if key == MetricKey.diskReadTotal || key == MetricKey.diskWriteTotal {
            return .bytesPerSec
        }
        switch key {
        case MetricKey.memoryUsed, MetricKey.gpuMemoryUsed,
             MetricKey.memoryWired, MetricKey.memoryCompressed,
             MetricKey.memoryCached, MetricKey.memoryTotal, MetricKey.gpuMemory:
            return .bytes
        default:
            return .percent
        }
    }
}
