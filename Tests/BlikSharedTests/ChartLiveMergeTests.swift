import XCTest
import BlikCore
@testable import BlikShared
@testable import BlikXPC

/// Тесты backfill'а live-окна daemon-историей.
///
/// Регресс v1.2.0: окна ≤ 15 мин рисовались только из in-memory буфера — после
/// открытия страницы график был пуст (пара минут данных + стале-фрагменты от
/// прошлых посещений), ось схлопывалась. История подтягивалась только для окон
/// шире буфера (30 мин+), поэтому «с 30 нормально, 5/15 сломаны».
@MainActor
final class ChartLiveMergeTests: XCTestCase {

    // MARK: - liveMergeSplit (чистая функция мержа)

    private func hp(_ t: TimeInterval, _ v: Double = 1) -> HistoryPoint {
        HistoryPoint(ts: Date(timeIntervalSinceReferenceDate: t), min: v, avg: v, max: v)
    }
    private func bp(_ t: TimeInterval, _ v: Double = 2) -> LiveMetricBuffer.Point {
        LiveMetricBuffer.Point(ts: Date(timeIntervalSinceReferenceDate: t), value: v)
    }

    func test_merge_empty_buffer_returns_history_only() {
        let history = [hp(0), hp(5), hp(10)]
        let (h, tail) = ChartsVM.liveMergeSplit(history: history, bufferSegments: [])
        XCTAssertEqual(h, history)
        XCTAssertTrue(tail.isEmpty)
    }

    func test_merge_cuts_history_at_tail_start() {
        let history = [hp(0), hp(5), hp(10), hp(15)]
        let tail = [bp(10), bp(11), bp(12)]
        let (h, t) = ChartsVM.liveMergeSplit(history: history, bufferSegments: [tail])
        XCTAssertEqual(h, [hp(0), hp(5)], "история обрезается до начала живого хвоста")
        XCTAssertEqual(t, tail)
    }

    func test_merge_drops_stale_buffer_fragments_keeps_last_segment() {
        // Буфер: стале-фрагмент от прошлого посещения страницы + свежий хвост.
        let stale = [bp(0), bp(1), bp(2)]
        let fresh = [bp(100), bp(101)]
        let history = [hp(0), hp(5), hp(50), hp(99), hp(101)]
        let (h, t) = ChartsVM.liveMergeSplit(history: history, bufferSegments: [stale, fresh])
        XCTAssertEqual(t, fresh, "живой хвост — только последний непрерывный сегмент буфера")
        XCTAssertEqual(h, [hp(0), hp(5), hp(50), hp(99)],
                       "стале-регион покрывается историей, а не обрывками буфера")
    }

    // MARK: - Подтяжка истории для узких окон (VM)

    /// Мок клиента с канированным ответом истории.
    private final class HistoryStubClient: BlikXPCClient {
        private let mock = MockHelper()
        let response: HistoryQueryResponse
        init(response: HistoryQueryResponse) {
            self.response = response
            super.init()
        }
        override func helper() -> BlikHelperProtocol? { mock }
        override var isConnected: Bool { true }
        override func queryHistorySync(_ request: HistoryQueryRequest) -> HistoryQueryResponse? {
            response
        }
    }

    func test_live_history_backfills_windows_narrower_than_buffer() async throws {
        let response = HistoryQueryResponse(
            series: [HistorySeries(metric: "cpu.load", points: [hp(0), hp(5)])],
            bucketSeconds: 5,
        )
        let runtime = BlikRuntime(xpcClient: HistoryStubClient(response: response),
                                  helperSupportsHistory: true)
        let vm = ChartsVM(runtime: runtime, settings: AppSettingsVM())
        vm.metricsToQuery = ["cpu.load"]
        vm.setLiveWindow(300) // 5 мин — уже буфера (900 с)
        vm.setVisible(true)
        defer { vm.setVisible(false) }

        // Подтяжка уходит на detached-задачу — ждём публикации на main.
        for _ in 0..<100 {
            if !vm.liveHistory.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(vm.liveHistory["cpu.load"], [hp(0), hp(5)],
                       "узкое live-окно должно подтягивать daemon-историю, а не рисоваться одним буфером")
        XCTAssertEqual(vm.rangeBucketSeconds, 5)
    }
}
