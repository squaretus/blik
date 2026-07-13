import Foundation
import SQLite3

/// SQLite-хранилище истории метрик.
///
/// **НЕ потокобезопасен** — вызывающий обязан сериализовать все обращения
/// (в daemon'е это db-очередь рекордера; тесты однопоточные).
///
/// Схема: `sample_raw` (сырьё, 5 с) → `sample_1m` (1-минутные роллапы) с
/// интернированием имён метрик в таблице `metric`. Ретенция: raw ~24 ч,
/// роллапы ~7 дней (см. `prune`).
public final class HistoryStore {

    public enum StoreError: Error, CustomStringConvertible {
        case open(message: String, code: Int32)
        case exec(message: String, code: Int32)

        public var description: String {
            switch self {
            case let .open(message, code): return "HistoryStore open failed (\(code)): \(message)"
            case let .exec(message, code): return "HistoryStore exec failed (\(code)): \(message)"
            }
        }
    }

    /// Базовый размер бакета сырых данных, сек.
    public static let rawBucketSeconds = 5
    /// Базовый размер бакета роллапов, сек.
    public static let rollupBucketSeconds = 60
    /// Версия схемы (для будущих миграций).
    public static let schemaVersion = 1

    private var db: OpaquePointer?
    /// Кэш интернированных id метрик (не сбрасывается — имена стабильны).
    private var metricIDCache: [String: Int64] = [:]

