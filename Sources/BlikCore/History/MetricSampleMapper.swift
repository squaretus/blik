import Foundation

/// Чистый маппер снимка датчиков/ресурсов в плоский набор `MetricSample`.
///
/// Не делает I/O и не хранит состояние — вся математика агрегатов совпадает с
/// тем, что видит пользователь в Overview (`averageTemperature`), чтобы
/// графики и история давали те же числа.
public enum MetricSampleMapper {

    /// Собирает все сэмплы для одного тика.
    ///
    /// - `reading == nil` — снимок без ресурсов (только температуры и вентиляторы).
    /// - Мгновенные значения памяти/GPU эмитятся даже на самом первом сэмпле
    ///   (когда `reading` — `.empty` и `cpuCores` пуст): у них нет производных.
    /// - Производные по ставке (per-core usage, overall busy, суммарный disk I/O)
    ///   эмитятся только когда есть дельта, т.е. `cpuCores` непуст.
    public static func samples(
        fans: [FanInfo],
        sensors: [SensorInfo],
        reading: ResourceReading?,
        at ts: Date,
    ) -> [MetricSample] {
        var out: [MetricSample] = []

        // Температура на каждый сенсор.
        for sensor in sensors {
            out.append(MetricSample(metric: MetricKey.temp(sensor.key), ts: ts, value: sensor.temperature))
        }

        // Три температурных агрегата (та же математика, что OverviewPage.averageTemperature).
        appendGroupAverage(sensors, group: .cpuCores, metric: MetricKey.tempPCoreAvg, ts: ts, into: &out)
        appendGroupAverage(sensors, group: .npuECores, metric: MetricKey.tempECoreAvg, ts: ts, into: &out)
        appendGroupAverage(sensors, group: .gpuCores, metric: MetricKey.tempGPUAvg, ts: ts, into: &out)

        // Фактические обороты вентиляторов.
        for fan in fans {
            out.append(MetricSample(metric: MetricKey.fanRPM(fan.id), ts: ts, value: fan.actualSpeed))
        }

        guard let r = reading else { return out }

        // Мгновенные значения памяти — всегда (в т.ч. на первом сэмпле).
        out.append(MetricSample(metric: MetricKey.memoryUsed, ts: ts, value: Double(r.memory.used)))
        out.append(MetricSample(metric: MetricKey.memoryPressure, ts: ts, value: r.memory.pressurePercent))

        // Мгновенные значения GPU — всегда, если железо их отдало.
        if let gpu = r.gpu {
            out.append(MetricSample(metric: MetricKey.gpuUsage, ts: ts, value: gpu.utilizationPercent))
            out.append(MetricSample(metric: MetricKey.gpuMemoryUsed, ts: ts, value: Double(gpu.memoryUsed)))
        }

        // Производные по ставке — только при наличии дельты (не первый тик).
        if !r.cpuCores.isEmpty {
            for core in r.cpuCores {
                out.append(MetricSample(metric: MetricKey.cpuCoreUsage(core.index), ts: ts, value: core.busyPercent))
            }
            out.append(MetricSample(metric: MetricKey.cpuUsageOverall, ts: ts, value: r.cpuOverallBusyPercent))

            let read = r.disks.reduce(0.0) { $0 + $1.readBytesPerSec }
            let write = r.disks.reduce(0.0) { $0 + $1.writeBytesPerSec }
            out.append(MetricSample(metric: MetricKey.diskReadTotal, ts: ts, value: read))
            out.append(MetricSample(metric: MetricKey.diskWriteTotal, ts: ts, value: write))
        }

        return out
    }

    private static func appendGroupAverage(
        _ sensors: [SensorInfo],
        group: SensorGroup,
        metric: String,
        ts: Date,
        into out: inout [MetricSample],
    ) {
        let inGroup = sensors.filter { $0.group == group }
        guard !inGroup.isEmpty else { return }
        let avg = inGroup.map(\.temperature).reduce(0, +) / Double(inGroup.count)
        out.append(MetricSample(metric: metric, ts: ts, value: avg))
    }
}
