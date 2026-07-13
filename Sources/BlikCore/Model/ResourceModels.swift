import Foundation

// MARK: - Сырой снимок (то, что отдаёт хелпер)

/// Мгновенный снимок системных счётчиков ресурсов. Кумулятивные счётчики
/// (CPU ticks, disk bytes) превращаются в rate дельтой между двумя снимками в
/// `ResourceUsageCalculator` — поэтому хелпер остаётся stateless (как `readState`).
public struct ResourceSnapshot: Equatable, Codable {
    public var timestamp: Date
    public var cpuCores: [CPUCoreTicks]
    public var memory: MemoryStats
    /// `nil` — железо не отдало GPU-статистику (graceful degradation).
    public var gpu: GPUStats?
    public var disks: [DiskIOCounters]

    public init(timestamp: Date, cpuCores: [CPUCoreTicks], memory: MemoryStats,
                gpu: GPUStats?, disks: [DiskIOCounters]) {
        self.timestamp = timestamp
        self.cpuCores = cpuCores
        self.memory = memory
        self.gpu = gpu
        self.disks = disks
    }
}

public enum CPUCoreType: String, Codable, Equatable, Sendable {
    case performance = "P"
    case efficiency = "E"
}

/// Кумулятивные тики одного логического ядра (`host_processor_info`).
public struct CPUCoreTicks: Equatable, Codable {
    public let index: Int
    public let type: CPUCoreType
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public init(index: Int, type: CPUCoreType, user: UInt64, system: UInt64,
                idle: UInt64, nice: UInt64) {
        self.index = index
        self.type = type
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// Кумулятивные байты одного физического диска (`IOBlockStorageDriver`).
public struct DiskIOCounters: Equatable, Codable {
    public let name: String
    public let bytesRead: UInt64
    public let bytesWritten: UInt64

    public init(name: String, bytesRead: UInt64, bytesWritten: UInt64) {
        self.name = name
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
    }
}

/// Мгновенная статистика RAM (байты). Агрегатная, без ядер.
public struct MemoryStats: Equatable, Codable {
    public let used: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let cached: UInt64
    public let total: UInt64
    public let pressurePercent: Double

    public init(used: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64,
                total: UInt64, pressurePercent: Double) {
        self.used = used
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.total = total
        self.pressurePercent = pressurePercent
    }
}

/// Мгновенная статистика GPU (агрегат — macOS не отдаёт per-core util).
public struct GPUStats: Equatable, Codable {
    public let utilizationPercent: Double
    public let memoryUsed: UInt64
    public let memoryTotal: UInt64

    public init(utilizationPercent: Double, memoryUsed: UInt64, memoryTotal: UInt64) {
        self.utilizationPercent = utilizationPercent
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
    }
}

// MARK: - Производные показатели (то, что видит UI и шлёт телеметрия)

/// Производные показатели за интервал между двумя снимками. CPU и disk —
/// rate из дельты кумулятивных счётчиков; RAM/GPU — мгновенные passthrough.
public struct ResourceReading: Equatable, Codable {
    public var timestamp: Date
    public var cpuCores: [CPUCoreUsage]
    /// Busy% усреднённый по всем ядрам (для KPI-плитки).
    public var cpuOverallBusyPercent: Double
    public var memory: MemoryStats
    public var gpu: GPUStats?
    public var disks: [DiskIORate]

    public init(timestamp: Date, cpuCores: [CPUCoreUsage],
                cpuOverallBusyPercent: Double, memory: MemoryStats,
                gpu: GPUStats?, disks: [DiskIORate]) {
        self.timestamp = timestamp
        self.cpuCores = cpuCores
        self.cpuOverallBusyPercent = cpuOverallBusyPercent
        self.memory = memory
        self.gpu = gpu
        self.disks = disks
    }

    /// Пустое чтение (нет производных) — для первого сэмпла без `prev`.
    public static func empty(timestamp: Date, memory: MemoryStats,
                             gpu: GPUStats?) -> ResourceReading {
        ResourceReading(timestamp: timestamp, cpuCores: [],
                        cpuOverallBusyPercent: 0, memory: memory,
                        gpu: gpu, disks: [])
    }

    /// Средний busy% по производительным (P) ядрам. `0`, если их нет.
    public var averagePerformanceBusy: Double { averageBusy(of: .performance) }

    /// Средний busy% по энергоэффективным (E) ядрам. `0`, если их нет.
    public var averageEfficiencyBusy: Double { averageBusy(of: .efficiency) }

    /// Суммарная скорость дискового I/O (чтение + запись), байт/сек.
    public var totalDiskBytesPerSec: Double {
        disks.reduce(0) { $0 + $1.readBytesPerSec + $1.writeBytesPerSec }
    }

    private func averageBusy(of type: CPUCoreType) -> Double {
        let cores = cpuCores.filter { $0.type == type }
        guard !cores.isEmpty else { return 0 }
        return cores.map(\.busyPercent).reduce(0, +) / Double(cores.count)
    }
}

/// Загрузка одного ядра за интервал, в процентах (сумма ≈ 100).
/// `nice`-тики свёрнуты в `userPercent` (стандартное поведение).
public struct CPUCoreUsage: Equatable, Codable {
    public let index: Int
    public let type: CPUCoreType
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double

    public init(index: Int, type: CPUCoreType, userPercent: Double,
                systemPercent: Double, idlePercent: Double) {
        self.index = index
        self.type = type
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
    }

    /// Busy% = user + system (= 100 − idle). Для heatmap (одно значение на ядро).
    public var busyPercent: Double { userPercent + systemPercent }
}

/// Скорость IO одного диска (байт/сек) за интервал.
public struct DiskIORate: Equatable, Codable {
    public let name: String
    public let readBytesPerSec: Double
    public let writeBytesPerSec: Double

    public init(name: String, readBytesPerSec: Double, writeBytesPerSec: Double) {
        self.name = name
        self.readBytesPerSec = readBytesPerSec
        self.writeBytesPerSec = writeBytesPerSec
    }
}
