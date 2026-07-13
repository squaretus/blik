import Foundation

/// Превращает два сырых снимка в производные показатели за интервал.
///
/// CPU%/ядро — доля дельты тиков (не зависит от wall-time); disk rate — дельта
/// байт, делённая на Δt. RAM/GPU мгновенные — passthrough. Чистая функция:
/// всё состояние (`prev`) приходит аргументом, легко тестируется.
public enum ResourceUsageCalculator {

    public static func reading(from prev: ResourceSnapshot?,
                               to curr: ResourceSnapshot) -> ResourceReading {
        guard let prev else {
            // Первый сэмпл: rate невозможен, отдаём только мгновенные показатели.
            return .empty(timestamp: curr.timestamp, memory: curr.memory, gpu: curr.gpu)
        }

        let cores = cpuUsage(prev: prev.cpuCores, curr: curr.cpuCores)
        let overall = cores.isEmpty
            ? 0
            : cores.map(\.busyPercent).reduce(0, +) / Double(cores.count)

        let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
        let disks = dt > 0 ? diskRates(prev: prev.disks, curr: curr.disks, dt: dt) : []

        return ResourceReading(
            timestamp: curr.timestamp,
            cpuCores: cores,
            cpuOverallBusyPercent: overall,
            memory: curr.memory,
            gpu: curr.gpu,
            disks: disks,
        )
    }

    // MARK: - Internals

    private static func cpuUsage(prev: [CPUCoreTicks],
                                 curr: [CPUCoreTicks]) -> [CPUCoreUsage] {
        let prevByIndex = Dictionary(prev.map { ($0.index, $0) },
                                     uniquingKeysWith: { a, _ in a })
        var out: [CPUCoreUsage] = []
        for c in curr {
            guard let p = prevByIndex[c.index] else { continue }
            let du = delta(c.user, p.user) + delta(c.nice, p.nice)
            let ds = delta(c.system, p.system)
            let di = delta(c.idle, p.idle)
            let total = du + ds + di
            guard total > 0 else {
                out.append(CPUCoreUsage(index: c.index, type: c.type,
                                        userPercent: 0, systemPercent: 0, idlePercent: 100))
                continue
            }
            let t = Double(total)
            out.append(CPUCoreUsage(
                index: c.index, type: c.type,
                userPercent: Double(du) / t * 100,
                systemPercent: Double(ds) / t * 100,
                idlePercent: Double(di) / t * 100,
            ))
        }
        return out
    }

    private static func diskRates(prev: [DiskIOCounters], curr: [DiskIOCounters],
                                  dt: TimeInterval) -> [DiskIORate] {
        let prevByName = Dictionary(prev.map { ($0.name, $0) },
                                    uniquingKeysWith: { a, _ in a })
        var out: [DiskIORate] = []
        for d in curr {
            guard let p = prevByName[d.name] else { continue }
            out.append(DiskIORate(
                name: d.name,
                readBytesPerSec: Double(delta(d.bytesRead, p.bytesRead)) / dt,
                writeBytesPerSec: Double(delta(d.bytesWritten, p.bytesWritten)) / dt,
            ))
        }
        return out
    }

    /// Δ с защитой от сброса/wraparound счётчика (curr < prev → 0).
    private static func delta(_ a: UInt64, _ b: UInt64) -> UInt64 { a >= b ? a - b : 0 }
}
