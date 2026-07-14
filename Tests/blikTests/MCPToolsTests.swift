import XCTest
import BlikCore
import MCP
@testable import blik

/// Стаб источника: фиксирует вызовы, отдаёт фикстуры.
private final class StubSource: MCPMetricsSource {
    var payload: CurrentMetricsPayload?
    var metrics: [String]? = ["cpu.pcore.avg"]
    var historyResponse: HistoryQueryResponse?
    var presetError: String?

    private(set) var requestedRange: (from: Date, to: Date)?
    private(set) var requestedMetric: String?
    private(set) var presetCalls: [Int] = []

    func currentMetrics() -> CurrentMetricsPayload? { payload }
    func listMetrics() -> [String]? { metrics }
    func queryHistory(metric: String, from: Date, to: Date) -> HistoryQueryResponse? {
        requestedMetric = metric
        requestedRange = (from, to)
        return historyResponse
    }
    func setFanPreset(percentage: Int) -> String? {
        presetCalls.append(percentage)
        return presetError
    }
}

final class MCPToolsTests: XCTestCase {

    private func text(_ result: CallTool.Result) -> String {
        guard case .text(let s, _, _) = result.content.first else { return "" }
        return s
    }

    // MARK: - Список инструментов

    func testToolListNamesAndCount() {
        XCTAssertEqual(BlikMCPTools.toolList.map(\.name),
                       ["get_current_metrics", "list_metrics",
                        "query_metric_history", "set_fan_preset"])
    }

    // MARK: - Диспетчеризация

    func testUnknownToolIsError() {
        let result = BlikMCPTools.handle(name: "nope", arguments: nil, source: StubSource())
        XCTAssertEqual(result.isError, true)
    }

    // MARK: - get_current_metrics

    func testGetCurrentMetricsReturnsJSON() {
        let source = StubSource()
        source.payload = CurrentMetricsPayload.build(
            sensors: [SensorInfo(key: "Tp01", name: "P1", group: .cpuCores, temperature: 48)],
            fans: [FanInfo(id: 0, actualSpeed: 1200, minimumSpeed: 1000,
                           maximumSpeed: 5000, targetSpeed: 0, isForced: false)],
            reading: nil)
        let result = BlikMCPTools.handle(name: "get_current_metrics",
                                         arguments: nil, source: source)
        XCTAssertNotEqual(result.isError, true)
        XCTAssertTrue(text(result).contains("\"temperatures\""))
        XCTAssertTrue(text(result).contains("\"pCoreAvgCelsius\" : 48"))
    }

    func testGetCurrentMetricsSourceFailureIsError() {
        let result = BlikMCPTools.handle(name: "get_current_metrics",
                                         arguments: nil, source: StubSource())
        XCTAssertEqual(result.isError, true)
    }

    // MARK: - query_metric_history

    func testQueryHistoryRequiresMetricKey() {
        let result = BlikMCPTools.handle(name: "query_metric_history",
                                         arguments: [:], source: StubSource())
        XCTAssertEqual(result.isError, true)
    }

    func testQueryHistoryClampsMinutesAndPassesMetric() {
        let source = StubSource()
        source.historyResponse = HistoryQueryResponse(series: [], bucketSeconds: 60)
        _ = BlikMCPTools.handle(
            name: "query_metric_history",
            arguments: ["metric_key": .string("gpu.avg"), "minutes": .int(999_999)],
            source: source)
        XCTAssertEqual(source.requestedMetric, "gpu.avg")
        let window = source.requestedRange!.to.timeIntervalSince(source.requestedRange!.from)
        XCTAssertEqual(window, 10_080 * 60, accuracy: 5)   // кламп 7 дней
    }

    // MARK: - set_fan_preset

    func testSetFanPresetRejectsInvalidPercent() {
        let source = StubSource()
        let result = BlikMCPTools.handle(name: "set_fan_preset",
                                         arguments: ["percent": .int(30)], source: source)
        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(source.presetCalls.isEmpty)
    }

    func testSetFanPresetCallsSourceOnValidPercent() {
        let source = StubSource()
        let result = BlikMCPTools.handle(name: "set_fan_preset",
                                         arguments: ["percent": .int(50)], source: source)
        XCTAssertNotEqual(result.isError, true)
        XCTAssertEqual(source.presetCalls, [50])
    }

    func testSetFanPresetPropagatesSourceError() {
        let source = StubSource()
        source.presetError = "SMC write failed"
        let result = BlikMCPTools.handle(name: "set_fan_preset",
                                         arguments: ["percent": .int(0)], source: source)
        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(text(result).contains("SMC write failed"))
    }

    // MARK: - CurrentMetricsPayload.build

    func testBuildComputesAveragesAndFanMode() {
        let payload = CurrentMetricsPayload.build(
            sensors: [
                SensorInfo(key: "Tp01", name: "P1", group: .cpuCores, temperature: 40),
                SensorInfo(key: "Tp02", name: "P2", group: .cpuCores, temperature: 56),
            ],
            fans: [FanInfo(id: 0, actualSpeed: 3000, minimumSpeed: 1000,
                           maximumSpeed: 5000, targetSpeed: 3000, isForced: true)],
            reading: nil)
        XCTAssertEqual(payload.temperatures.pCoreAvgCelsius, 48)
        XCTAssertNil(payload.temperatures.gpuAvgCelsius)
        XCTAssertEqual(payload.fans.first?.mode, "manual")
        XCTAssertNil(payload.cpuUsage)   // reading == nil → производных нет
    }
}
