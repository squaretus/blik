import Foundation
import BlikCore

/// Пишет локальную историю метрик в daemon'е.
///
/// **Две serial-очереди** — чтобы запросы графиков (`query`/`availableMetrics`)
/// НИКОГДА не ждали SMC-операций:
/// - `sampling` — только тики семплинга (5 с). Внутри тика читает fans/sensors
///   через инжектированный closure (он делает `smcQueue.sync` — SMC-дисциплина
///   сохраняется), затем собственный `ResourceReader().read()` (root не нужен),
///   считает дельты и складывает результат `async` на db-очередь.
/// - `db` — ВСЕ обращения к `HistoryStore` (insert/rollup/prune/query/…).
///   db-очередь никогда не блокируется на SMC.
///
/// Skip-if-busy: если предыдущий тик ещё ждёт `smcQueue` (ручное управление
/// вентиляторами: unlock Ftst ~5 с + ретраи), новый тик пропускается, а не копится.
final class HistoryRecorder {

    /// Читает fans+sensors на SMC-очереди. Возвращает nil при ошибке чтения.
    typealias FanSensorReader = () -> (fans: [FanInfo], sensors: [SensorInfo])?

    private let store: HistoryStore
    private let readFansSensors: FanSensorReader
    private let resourceReader = ResourceReader()

    /// Только тики семплинга + управление таймером/флагами состояния.
    private let samplingQueue = DispatchQueue(label: "com.blik.helper.history.sampling")
    /// ВСЕ обращения к `HistoryStore`. Никогда не ждёт SMC.
    private let dbQueue = DispatchQueue(label: "com.blik.helper.history.db")

    // MARK: - Состояние (доступ только на samplingQueue)

    private var timer: DispatchSourceTimer?
    private var isActive = false
    /// Тик держит этот флаг, пока ждёт SMC-чтение; следующий тик пропускается.
    private var tickInProgress = false
    /// Предыдущий снимок ресурсов для расчёта дельт. Сбрасывается при разрыве
    /// (сон/пробуждение) — см. `cadence * 3`.
    private var prevSnapshot: ResourceSnapshot?

    // MARK: - Периодическое обслуживание (доступ только на dbQueue)

    private var lastRollup: Date = .distantPast
    private var lastPrune: Date = .distantPast
    private var lastCheckpoint: Date = .distantPast

    private let cadence = Constants.historyRawCadenceSeconds

    init(store: HistoryStore, readFansSensors: @escaping FanSensorReader) {
        self.store = store
        self.readFansSensors = readFansSensors
    }

    // MARK: - Управление жизненным циклом

    /// Идемпотентный старт/стоп таймера семплинга. Вызывается при подключении
    /// первого / отключении последнего XPC-клиента.
    func setActive(_ active: Bool) {
        samplingQueue.async { [weak self] in
            guard let self else { return }
            guard self.isActive != active else { return }
            self.isActive = active
            if active {
                self.startTimerLocked()
                HelperLogger.log("history recorder: active")
            } else {
                self.stopTimerLocked()
                self.prevSnapshot = nil
                HelperLogger.log("history recorder: idle")
            }
        }
    }

    // Вызывается на samplingQueue.
    private func startTimerLocked() {
        let t = DispatchSource.makeTimerSource(queue: samplingQueue)
        t.schedule(deadline: .now(), repeating: cadence)
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        t.resume()
        timer = t
    }

    // Вызывается на samplingQueue.
    private func stopTimerLocked() {
        timer?.cancel()
        timer = nil
        tickInProgress = false
    }

    // MARK: - Тик семплинга (samplingQueue)

    private func tick() {
        // Skip-if-busy: предыдущий тик всё ещё ждёт SMC — пропускаем.
        guard !tickInProgress else {
            HelperLogger.log("history tick skipped (smc busy)")
            return
        }
        tickInProgress = true
        defer { tickInProgress = false }

        // Чтение fans/sensors на SMC-очереди (может блокировать ~5 с при ручном
        // управлении вентиляторами). Держит tickInProgress → следующий тик skip.
        guard let (fans, sensors) = readFansSensors() else { return }

        let snapshot = resourceReader.read()
        let now = snapshot.timestamp

        // Разрыв > 3× cadence (сон/пробуждение) → нельзя считать дельту.
        if let prev = prevSnapshot,
           now.timeIntervalSince(prev.timestamp) > cadence * 3 {
            prevSnapshot = nil
        }

        let reading = ResourceUsageCalculator.reading(from: prevSnapshot, to: snapshot)
        prevSnapshot = snapshot

        let samples = MetricSampleMapper.samples(
            fans: fans, sensors: sensors, reading: reading, at: now
        )

        // Запись и обслуживание — на db-очереди (никогда не ждёт SMC).
        dbQueue.async { [weak self] in
            guard let self else { return }
            self.store.insert(samples)
            self.runMaintenance(now: now)
        }
    }

    // MARK: - Обслуживание (dbQueue)

    /// Раз в минуту — роллап, раз в час — prune, раз в сутки — checkpoint.
    private func runMaintenance(now: Date) {
        if now.timeIntervalSince(lastRollup) >= 60 {
            lastRollup = now
            store.rollupCompletedMinutes(now: now)
        }
        if now.timeIntervalSince(lastPrune) >= 3_600 {
            lastPrune = now
            store.prune(
                rawBefore: now.addingTimeInterval(-Constants.historyRawRetention),
                rollupBefore: now.addingTimeInterval(-Constants.historyRollupRetention)
            )
        }
        if now.timeIntervalSince(lastCheckpoint) >= 86_400 {
            lastCheckpoint = now
            store.checkpointTruncate()
        }
    }

    // MARK: - Запросы (dbQueue, sync)

    /// Синхронный запрос истории. `sync` на db-очередь: перед ним могут стоять
    /// только быстрые (< мс) операции БД, но никогда — ожидание SMC.
    func query(_ request: HistoryQueryRequest) -> HistoryQueryResponse {
        dbQueue.sync {
            store.query(request, rawWindow: Constants.historyRawQueryWindow)
        }
    }

    /// Синхронный список известных имён метрик.
    func availableMetrics() -> [String] {
        dbQueue.sync {
            store.availableMetrics()
        }
    }
}
