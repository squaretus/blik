import Foundation
import IOKit

/// Читает сырой снимок системных ресурсов (CPU/RAM/GPU/Disk) через Mach и
/// IORegistry. **Не требует root** — но в проекте вызывается из хелпера ради
/// единообразия с SMC-чтением. Возвращает кумулятивные счётчики (CPU ticks, disk
/// bytes) + мгновенные показатели (RAM, GPU); дельту в rate считает
/// `ResourceUsageCalculator` на стороне клиента (хелпер stateless).
///
/// Все подсистемы best-effort: GPU/Disk недоступны на части машин → `nil`/пустой
/// массив (graceful degradation), снимок всё равно валиден.
public struct ResourceReader {

    /// Топология CPU (P/E per ядро) статична в пределах загрузки ОС — определяем
    /// один раз по железу, не угадываем по порядку нумерации.
    private static let topology = CPUTopologyDetector.detect()

    public init() {}

    public func read() -> ResourceSnapshot {
        let total = Self.sysctlU64("hw.memsize") ?? 0
        return ResourceSnapshot(
            timestamp: Date(),
            cpuCores: Self.readCPU(),
            memory: Self.readMemory(total: total),
            gpu: Self.readGPU(systemMemoryTotal: total),
            disks: Self.readDisks(),
        )
    }

    // MARK: - CPU (host_processor_info, кумулятивные ticks per logical core)

    private static func readCPU() -> [CPUCoreTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                     &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return [] }
        defer {
            let address = vm_address_t(UInt(bitPattern: UnsafeMutableRawPointer(info)))
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, address, size)
        }

        // Тип ядра (P/E) берём из авторитетной топологии (device-tree), а не из
        // допущения о порядке нумерации — корректно на M1–M4 и Intel.
        let count = Int(cpuCount)
        return info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: count) { ptr in
            (0..<count).map { i in
                let ticks = ptr[i].cpu_ticks
                return CPUCoreTicks(
                    index: i,
                    type: topology.type(for: i),
                    user: UInt64(ticks.0),    // CPU_STATE_USER
                    system: UInt64(ticks.1),  // CPU_STATE_SYSTEM
                    idle: UInt64(ticks.2),    // CPU_STATE_IDLE
                    nice: UInt64(ticks.3),    // CPU_STATE_NICE
                )
            }
        }
    }

    // MARK: - RAM (host_statistics64 + hw.memsize)

    private static func readMemory(total: UInt64) -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return MemoryStats(used: 0, wired: 0, compressed: 0, cached: 0,
                               total: total, pressurePercent: 0)
        }

        let ps = UInt64(vm_kernel_page_size)
        // Used = active + wired — реально занятая, нереклеймируемая память (как
        // считает btop / "Memory Used"). inactive/cached/compressed/free
        // реклеймируемы и в used НЕ входят. Прошлая формула (app+wired+compressed)
        // переоценивала вдвое (Activity-Monitor-стиль с большим compressor-пулом).
        let active = UInt64(stats.active_count) * ps
        let wired = UInt64(stats.wire_count) * ps
        let compressed = UInt64(stats.compressor_page_count) * ps
        let cached = UInt64(stats.external_page_count) * ps
        let used = active + wired
        let pressure = total > 0 ? min(100, Double(used) / Double(total) * 100) : 0

        return MemoryStats(used: used, wired: wired, compressed: compressed,
                           cached: cached, total: total, pressurePercent: pressure)
    }

    // MARK: - GPU (IORegistry IOAccelerator → PerformanceStatistics)

    private static func readGPU(systemMemoryTotal: UInt64) -> GPUStats? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == kIOReturnSuccess
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var result: GPUStats?
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            guard let perf = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            let util = (perf["Device Utilization %"] as? NSNumber)?.doubleValue
                ?? (perf["GPU Activity(%)"] as? NSNumber)?.doubleValue
            let used = (perf["In use system memory"] as? NSNumber)?.uint64Value
                ?? (perf["Alloc system memory"] as? NSNumber)?.uint64Value

            if util != nil || used != nil {
                // Apple Silicon — unified memory: GPU делит system RAM, total = hw.memsize.
                result = GPUStats(utilizationPercent: util ?? 0,
                                  memoryUsed: used ?? 0,
                                  memoryTotal: systemMemoryTotal)
                break
            }
        }
        return result
    }

    // MARK: - Disk IO (IORegistry IOBlockStorageDriver → Statistics)

    private static func readDisks() -> [DiskIOCounters] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == kIOReturnSuccess
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var out: [DiskIOCounters] = []
        while case let driver = IOIteratorNext(iterator), driver != IO_OBJECT_NULL {
            defer { IOObjectRelease(driver) }
            guard let stats = IORegistryEntryCreateCFProperty(
                driver, "Statistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            let written = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            let name = bsdName(of: driver) ?? "disk\(out.count)"
            out.append(DiskIOCounters(name: name, bytesRead: read, bytesWritten: written))
        }
        return out
    }

    /// BSD-имя (`disk0`) из дочернего `IOMedia` драйвера.
    private static func bsdName(of entry: io_registry_entry_t) -> String? {
        IORegistryEntrySearchCFProperty(
            entry, kIOServicePlane, "BSD Name" as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively),
        ) as? String
    }

    // MARK: - sysctl helpers

    private static func sysctlU64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }
}
