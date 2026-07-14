import XCTest
import BlikCore
@testable import blik

final class StatuslineRendererTests: XCTestCase {

    // MARK: - sparkline

    func testSparklineEmpty() {
        XCTAssertEqual(StatuslineRenderer.sparkline([]), "")
    }

    func testSparklineSinglePointIsMidBlock() {
        XCTAssertEqual(StatuslineRenderer.sparkline([5]), "▄")
    }

    func testSparklineFlatSeriesIsMidBlocks() {
        XCTAssertEqual(StatuslineRenderer.sparkline([3, 3, 3]), "▄▄▄")
    }

    func testSparklineAscendingUsesFullRange() {
        let values = (0...7).map(Double.init)
        XCTAssertEqual(StatuslineRenderer.sparkline(values), "▁▂▃▄▅▆▇█")
    }

    // MARK: - Уровни

    func testTempLevelThresholds() {
        XCTAssertEqual(StatuslineRenderer.tempLevel(69.9), .ok)
        XCTAssertEqual(StatuslineRenderer.tempLevel(70), .warn)
        XCTAssertEqual(StatuslineRenderer.tempLevel(89.9), .warn)
        XCTAssertEqual(StatuslineRenderer.tempLevel(90), .crit)
    }

    func testFillLevelThresholds() {
        XCTAssertEqual(StatuslineRenderer.fillLevel(used: 50, total: 100), .ok)
        XCTAssertEqual(StatuslineRenderer.fillLevel(used: 70, total: 100), .warn)
        XCTAssertEqual(StatuslineRenderer.fillLevel(used: 95, total: 100), .crit)
        XCTAssertEqual(StatuslineRenderer.fillLevel(used: 1, total: 0), .ok)
    }

    // MARK: - Форматирование

    func testGigabytesUsesCommaAndSuffix() {
        XCTAssertEqual(StatuslineRenderer.gigabytes(17_395_522_355), "16,2G")
        XCTAssertEqual(StatuslineRenderer.gigabytes(1_890_000_000), "1,8G")
    }

    // MARK: - render (проверяем через stripANSI, как существующие тесты)

    func testRenderUsesTruecolorNotPaletteCodes() {
        // Базовые ANSI-16 коды ([32m и т.п.) перекрашиваются палитрой темы
        // терминала — все цвета идут truecolor'ом (38;2;R;G;B).
        // Значения — белые (цвет уровня несёт спарклайн).
        let metrics = [
            StatuslineMetric(label: "CPU", valueText: "48°", level: .ok, spark: [1, 2]),
            StatuslineMetric(label: "E", valueText: "75°", level: .warn, spark: [3, 4]),
            StatuslineMetric(label: "GPU", valueText: "95°", level: .crit, spark: [5, 6]),
        ]
        let out = StatuslineRenderer.render(metrics)
        XCTAssertTrue(out.contains("\u{1B}[38;2;255;255;255m\u{1B}[1m48°"))  // значение — белое
        XCTAssertTrue(out.contains("\u{1B}[38;2;48;209;88m"))    // ok → systemGreen (спарклайн)
        XCTAssertTrue(out.contains("\u{1B}[38;2;255;214;10m"))   // warn → systemYellow
        XCTAssertTrue(out.contains("\u{1B}[38;2;255;69;58m"))    // crit → systemRed
        XCTAssertFalse(out.contains("\u{1B}[32m"))
        XCTAssertFalse(out.contains("\u{1B}[90m"))
    }

    func testRenderJoinsBlocksAndSkipsEmptySpark() {
        let metrics = [
            StatuslineMetric(label: "CPU", valueText: "48°", level: .ok, spark: [0, 7]),
            StatuslineMetric(label: "RAM", valueText: "16,2G", level: .warn, spark: []),
        ]
        let plain = DashboardView.stripANSI(StatuslineRenderer.render(metrics))
        XCTAssertEqual(plain, "CPU 48° ▁█  RAM 16,2G")
    }

    // MARK: - buildMetrics

    private func sensor(_ key: String, _ group: SensorGroup, _ t: Double) -> SensorInfo {
        SensorInfo(key: key, name: key, group: group, temperature: t)
    }

    private func snapshot(gpu: GPUStats?) -> ResourceSnapshot {
        ResourceSnapshot(
            timestamp: Date(),
            cpuCores: [],
            memory: MemoryStats(used: 17_395_522_355, wired: 0, compressed: 0,
                                cached: 0, total: 34_359_738_368, pressurePercent: 30),
            gpu: gpu,
            disks: [])
    }

    func testBuildMetricsFullSet() {
        let sensors = [
            sensor("Tp01", .cpuCores, 40), sensor("Tp02", .cpuCores, 56),
            sensor("Te01", .npuECores, 52),
            sensor("Tg01", .gpuCores, 51),
        ]
        let gpu = GPUStats(utilizationPercent: 10, memoryUsed: 1_890_000_000,
                           memoryTotal: 34_359_738_368)
        let history = HistoryQueryResponse(series: [
            HistorySeries(metric: "cpu.pcore.avg",
                          points: [HistoryPoint(ts: Date(), min: 40, avg: 45, max: 50)])
        ], bucketSeconds: 60)

        let metrics = StatuslineRenderer.buildMetrics(
            sensors: sensors, snapshot: snapshot(gpu: gpu), history: history)

        XCTAssertEqual(metrics.map(\.label), ["CPU", "E", "GPU", "RAM", "VRAM"])
        XCTAssertEqual(metrics[0].valueText, "48°")   // (40+56)/2
        XCTAssertEqual(metrics[0].spark, [45])         // avg-точки из истории
        XCTAssertEqual(metrics[3].valueText, "16,2G")
        XCTAssertEqual(metrics[4].valueText, "1,8G")
        XCTAssertEqual(metrics[1].spark, [])           // истории по ключу нет
    }

    func testBuildMetricsSkipsMissingBlocks() {
        // Нет GPU-сенсоров, нет GPUStats, нет snapshot → только CPU/E
        let sensors = [sensor("Tp01", .cpuCores, 40), sensor("Te01", .npuECores, 52)]
        let metrics = StatuslineRenderer.buildMetrics(
            sensors: sensors, snapshot: nil, history: nil)
        XCTAssertEqual(metrics.map(\.label), ["CPU", "E"])
    }

    func testBuildMetricsEmptyEverythingIsEmpty() {
        XCTAssertTrue(StatuslineRenderer.buildMetrics(
            sensors: [], snapshot: nil, history: nil).isEmpty)
    }
}
