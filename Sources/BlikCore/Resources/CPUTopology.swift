import Foundation
#if canImport(IOKit)
import IOKit
#endif

/// Маппинг «логический индекс CPU → тип ядра (P/E)». Определяется по железу
/// (а не по допущению о порядке нумерации), поэтому корректен на любой
/// конфигурации: Apple Silicon M1–M4 (hybrid), Intel i7/i9 Mac (uniform),
/// Linux big.LITTLE / Intel hybrid (по capacity).
public struct CPUTopology: Equatable {
    public let coreTypes: [Int: CPUCoreType]
    public let coreCount: Int

    public init(coreTypes: [Int: CPUCoreType], coreCount: Int) {
        self.coreTypes = coreTypes
        self.coreCount = coreCount
    }

    /// Тип ядра по логическому индексу. Неизвестный индекс → `.performance`
    /// (безопасный дефолт: не прячем нагрузку в «эффективную» группу).
    public func type(for index: Int) -> CPUCoreType {
        coreTypes[index] ?? .performance
    }

    // MARK: - Pure builders (тестируемы без железа)

    /// Из записей device-tree (`logical-cpu-id` + `cluster-type`). `cluster-type`,
    /// начинающийся на «E» → efficiency, иначе performance.
    public static func from(entries: [(logicalId: Int, clusterType: String)]) -> CPUTopology {
        var map: [Int: CPUCoreType] = [:]
        for e in entries {
            map[e.logicalId] = e.clusterType.uppercased().hasPrefix("E") ? .efficiency : .performance
        }
        return CPUTopology(coreTypes: map, coreCount: map.count)
    }

    /// Однородная топология: все ядра performance (Intel Mac, неизвестное железо).
    public static func uniform(logicalCount: Int) -> CPUTopology {
        let n = max(0, logicalCount)
        var map: [Int: CPUCoreType] = [:]
        for i in 0..<n { map[i] = .performance }
        return CPUTopology(coreTypes: map, coreCount: n)
    }
}

/// Определяет `CPUTopology` текущей машины. Топология статична в пределах
/// загрузки ОС, поэтому результат можно кэшировать.
public enum CPUTopologyDetector {

    public static func detect() -> CPUTopology {
        #if canImport(IOKit)
        // Apple Silicon: device-tree даёт точный cluster-type per ядро.
        // Hybrid детектируем по наличию хотя бы одного E-ядра; иначе (Intel Mac
        // или device-tree без cluster-type) — uniform performance.
        if let entries = deviceTreeEntries(),
           entries.contains(where: { $0.clusterType.uppercased().hasPrefix("E") }) {
            return CPUTopology.from(entries: entries)
        }
        return CPUTopology.uniform(logicalCount: logicalCPUCount())
        #else
        // TODO(linux): /sys/devices/system/cpu/cpuN/cpu_capacity — макс capacity
        // performance, ниже efficiency. Реализуем при добавлении Linux-таргета.
        return CPUTopology.uniform(logicalCount: logicalCPUCount())
        #endif
    }

    // MARK: - macOS / Apple Silicon

    #if canImport(IOKit)
    private static func deviceTreeEntries() -> [(logicalId: Int, clusterType: String)]? {
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }

        var iter = io_iterator_t()
        guard IORegistryEntryGetChildIterator(root, kIODeviceTreePlane, &iter) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }

        var out: [(logicalId: Int, clusterType: String)] = []
        while case let child = IOIteratorNext(iter), child != IO_OBJECT_NULL {
            defer { IOObjectRelease(child) }
            guard let clusterType = dataString(child, "cluster-type") else { continue }
            let logicalId = dataInt(child, "logical-cpu-id") ?? out.count
            out.append((logicalId, clusterType))
        }
        return out.isEmpty ? nil : out
    }

    /// CFData с ASCII-строкой («E»/«P»), возможно null-terminated.
    private static func dataString(_ entry: io_registry_entry_t, _ key: String) -> String? {
        guard let data = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Data else { return nil }
        let bytes = data.prefix { $0 != 0 }
        let s = String(decoding: bytes, as: UTF8.self)
        return s.isEmpty ? nil : s
    }

    /// CFData с little-endian Int (обычно 4 байта).
    private static func dataInt(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        guard let data = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Data, !data.isEmpty else { return nil }
        var value = 0
        for (i, byte) in data.prefix(8).enumerated() { value |= Int(byte) << (8 * i) }
        return value
    }
    #endif

    // MARK: - Shared

    private static func logicalCPUCount() -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.logicalcpu", &value, &size, nil, 0) == 0, value > 0 {
            return Int(value)
        }
        return ProcessInfo.processInfo.activeProcessorCount
    }
}
