import XCTest
import BlikCore
@testable import blik

final class StatuslineRendererTests: XCTestCase {

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

    private static let fullSet = [
        StatuslineMetric(label: "CPU", valueText: "43°", level: .ok),
        StatuslineMetric(label: "E-CORES", valueText: "46°", level: .ok),
        StatuslineMetric(label: "GPU", valueText: "45°", level: .ok),
        StatuslineMetric(label: "RAM", valueText: "11,2G", level: .warn),
        StatuslineMetric(label: "VRAM", valueText: "1,2G", level: .ok),
    ]

    func testRenderSingleColumnDrawsFramedTable() {
        let metrics = [StatuslineMetric(label: "CPU", valueText: "48°", level: .ok)]
        let plain = DashboardView.stripANSI(StatuslineRenderer.render(metrics))
        XCTAssertEqual(plain, """
            ┌─────┐
            │ CPU │
            ├─────┤
            │ 48° │
            └─────┘
            """)
    }

    func testRenderFullSetDrawsTable() {
        let plain = DashboardView.stripANSI(StatuslineRenderer.render(Self.fullSet))
        XCTAssertEqual(plain, """
            ┌─────┬─────────┬─────┬───────┬──────┐
            │ CPU │ E-CORES │ GPU │  RAM  │ VRAM │
            ├─────┼─────────┼─────┼───────┼──────┤
            │ 43° │   46°   │ 45° │ 11,2G │ 1,2G │
            └─────┴─────────┴─────┴───────┴──────┘
            """)
    }

    func testRenderCentersOddRemainderToTheRight() {
        // Ширина колонки = max(2, 3) + 2 = 5; "AB" короче на 3 → 1 пробел слева, 2 справа.
        let metrics = [StatuslineMetric(label: "AB", valueText: "XYZ", level: .ok)]
        let lines = DashboardView.stripANSI(StatuslineRenderer.render(metrics))
            .components(separatedBy: "\n")
        XCTAssertEqual(lines[1], "│ AB  │")
        XCTAssertEqual(lines[3], "│ XYZ │")
    }

    func testRenderKeepsAllLinesEqualWidth() {
        let lines = DashboardView.stripANSI(StatuslineRenderer.render(Self.fullSet))
            .components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(Set(lines.map(\.count)).count, 1, "строки таблицы разъехались: \(lines)")
    }

    func testRenderDegradesToAvailableColumns() {
        let metrics = [
            StatuslineMetric(label: "CPU", valueText: "48°", level: .ok),
            StatuslineMetric(label: "RAM", valueText: "16,2G", level: .warn),
        ]
        let plain = DashboardView.stripANSI(StatuslineRenderer.render(metrics))
        XCTAssertEqual(plain, """
            ┌─────┬───────┐
            │ CPU │  RAM  │
            ├─────┼───────┤
            │ 48° │ 16,2G │
            └─────┴───────┘
            """)
    }

    func testRenderEmptyMetricsIsEmptyString() {
        XCTAssertEqual(StatuslineRenderer.render([]), "")
    }

    func testRenderUsesTruecolorNotPaletteCodes() {
        // Базовые ANSI-16 коды ([32m и т.п.) перекрашиваются палитрой темы
        // терминала — все цвета идут truecolor'ом (38;2;R;G;B).
        let metrics = [
            StatuslineMetric(label: "CPU", valueText: "48°", level: .ok),
            StatuslineMetric(label: "E-CORES", valueText: "75°", level: .warn),
            StatuslineMetric(label: "GPU", valueText: "95°", level: .crit),
        ]
        let out = StatuslineRenderer.render(metrics)
        XCTAssertTrue(out.contains("\u{1B}[38;2;48;209;88m\u{1B}[1m 48° "))    // ok → green
        XCTAssertTrue(out.contains("\u{1B}[38;2;255;214;10m\u{1B}[1m   75°   ")) // warn → yellow
        XCTAssertTrue(out.contains("\u{1B}[38;2;255;69;58m\u{1B}[1m 95° "))    // crit → red
        XCTAssertTrue(out.contains("\u{1B}[38;2;142;142;147m│"))                // рамка — серая
        XCTAssertTrue(out.contains("\u{1B}[38;2;142;142;147m CPU "))            // заголовок — серый
        XCTAssertFalse(out.contains("\u{1B}[32m"))
        XCTAssertFalse(out.contains("\u{1B}[90m"))
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

        let metrics = StatuslineRenderer.buildMetrics(
            sensors: sensors, snapshot: snapshot(gpu: gpu))

        XCTAssertEqual(metrics.map(\.label), ["CPU", "E-CORES", "GPU", "RAM", "VRAM"])
        XCTAssertEqual(metrics[0].valueText, "48°")   // (40+56)/2
        XCTAssertEqual(metrics[3].valueText, "16,2G")
        XCTAssertEqual(metrics[4].valueText, "1,8G")
    }

    func testBuildMetricsSkipsMissingBlocks() {
        // Нет GPU-сенсоров, нет GPUStats, нет snapshot → только CPU/E
        let sensors = [sensor("Tp01", .cpuCores, 40), sensor("Te01", .npuECores, 52)]
        let metrics = StatuslineRenderer.buildMetrics(sensors: sensors, snapshot: nil)
        XCTAssertEqual(metrics.map(\.label), ["CPU", "E-CORES"])
    }

    func testBuildMetricsEmptyEverythingIsEmpty() {
        XCTAssertTrue(StatuslineRenderer.buildMetrics(sensors: [], snapshot: nil).isEmpty)
    }
}
