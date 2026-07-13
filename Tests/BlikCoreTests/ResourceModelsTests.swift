import XCTest
@testable import BlikCore

final class ResourceModelsTests: XCTestCase {

    private func core(_ index: Int, _ type: CPUCoreType, busy: Double) -> CPUCoreUsage {
        // busyPercent = user + system; делим busy пополам, idle = 100 - busy.
        CPUCoreUsage(index: index, type: type,
                     userPercent: busy / 2, systemPercent: busy / 2,
                     idlePercent: 100 - busy)
    }

    private func reading(cpuCores: [CPUCoreUsage] = [], disks: [DiskIORate] = []) -> ResourceReading {
        ResourceReading(
            timestamp: Date(timeIntervalSince1970: 0),
            cpuCores: cpuCores,
            cpuOverallBusyPercent: 0,
            memory: MemoryStats(used: 0, wired: 0, compressed: 0, cached: 0,
                                total: 0, pressurePercent: 0),
            gpu: nil,
            disks: disks
        )
    }

    func test_average_performance_busy_averages_only_P_cores() {
        let r = reading(cpuCores: [
            core(0, .performance, busy: 40),
            core(1, .performance, busy: 80),
            core(2, .efficiency, busy: 10),
        ])
        XCTAssertEqual(r.averagePerformanceBusy, 60, accuracy: 0.001)
    }

    func test_average_efficiency_busy_averages_only_E_cores() {
        let r = reading(cpuCores: [
            core(0, .performance, busy: 90),
            core(1, .efficiency, busy: 20),
            core(2, .efficiency, busy: 30),
        ])
        XCTAssertEqual(r.averageEfficiencyBusy, 25, accuracy: 0.001)
    }

    func test_average_busy_zero_when_no_cores_of_type() {
        let r = reading(cpuCores: [core(0, .performance, busy: 50)])
        XCTAssertEqual(r.averageEfficiencyBusy, 0)
    }

    func test_average_busy_zero_when_no_cores_at_all() {
        let r = reading()
        XCTAssertEqual(r.averagePerformanceBusy, 0)
        XCTAssertEqual(r.averageEfficiencyBusy, 0)
    }

    func test_total_disk_bytes_sums_read_and_write_across_disks() {
        let r = reading(disks: [
            DiskIORate(name: "disk0", readBytesPerSec: 1_000, writeBytesPerSec: 2_000),
            DiskIORate(name: "disk1", readBytesPerSec: 500, writeBytesPerSec: 0),
        ])
        XCTAssertEqual(r.totalDiskBytesPerSec, 3_500, accuracy: 0.001)
    }

    func test_total_disk_bytes_zero_when_no_disks() {
        XCTAssertEqual(reading().totalDiskBytesPerSec, 0)
    }
}
