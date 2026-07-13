import Foundation

/// Стабильные строковые идентификаторы метрик. Общие для истории (SQLite),
/// переименования датчиков (`MetricNameStore`) и графиков.
///
/// Caseless enum — только namespace, инстансов нет.
public enum MetricKey {

    // MARK: - Билдеры (динамические ключи)

    /// Температура одного SMC-сенсора: `temp.TPD0`.
    public static func temp(_ smcKey: String) -> String { "temp.\(smcKey)" }

    /// Фактические обороты вентилятора: `fan.0.rpm`.
    public static func fanRPM(_ id: Int) -> String { "fan.\(id).rpm" }

    /// Загрузка одного логического ядра CPU (busy%): `cpu.core.3.usage`.
    public static func cpuCoreUsage(_ index: Int) -> String { "cpu.core.\(index).usage" }

    // MARK: - Температурные агрегаты

    public static let tempPCoreAvg = "cpu.pcore.avg"
    public static let tempECoreAvg = "cpu.ecore.avg"
    public static let tempGPUAvg = "gpu.avg"

    // MARK: - Ресурсные агрегаты (charted)

    public static let cpuUsageOverall = "cpu.usage.overall"
    public static let gpuUsage = "gpu.usage"
    public static let gpuMemoryUsed = "gpu.memory.used"
    public static let memoryUsed = "memory.used"
    public static let memoryPressure = "memory.pressure"
    public static let diskReadTotal = "disk.read.total"
    public static let diskWriteTotal = "disk.write.total"

    // MARK: - Non-charted строки вкладки «Ресурсы» (только для переименования)

    public static let memoryWired = "memory.wired"
    public static let memoryCompressed = "memory.compressed"
    public static let memoryCached = "memory.cached"
    public static let memoryTotal = "memory.total"
    public static let gpuMemory = "gpu.memory"

    /// Префикс температурных ключей — для фильтрации/детекции unit'а.
    public static let tempPrefix = "temp."
}
