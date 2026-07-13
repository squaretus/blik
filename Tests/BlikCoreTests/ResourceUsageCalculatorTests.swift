import XCTest
@testable import BlikCore

final class ResourceUsageCalculatorTests: XCTestCase {

    // MARK: - Fixtures

    private func mem(_ used: UInt64 = 8_000_000_000) -> MemoryStats {
        MemoryStats(used: used, wired: 1_000_000_000, compressed: 500_000_000,
                    cached: 2_000_000_000, total: 16_000_000_000, pressurePercent: 25)
    }

    private func snapshot(at t: TimeInterval, cores: [CPUCoreTicks],
                          disks: [DiskIOCounters] = [], gpu: GPUStats? = nil,
                          memory: MemoryStats? = nil) -> ResourceSnapshot {
        ResourceSnapshot(timestamp: Date(timeIntervalSince1970: t), cpuCores: cores,
                         memory: memory ?? mem(), gpu: gpu, disks: disks)
    }

    private func core(_ i: Int, _ type: CPUCoreType, user: UInt64, system: UInt64,
                      idle: UInt64, nice: UInt64 = 0) -> CPUCoreTicks {
        CPUCoreTicks(index: i, type: type, user: user, system: system, idle: idle, nice: nice)
    }

    // MARK: - CPU per-core %

    func test_cpu_core_percentages_from_tick_delta() {
        let prev = snapshot(at: 0, cores: [core(0, .performance, user: 100, system: 50, idle: 850)])
        let curr = snapshot(at: 1, cores: [core(0, .performance, user: 200, system: 100, idle: 1700)])
        // Δuser=100 Δsystem=50 Δidle=850 → total=1000
        let reading = ResourceUsageCalculator.reading(from: prev, to: curr)

        XCTAssertEqual(reading.cpuCores.count, 1)
        let c = reading.cpuCores[0]
        XCTAssertEqual(c.userPercent, 10, accuracy: 0.001)
        XCTAssertEqual(c.systemPercent, 5, accuracy: 0.001)
        XCTAssertEqual(c.idlePercent, 85, accuracy: 0.001)
        XCTAssertEqual(c.busyPercent, 15, accuracy: 0.001)
        XCTAssertEqual(c.type, .performance)
    }

    func test_nice_ticks_folded_into_user() {
        let prev = snapshot(at: 0, cores: [core(0, .efficiency, user: 0, system: 0, idle: 0, nice: 0)])
        let curr = snapshot(at: 1, cores: [core(0, .efficiency, user: 100, system: 100, idle: 700, nice: 100)])
        // Δuser+Δnice=200, Δsystem=100, Δidle=700 → total=1000
        let reading = ResourceUsageCalculator.reading(from: prev, to: curr)
        let c = reading.cpuCores[0]
        XCTAssertEqual(c.userPercent, 20, accuracy: 0.001)
        XCTAssertEqual(c.systemPercent, 10, accuracy: 0.001)
        XCTAssertEqual(c.idlePercent, 70, accuracy: 0.001)
    }

    func test_idle_core_reports_100_percent_idle() {
        // Никаких изменений тиков между снимками → 100% idle, не деление на ноль.
        let same = core(0, .performance, user: 100, system: 50, idle: 850)
        let prev = snapshot(at: 0, cores: [same])
        let curr = snapshot(at: 1, cores: [same])
        let reading = ResourceUsageCalculator.reading(from: prev, to: curr)
        let c = reading.cpuCores[0]
        XCTAssertEqual(c.idlePercent, 100, accuracy: 0.001)
        XCTAssertEqual(c.busyPercent, 0, accuracy: 0.001)
    }

