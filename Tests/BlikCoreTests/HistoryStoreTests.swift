import XCTest
@testable import BlikCore

/// Тесты SQLite-хранилища истории метрик. Каждый тест — своя временная БД
/// (уникальный каталог в `temporaryDirectory`), удаляется в `tearDown`.
final class HistoryStoreTests: XCTestCase {

    private var dirs: [URL] = []

    override func tearDown() {
        for dir in dirs { try? FileManager.default.removeItem(at: dir) }
        dirs.removeAll()
        super.tearDown()
    }

    /// Минута-выровненная база (`ts % 60 == 0`) — удобно для роллап-бакетинга.
    private let base = Date(timeIntervalSince1970: 1_700_000_040)
    /// Окно выбора raw/rollup (6 ч) — как `Constants.historyRawQueryWindow`.
    private let rawWindow: TimeInterval = 21_600

    private func makePath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blik-history-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dirs.append(dir)
        return dir.appendingPathComponent("history.db").path
    }

    private func makeStore() throws -> HistoryStore {
        try HistoryStore(path: makePath())
    }

    private func at(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    // MARK: - Roundtrip

    func test_insert_query_roundtrip_returns_inserted_values() throws {
        let store = try makeStore()
        store.insert([
            MetricSample(metric: "temp.X", ts: at(0), value: 10),
            MetricSample(metric: "temp.X", ts: at(5), value: 20),
            MetricSample(metric: "temp.X", ts: at(10), value: 30),
        ])

        let req = HistoryQueryRequest(metrics: ["temp.X"], from: at(0), to: at(10),
                                      maxPointsPerSeries: 720)
        let resp = store.query(req, rawWindow: rawWindow)

        XCTAssertEqual(resp.series.count, 1)
        XCTAssertEqual(resp.bucketSeconds, HistoryStore.rawBucketSeconds)
        let pts = resp.series[0].points
        XCTAssertEqual(pts.count, 3, "три точки в отдельных 5-секундных бакетах")
        XCTAssertEqual(pts.map(\.avg), [10, 20, 30])
        XCTAssertEqual(pts.map(\.min), [10, 20, 30])
        XCTAssertEqual(pts.map(\.max), [10, 20, 30])
    }

    // MARK: - Интернирование имён

    func test_available_metrics_are_interned_and_sorted_without_duplicates() throws {
        let store = try makeStore()
        store.insert([
            MetricSample(metric: "b", ts: at(0), value: 1),
            MetricSample(metric: "a", ts: at(0), value: 1),
            MetricSample(metric: "a", ts: at(5), value: 2),
        ])
        XCTAssertEqual(store.availableMetrics(), ["a", "b"])
    }

    func test_available_metrics_empty_on_fresh_db() throws {
        let store = try makeStore()
        XCTAssertEqual(store.availableMetrics(), [])
    }

    // MARK: - Бакетинг

    func test_bucketing_respects_maxPoints_and_aligns_to_base_multiple() throws {
        let store = try makeStore()
        // 120 точек через 5 с → диапазон 600 с.
        var samples: [MetricSample] = []
        for i in 0..<120 {
            samples.append(MetricSample(metric: "m", ts: at(Double(i * 5)), value: Double(i)))
        }
        store.insert(samples)

        // maxPoints=10 → needed=ceil(600/10)=60 → bucket=60 (кратен базе 5).
        let req = HistoryQueryRequest(metrics: ["m"], from: at(0), to: at(600),
                                      maxPointsPerSeries: 10)
        let resp = store.query(req, rawWindow: rawWindow)

        XCTAssertEqual(resp.bucketSeconds, 60)
        let pts = resp.series[0].points
        XCTAssertLessThanOrEqual(pts.count, 11)
        for p in pts {
            XCTAssertEqual(Int(p.ts.timeIntervalSince1970) % 60, 0,
                           "границы бакетов выровнены на кратные 60")
        }
    }

    // MARK: - Граница raw/rollup на 6 ч

    func test_query_uses_raw_within_window_and_rollup_beyond() throws {
        let store = try makeStore()
        let t = at(0)
        store.insert([MetricSample(metric: "m", ts: t, value: 42)])

        // Диапазон ровно 6 ч → raw-таблица, точка есть. Бакет кратен базе raw (5 с),
        // конкретное значение зависит от maxPoints (тут 720 → 30 с).
        let inRange = HistoryQueryRequest(metrics: ["m"], from: t.addingTimeInterval(-rawWindow), to: t)
        let rawResp = store.query(inRange, rawWindow: rawWindow)
        XCTAssertEqual(rawResp.bucketSeconds % HistoryStore.rawBucketSeconds, 0)
        XCTAssertEqual(rawResp.series[0].points.count, 1)

        // Диапазон > 6 ч → rollup-таблица (пустая, роллап не запускали).
        let beyond = HistoryQueryRequest(metrics: ["m"], from: t.addingTimeInterval(-rawWindow - 10), to: t)
        let rollupResp = store.query(beyond, rawWindow: rawWindow)
        XCTAssertEqual(rollupResp.bucketSeconds, HistoryStore.rollupBucketSeconds)
        XCTAssertTrue(rollupResp.series[0].points.isEmpty,
                      "за границей окна берётся sample_1m, который ещё пуст")
    }

    // MARK: - Роллап: min/avg/max/cnt + идемпотентность watermark

    func test_rollup_computes_min_avg_max_and_is_watermark_idempotent() throws {
        let store = try makeStore()
        // Четыре сэмпла в одной минуте (base).
        store.insert([
            MetricSample(metric: "m", ts: at(0), value: 10),
            MetricSample(metric: "m", ts: at(5), value: 20),
            MetricSample(metric: "m", ts: at(10), value: 30),
            MetricSample(metric: "m", ts: at(15), value: 40),
        ])
        store.rollupCompletedMinutes(now: at(60))

        // Широкий диапазон → rollup-таблица.
        let req = HistoryQueryRequest(metrics: ["m"], from: at(-1),
                                      to: at(7 * 86_400), maxPointsPerSeries: 720)
        let resp = store.query(req, rawWindow: rawWindow)
        XCTAssertEqual(resp.series[0].points.count, 1)
        let p = resp.series[0].points[0]
        XCTAssertEqual(p.min, 10)
        XCTAssertEqual(p.avg, 25, accuracy: 0.0001, "взвешенное среднее (10+20+30+40)/4")
        XCTAssertEqual(p.max, 40)

        // Повторный роллап на том же `now` — no-op (watermark не двигается).
        store.rollupCompletedMinutes(now: at(60))
        let resp2 = store.query(req, rawWindow: rawWindow)
        XCTAssertEqual(resp2.series[0].points.count, 1, "нет дублирования роллап-строки")
        XCTAssertEqual(resp2.series[0].points[0].avg, 25, accuracy: 0.0001)
    }

    // MARK: - Prune + персистентность после reopen

    func test_prune_removes_old_raw_and_data_persists_after_reopen() throws {
        let path = makePath()
        var store: HistoryStore? = try HistoryStore(path: path)
        store!.insert([
            MetricSample(metric: "m", ts: at(0), value: 1),      // старый
            MetricSample(metric: "m", ts: at(3600), value: 2),   // свежий
        ])
        // Удаляем сырьё старше at(1); роллапы не трогаем.
        store!.prune(rawBefore: at(1), rollupBefore: at(-100_000))

        let req = HistoryQueryRequest(metrics: ["m"], from: at(-10), to: at(3600),
                                      maxPointsPerSeries: 720)
        let afterPrune = store!.query(req, rawWindow: rawWindow)
        XCTAssertEqual(afterPrune.series[0].points.map(\.avg), [2],
                       "старый сэмпл удалён, свежий остался")

        // Закрываем и переоткрываем ту же БД — данные переживают reopen.
        store!.checkpointTruncate()
        store = nil
        let reopened = try HistoryStore(path: path)
        let afterReopen = reopened.query(req, rawWindow: rawWindow)
        XCTAssertEqual(afterReopen.series[0].points.map(\.avg), [2])
    }

    // MARK: - Пустой диапазон / неизвестная метрика

    func test_unknown_metric_returns_empty_series() throws {
        let store = try makeStore()
        store.insert([MetricSample(metric: "known", ts: at(0), value: 1)])
        let req = HistoryQueryRequest(metrics: ["known", "missing"], from: at(-10), to: at(10))
        let resp = store.query(req, rawWindow: rawWindow)
        XCTAssertEqual(resp.series.map(\.metric), ["known", "missing"], "порядок серий = порядок запроса")
        XCTAssertEqual(resp.series[0].points.count, 1)
        XCTAssertTrue(resp.series[1].points.isEmpty)
    }

    func test_empty_time_range_returns_no_points() throws {
        let store = try makeStore()
        store.insert([MetricSample(metric: "m", ts: at(100), value: 5)])
        // Диапазон, не покрывающий сэмпл.
        let req = HistoryQueryRequest(metrics: ["m"], from: at(0), to: at(50))
        let resp = store.query(req, rawWindow: rawWindow)
        XCTAssertTrue(resp.series[0].points.isEmpty)
    }
}