    // SQLite требует, чтобы связанный текст копировался (иначе dangling pointer).
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw StoreError.open(message: msg, code: rc)
        }
        db = handle
        try configureAndMigrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Схема

    private func configureAndMigrate() throws {
        // Прагмы СТРОГО до DDL — иначе auto_vacuum=INCREMENTAL не применится к
        // уже созданным таблицам.
        try exec("""
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        PRAGMA auto_vacuum=INCREMENTAL;
        CREATE TABLE IF NOT EXISTS metric (id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL);
        CREATE TABLE IF NOT EXISTS sample_raw (
          metric_id INTEGER NOT NULL, ts INTEGER NOT NULL, value REAL NOT NULL,
          PRIMARY KEY (metric_id, ts)) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS sample_1m (
          metric_id INTEGER NOT NULL, ts INTEGER NOT NULL,
          vmin REAL NOT NULL, vavg REAL NOT NULL, vmax REAL NOT NULL, cnt INTEGER NOT NULL,
          PRIMARY KEY (metric_id, ts)) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """)
        if metaInt("schema_version") == nil {
            setMetaInt("schema_version", Int64(Self.schemaVersion))
        }
    }

    // MARK: - Запись

    /// Пакетная вставка сэмплов в `sample_raw` (одна транзакция).
    /// Дубли по (metric, ts) перезаписываются.
    public func insert(_ samples: [MetricSample]) {
        guard !samples.isEmpty else { return }
        do {
            try exec("BEGIN IMMEDIATE")
        } catch {
            log(error); return
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "INSERT OR REPLACE INTO sample_raw(metric_id,ts,value) VALUES(?,?,?)",
            -1, &stmt, nil) == SQLITE_OK else {
            try? exec("ROLLBACK")
            log(lastMessage()); return
        }
        for s in samples {
            guard let mid = metricID(for: s.metric) else { continue }
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_int64(stmt, 1, mid)
            sqlite3_bind_int64(stmt, 2, seconds(s.ts))
            sqlite3_bind_double(stmt, 3, s.value)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        try? exec("COMMIT")
    }

    // MARK: - Роллап

    /// Сворачивает завершённые минуты `sample_raw` в `sample_1m` по watermark'у.
    /// Идемпотентно: повторный вызов с тем же `now` — no-op (watermark не двигается).
    public func rollupCompletedMinutes(now: Date) {
        let watermark = metaInt("rollup_watermark") ?? 0
        let currentMinuteStart = (seconds(now) / 60) * 60
        guard currentMinuteStart > watermark else { return }

        var stmt: OpaquePointer?
        let sql = """
        INSERT OR REPLACE INTO sample_1m(metric_id,ts,vmin,vavg,vmax,cnt)
        SELECT metric_id,(ts/60)*60,MIN(value),AVG(value),MAX(value),COUNT(*)
        FROM sample_raw WHERE ts>=? AND ts<? GROUP BY metric_id,(ts/60)*60
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log(lastMessage()); return
        }
        sqlite3_bind_int64(stmt, 1, watermark)
        sqlite3_bind_int64(stmt, 2, currentMinuteStart)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        setMetaInt("rollup_watermark", currentMinuteStart)
    }

    // MARK: - Ретенция

    /// Удаляет сырьё старше `rawBefore` и роллапы старше `rollupBefore`,
    /// затем возвращает освобождённые страницы ОС (`incremental_vacuum`).
    public func prune(rawBefore: Date, rollupBefore: Date) {
        deleteBefore(table: "sample_raw", ts: seconds(rawBefore))
        deleteBefore(table: "sample_1m", ts: seconds(rollupBefore))
        try? exec("PRAGMA incremental_vacuum;")
    }

    private func deleteBefore(table: String, ts: Int64) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM \(table) WHERE ts<?", -1, &stmt, nil) == SQLITE_OK else {
            log(lastMessage()); return
        }
        sqlite3_bind_int64(stmt, 1, ts)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - Чтение

    /// Агрегированный запрос истории. `rawWindow` — граница выбора таблицы:
    /// диапазон ≤ `rawWindow` идёт по `sample_raw`, иначе по `sample_1m`.
    public func query(_ request: HistoryQueryRequest, rawWindow: TimeInterval) -> HistoryQueryResponse {
        // Дедуп + кламп числа метрик.
        var seen = Set<String>()
        var metrics: [String] = []
        for m in request.metrics where !seen.contains(m) {
            seen.insert(m)
            metrics.append(m)
            if metrics.count >= HistoryQueryRequest.maxMetrics { break }
        }

        let fromSec = seconds(request.from)
        let toSec = seconds(request.to)
        let range = max(0, toSec - fromSec)

        let useRaw = Double(range) <= rawWindow
        let base = useRaw ? Self.rawBucketSeconds : Self.rollupBucketSeconds
        let maxPoints = max(1, min(HistoryQueryRequest.maxPointsHardCap, request.maxPointsPerSeries))

        var bucket = base
        if range > 0 {
            let needed = Int((Double(range) / Double(maxPoints)).rounded(.up))
            bucket = Swift.max(base, needed)
        }
        // Кратность базовому бакету.
        if bucket % base != 0 { bucket = ((bucket / base) + 1) * base }

        let table = useRaw ? "sample_raw" : "sample_1m"
        var series: [HistorySeries] = []
        for metric in metrics {
            let points: [HistoryPoint]
            if let mid = metricIDIfExists(metric) {
                points = queryPoints(table: table, useRaw: useRaw, metricID: mid,
                                     from: fromSec, to: toSec, bucket: Int64(bucket))
            } else {
                points = []
            }
            series.append(HistorySeries(metric: metric, points: points))
        }
        return HistoryQueryResponse(series: series, bucketSeconds: bucket)
    }

    private func queryPoints(table: String, useRaw: Bool, metricID: Int64,
                             from: Int64, to: Int64, bucket: Int64) -> [HistoryPoint] {
        let sql: String
        if useRaw {
            sql = """
            SELECT (ts/\(bucket))*\(bucket) AS b, MIN(value), AVG(value), MAX(value)
            FROM \(table) WHERE metric_id=? AND ts>=? AND ts<=? GROUP BY b ORDER BY b
            """
        } else {
            // Роллапы комбинируем корректно: min по vmin, max по vmax,
            // avg — взвешенное по cnt.
            sql = """
            SELECT (ts/\(bucket))*\(bucket) AS b, MIN(vmin),
                   SUM(vavg*cnt)/SUM(cnt), MAX(vmax)
            FROM \(table) WHERE metric_id=? AND ts>=? AND ts<=? GROUP BY b ORDER BY b
            """
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log(lastMessage()); return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, metricID)
        sqlite3_bind_int64(stmt, 2, from)
        sqlite3_bind_int64(stmt, 3, to)

        var points: [HistoryPoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let b = sqlite3_column_int64(stmt, 0)
            let vmin = sqlite3_column_double(stmt, 1)
            let vavg = sqlite3_column_double(stmt, 2)
            let vmax = sqlite3_column_double(stmt, 3)
            points.append(HistoryPoint(ts: Date(timeIntervalSince1970: Double(b)),
                                       min: vmin, avg: vavg, max: vmax))
        }
        return points
    }

    /// Все известные имена метрик (для редактора графиков / диагностики).
    public func availableMetrics() -> [String] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM metric ORDER BY name", -1, &stmt, nil) == SQLITE_OK else {
            log(lastMessage()); return []
        }
        defer { sqlite3_finalize(stmt) }
        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) {
                names.append(String(cString: c))
            }
        }
        return names
    }

    /// Ежедневный чекпоинт WAL с усечением — не даёт `-wal` расти безгранично.
    public func checkpointTruncate() {
        try? exec("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    // MARK: - Интернирование метрик

    private func metricID(for name: String) -> Int64? {
        if let cached = metricIDCache[name] { return cached }
        if let id = metricIDIfExists(name) {
            metricIDCache[name] = id
            return id
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO metric(name) VALUES(?)", -1, &stmt, nil) == SQLITE_OK else {
            log(lastMessage()); return nil
        }
        sqlite3_bind_text(stmt, 1, name, -1, Self.transient)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        if let id = metricIDIfExists(name) {
            metricIDCache[name] = id
            return id
        }
        return nil
    }

    private func metricIDIfExists(_ name: String) -> Int64? {
        if let cached = metricIDCache[name] { return cached }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id FROM metric WHERE name=?", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, Self.transient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let id = sqlite3_column_int64(stmt, 0)
        metricIDCache[name] = id
        return id
    }

    // MARK: - meta

    private func metaInt(_ key: String) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key=?", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, Self.transient)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
        return Int64(String(cString: c))
    }

    private func setMetaInt(_ key: String, _ value: Int64) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)", -1, &stmt, nil) == SQLITE_OK else {
            log(lastMessage()); return
        }
        sqlite3_bind_text(stmt, 1, key, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, String(value), -1, Self.transient)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - Низкоуровневое

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw StoreError.exec(message: msg, code: rc)
        }
    }

    private func seconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded())
    }

    private func lastMessage() -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
    }

    private func log(_ error: Error) { log("\(error)") }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[HistoryStore] \(message)\n".utf8))
    }
}