    func test_overall_busy_is_average_across_cores() {
        let prev = snapshot(at: 0, cores: [
            core(0, .performance, user: 0, system: 0, idle: 0),
            core(1, .performance, user: 0, system: 0, idle: 0),
        ])
        let curr = snapshot(at: 1, cores: [
            core(0, .performance, user: 200, system: 0, idle: 800),   // busy 20
            core(1, .performance, user: 600, system: 0, idle: 400),   // busy 60
        ])
        let reading = ResourceUsageCalculator.reading(from: prev, to: curr)
        XCTAssertEqual(reading.cpuOverallBusyPercent, 40, accuracy: 0.001)
    }

    // MARK: - First sample (no prev)

    func test_first_sample_yields_empty_derived_but_keeps_instantaneous() {
        let gpu = GPUStats(utilizationPercent: 42, memoryUsed: 1, memoryTotal: 2)
        let curr = snapshot(at: 0, cores: [core(0, .performance, user: 1, system: 1, idle: 1)],
                            disks: [DiskIOCounters(name: "disk0", bytesRead: 100, bytesWritten: 100)],
                            gpu: gpu, memory: mem(9_000_000_000))
        let reading = ResourceUsageCalculator.reading(from: nil, to: curr)

        XCTAssertTrue(reading.cpuCores.isEmpty)
        XCTAssertTrue(reading.disks.isEmpty)
        XCTAssertEqual(reading.cpuOverallBusyPercent, 0)
        XCTAssertEqual(reading.memory.used, 9_000_000_000)   // мгновенное — сохранено
        XCTAssertEqual(reading.gpu, gpu)                      // мгновенное — сохранено
    }

    // MARK: - Disk IO rate

    func test_disk_rate_from_cumulative_delta_over_time() {
        let prev = snapshot(at: 0, cores: [],
                            disks: [DiskIOCounters(name: "disk0", bytesRead: 1_000, bytesWritten: 2_000)])
        let curr = snapshot(at: 2, cores: [],
                            disks: [DiskIOCounters(name: "disk0", bytesRead: 5_000, bytesWritten: 2_000)])
        // Δread=4000 за 2с → 2000 B/s; Δwrite=0 → 0
        let reading = ResourceUsageCalculator.reading(from: prev, to: curr)
        XCTAssertEqual(reading.disks.count, 1)
        XCTAssertEqual(reading.disks[0].readBytesPerSec, 2_000, accuracy: 0.001)
        XCTAssertEqual(reading.disks[0].writeBytesPerSec, 0, accuracy: 0.001)
    }

    func test_disk_counter_reset_clamps_to_zero() {
        // Сброс счётчика (curr < prev) не должен давать отрицательный rate.
        let prev = snapshot(at: 0, cores: [],
                            disks: [DiskIOCounters(name: "disk0", bytesRead: 9_000, bytesWritten: 9_000)])
        let curr = snapshot(at: 1, cores: [],
                            disks: [DiskIOCounters(name: "disk0", bytesRead: 100, bytesWritten: 100)])
        let reading = ResourceUsageCalculator.reading(from: prev, to: curr)
        XCTAssertEqual(reading.disks[0].readBytesPerSec, 0, accuracy: 0.001)
        XCTAssertEqual(reading.disks[0].writeBytesPerSec, 0, accuracy: 0.001)
    }

    func test_new_disk_without_prev_is_skipped() {
        let prev = snapshot(at: 0, cores: [], disks: [])
        let curr = snapshot(at: 1, cores: [],
                            disks: [DiskIOCounters(name: "disk1", bytesRead: 500, bytesWritten: 500)])
        let reading = ResourceUsageCalculator.reading(from: prev, to: curr)
        XCTAssertTrue(reading.disks.isEmpty)
    }

    func test_zero_time_delta_skips_disk_rate() {
        let prev = snapshot(at: 5, cores: [],
                            disks: [DiskIOCounters(name: "disk0", bytesRead: 1, bytesWritten: 1)])
        let curr = snapshot(at: 5, cores: [],
                            disks: [DiskIOCounters(name: "disk0", bytesRead: 9, bytesWritten: 9)])
        let reading = ResourceUsageCalculator.reading(from: prev, to: curr)
        XCTAssertTrue(reading.disks.isEmpty)
    }
}
