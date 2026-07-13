import XCTest
@testable import BlikCore

/// Тесты чистого маппера снимка датчиков/ресурсов в `[MetricSample]`.
final class MetricSampleMapperTests: XCTestCase {

    private let ts = Date(timeIntervalSince1970: 1_700_000_000)

    private func value(_ samples: [MetricSample], _ metric: String) -> Double? {
        samples.first { $0.metric == metric }?.value
    }

    private func memory(used: UInt64 = 8_000, pressure: Double = 42) -> MemoryStats {
        MemoryStats(used: used, wired: 0, compressed: 0, cached: 0, total: 16_000, pressurePercent: pressure)
    }

    private func core(_ index: Int, _ type: CPUCoreType, busy: Double) -> CPUCoreUsage {
        CPUCoreUsage(index: index, type: type, userPercent: busy / 2,
                     systemPercent: busy / 2, idlePercent: 100 - busy)
    }

    // MARK: - Сенсоры и агрегаты

    func test_maps_each_sensor_to_temp_key() {
        let sensors = [
            SensorInfo(key: "TP0", name: "P", group: .cpuCores, temperature: 50),
            SensorInfo(key: "TG0", name: "G", group: .gpuCores, temperature: 60),
        ]
        let out = MetricSampleMapper.samples(fans: [], sensors: sensors, reading: nil, at: ts)
        XCTAssertEqual(value(out, MetricKey.temp("TP0")), 50)
        XCTAssertEqual(value(out, MetricKey.temp("TG0")), 60)
    }

    func test_temperature_group_averages_match_overview_math() {
        let sensors = [
            SensorInfo(key: "P0", name: "", group: .cpuCores, temperature: 40),
            SensorInfo(key: "P1", name: "", group: .cpuCores, temperature: 80),
            SensorInfo(key: "E0", name: "", group: .npuECores, temperature: 30),
            SensorInfo(key: "G0", name: "", group: .gpuCores, temperature: 55),
            SensorInfo(key: "G1", name: "", group: .gpuCores, temperature: 65),
        ]
        let out = MetricSampleMapper.samples(fans: [], sensors: sensors, reading: nil, at: ts)
        XCTAssertEqual(value(out, MetricKey.tempPCoreAvg), 60, "среднее P (40+80)/2")
        XCTAssertEqual(value(out, MetricKey.tempECoreAvg), 30, "единственный E-сенсор")
        XCTAssertEqual(value(out, MetricKey.tempGPUAvg), 60, "среднее GPU (55+65)/2")
    }

    func test_group_average_absent_when_no_sensors_in_group() {
        let out = MetricSampleMapper.samples(
            fans: [], sensors: [SensorInfo(key: "P0", name: "", group: .cpuCores, temperature: 40)],
            reading: nil, at: ts)
        XCTAssertNil(value(out, MetricKey.tempGPUAvg))
        XCTAssertNil(value(out, MetricKey.tempECoreAvg))
    }

    func test_maps_fans_to_rpm_keys() {
        let fans = [
            FanInfo(id: 0, actualSpeed: 2100, minimumSpeed: 1000, maximumSpeed: 5000, targetSpeed: 2100, isForced: false),
            FanInfo(id: 1, actualSpeed: 3300, minimumSpeed: 1000, maximumSpeed: 5000, targetSpeed: 3300, isForced: false),
        ]
        let out = MetricSampleMapper.samples(fans: fans, sensors: [], reading: nil, at: ts)
        XCTAssertEqual(value(out, MetricKey.fanRPM(0)), 2100)
        XCTAssertEqual(value(out, MetricKey.fanRPM(1)), 3300)
    }

    // MARK: - Первый сэмпл (empty reading)

    func test_empty_reading_emits_instant_memory_and_gpu_but_no_rate_derived() {
        let reading = ResourceReading.empty(
            timestamp: ts, memory: memory(used: 9_000, pressure: 33),
            gpu: GPUStats(utilizationPercent: 12, memoryUsed: 4_000, memoryTotal: 16_000))
        let out = MetricSampleMapper.samples(fans: [], sensors: [], reading: reading, at: ts)

        // Мгновенные значения эмитятся даже без дельты.
        XCTAssertEqual(value(out, MetricKey.memoryUsed), 9_000)
        XCTAssertEqual(value(out, MetricKey.memoryPressure), 33)
        XCTAssertEqual(value(out, MetricKey.gpuUsage), 12)
        XCTAssertEqual(value(out, MetricKey.gpuMemoryUsed), 4_000)

        // Производные по ставке отсутствуют (cpuCores пуст).
        XCTAssertNil(value(out, MetricKey.cpuUsageOverall))
        XCTAssertNil(value(out, MetricKey.diskReadTotal))
        XCTAssertNil(value(out, MetricKey.diskWriteTotal))
    }

    func test_gpu_metrics_absent_when_reading_has_no_gpu() {
        let reading = ResourceReading.empty(timestamp: ts, memory: memory(), gpu: nil)
        let out = MetricSampleMapper.samples(fans: [], sensors: [], reading: reading, at: ts)
        XCTAssertNil(value(out, MetricKey.gpuUsage))
        XCTAssertNil(value(out, MetricKey.gpuMemoryUsed))
    }

    // MARK: - Производные (per-core, overall, суммы дисков)

    func test_rate_derived_metrics_present_when_cpuCores_nonempty() {
        let reading = ResourceReading(
            timestamp: ts,
            cpuCores: [core(0, .performance, busy: 20), core(1, .efficiency, busy: 40)],
            cpuOverallBusyPercent: 30,
            memory: memory(),
            gpu: nil,
            disks: [
                DiskIORate(name: "disk0", readBytesPerSec: 1_000, writeBytesPerSec: 2_000),
                DiskIORate(name: "disk1", readBytesPerSec: 500, writeBytesPerSec: 250),
            ])
        let out = MetricSampleMapper.samples(fans: [], sensors: [], reading: reading, at: ts)

        XCTAssertEqual(value(out, MetricKey.cpuCoreUsage(0)), 20)
        XCTAssertEqual(value(out, MetricKey.cpuCoreUsage(1)), 40)
        XCTAssertEqual(value(out, MetricKey.cpuUsageOverall), 30)
        XCTAssertEqual(value(out, MetricKey.diskReadTotal), 1_500, "сумма чтений всех дисков")
        XCTAssertEqual(value(out, MetricKey.diskWriteTotal), 2_250, "сумма записей всех дисков")
    }
}
