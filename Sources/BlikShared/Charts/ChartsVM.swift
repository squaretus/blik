import Foundation
@preconcurrency import BlikCore
import BlikXPC
import os

/// VM графиков: держит live-буферы метрик (реальное время) и загружает
/// исторические диапазоны через XPC. По умолчанию — `.live`.
///
/// Live-капчер работает только когда страница на экране (`setVisible`) и режим
/// `.live` — чтобы скрытая вкладка не крутила таймер (см. риск наблюдаемости).
/// Диапазонные запросы уходят на фоновую задачу с `queryHistorySync` (блокирующий
/// вызов), публикация результата — на main.
@Observable
@MainActor
public final class ChartsVM {

    private static let logger = os.Logger(subsystem: "com.blik.shared", category: "Charts")

    // MARK: - Observable state

    /// Текущий режим. По умолчанию live.
    public private(set) var mode: ChartMode = .live
    /// Результаты диапазонного запроса: метрика → агрегированные точки.
    public private(set) var series: [String: [HistoryPoint]] = [:]
    /// Фактический размер бакета последнего диапазонного ответа (для разбивки
    /// на сегменты по разрывам).
    public private(set) var rangeBucketSeconds: Int = 60
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    /// Доступна ли история (хелпер установлен и поддерживает `queryHistory`).
    /// Range-режим при `false` показывает empty-state, а не зависает.
    public private(set) var helperAvailable = false

    /// Метрики, которые нужно грузить в диапазонном режиме (union метрик
    /// видимых виджетов). Проставляется страницей перед `setMode(.range)`;
    /// клампится хелпером до 32. Пусто → берём ключи live-буферов.
    public var metricsToQuery: [String] = []

    /// Окно live-режима, сек (правый край = now, следит за реальным временем).
    /// Выбирается пикером; при доступном хелпере окно любой ширины подтягивается
    /// из daemon-истории и мержится с живым хвостом буфера — иначе после открытия
    /// страницы график пуст, пока буфер не наполнится.
    public private(set) var liveWindowSeconds: TimeInterval = 900
    /// Daemon-история для текущего live-окна (метрика → бакетированные точки).
    /// Обновляется таймером ~каждые 4 с; в `ChartData` мержится с live-буфером.
    public private(set) var liveHistory: [String: [HistoryPoint]] = [:]

    /// Троттлинг перерисовки: тяжёлые графики перечитывают данные по `chartTick`
    /// (реже — ~2 с), summary-плитки — по `summaryTick` (каждый poll). View
    /// подписываются на них вместо сырых `resources`/`sensors`, чтобы live-поллинг
    /// не инвалидировал всю страницу графиков каждую секунду. Во время скролла
    /// тики не публикуются (см. `setScrolling`).
    public private(set) var chartTick: Int = 0
    public private(set) var summaryTick: Int = 0

    // MARK: - Private

    @ObservationIgnored private let runtime: BlikRuntime
    @ObservationIgnored private weak var settings: AppSettingsVM?
    @ObservationIgnored private weak var fan: FanControlVM?
    @ObservationIgnored private weak var resource: ResourceVM?
    @ObservationIgnored private var buffers: [String: LiveMetricBuffer] = [:]
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var rangeTask: Task<Void, Never>?
    @ObservationIgnored private var liveHistoryTask: Task<Void, Never>?
    @ObservationIgnored private var tickCounter = 0
    @ObservationIgnored private var scrolling = false
    /// Как часто перерисовывать тяжёлые графики (сек) — независимо от 1s-сбора.
    @ObservationIgnored private let chartRenderEvery: TimeInterval = 2.0
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private let bufferCapacity = 900

    public init(runtime: BlikRuntime, settings: AppSettingsVM) {
        self.runtime = runtime
        self.settings = settings
        self.helperAvailable = runtime.helperSupportsHistory
    }

    deinit {
        captureTask?.cancel()
        rangeTask?.cancel()
        liveHistoryTask?.cancel()
    }

    /// Привязывает источники поточных данных SMC/ресурсов. Капчер не стартует —
    /// он запускается лениво из `setVisible(true)` (только при видимой странице).
    public func attach(fan: FanControlVM, resource: ResourceVM) {
        self.fan = fan
        self.resource = resource
    }

    // MARK: - Visibility / mode

    /// Управляет live-капчером в зависимости от видимости страницы.
    public func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        helperAvailable = runtime.helperSupportsHistory
        if visible {
            if case .live = mode { startCapture(); restartLiveHistory() }
        } else {
            stopCapture()
            stopLiveHistory()
        }
    }

    /// Переключает режим. Смена режима отменяет активную задачу другого режима.
    public func setMode(_ newMode: ChartMode) {
        mode = newMode
        helperAvailable = runtime.helperSupportsHistory
        rangeTask?.cancel()
        rangeTask = nil
        switch newMode {
        case .live:
            errorMessage = nil
            isLoading = false
            if isVisible { startCapture(); restartLiveHistory() }
        case .range(let range):
            stopCapture()
            stopLiveHistory()
            loadRange(range)
        }
    }

    /// Меняет длительность live-окна (следит за now). Перезапускает подтяжку
    /// истории, если новое окно шире буфера.
    public func setLiveWindow(_ seconds: TimeInterval) {
        liveWindowSeconds = seconds
        if isVisible, case .live = mode { restartLiveHistory() }
    }

    /// Видимое окно `[from, to]` для домена оси X: live → `[now − окно, now]`,
    /// range → границы диапазона.
    public func visibleRange(now: Date = Date()) -> (from: Date, to: Date) {
        switch mode {
        case .live:            return (now.addingTimeInterval(-liveWindowSeconds), now)
        case .range(let r):    return (r.from, r.to)
        }
    }

    // MARK: - Live capture

    private func startCapture() {
        guard captureTask == nil else { return }
        captureTask = Task { @MainActor [weak self] in
            await self?.captureLoop()
        }
    }

    private func stopCapture() {
        captureTask?.cancel()
        captureTask = nil
    }

    private func captureLoop() async {
        while !Task.isCancelled {
            captureTick()
            let interval = settings?.pollIntervalSeconds ?? Constants.defaultPollIntervalSeconds
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return // cancelled
            }
        }
    }

    private func captureTick() {
        let now = Date()
        let samples = MetricSampleMapper.samples(
            fans: fan?.fans ?? [],
            sensors: fan?.sensors ?? [],
            reading: resource?.resources,
            at: now,
        )
        for sample in samples {
            buffers[sample.metric, default: LiveMetricBuffer(capacity: bufferCapacity)]
                .append(ts: sample.ts, value: sample.value)
        }

        // Публикация render-тиков (буфер уже наполнен). Во время скролла — пауза:
        // тяжёлые графики не перестраиваются, пока идёт прокрутка.
        tickCounter += 1
        guard !scrolling else { return }
        summaryTick &+= 1
        let interval = settings?.pollIntervalSeconds ?? Constants.defaultPollIntervalSeconds
        let ratio = max(1, Int((chartRenderEvery / interval).rounded()))
        if tickCounter % ratio == 0 { chartTick &+= 1 }
    }

    /// Пауза перерисовки графиков на время скролла (из `onScrollPhaseChange`).
    /// По завершении скролла — один финальный refresh, чтобы догнать актуальные данные.
    public func setScrolling(_ value: Bool) {
        guard value != scrolling else { return }
        scrolling = value
        if !value {
            summaryTick &+= 1
            chartTick &+= 1
        }
    }

    /// Live-точки метрики за окно `window` секунд от текущего момента.
    public func livePoints(for metric: String, window: TimeInterval) -> [LiveMetricBuffer.Point] {
        guard let buffer = buffers[metric] else { return [] }
        return buffer.points(since: Date().addingTimeInterval(-window))
    }

    /// Live-точки, разбитые на сегменты по разрывам (`Δts > 3 × интервал поллинга`),
    /// чтобы графики не мостили пропуски интерполяцией.
    public func liveSegments(for metric: String, window: TimeInterval) -> [[LiveMetricBuffer.Point]] {
        let interval = settings?.pollIntervalSeconds ?? Constants.defaultPollIntervalSeconds
        return Self.splitSegments(livePoints(for: metric, window: window), gap: interval * 3) { $0.ts }
    }

    // MARK: - Live history (окна шире буфера)

    private func restartLiveHistory() {
        stopLiveHistory()
        liveHistory = [:]
        guard runtime.helperSupportsHistory, runtime.xpcClient != nil else { return }
        liveHistoryTask = Task { @MainActor [weak self] in
            await self?.liveHistoryLoop()
        }
    }

    private func stopLiveHistory() {
        liveHistoryTask?.cancel()
        liveHistoryTask = nil
    }

    private func liveHistoryLoop() async {
        while !Task.isCancelled {
            await fetchLiveHistory()
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return // cancelled
            }
        }
    }

    private func fetchLiveHistory() async {
        guard let client = runtime.xpcClient else { return }
        let base = metricsToQuery.isEmpty ? Array(buffers.keys) : metricsToQuery
        let metrics = Array(Set(base).prefix(HistoryQueryRequest.maxMetrics))
        guard !metrics.isEmpty else { return }
        let now = Date()
        let request = HistoryQueryRequest(metrics: metrics,
                                          from: now.addingTimeInterval(-liveWindowSeconds), to: now)
        let response = await Task.detached(priority: .utility) {
            client.queryHistorySync(request)
        }.value
        guard !Task.isCancelled, let response else { return }
        var dict: [String: [HistoryPoint]] = [:]
        for s in response.series {
            dict[s.metric] = s.points
        }
        liveHistory = dict
        rangeBucketSeconds = Swift.max(1, response.bucketSeconds)
    }

    // MARK: - Range load

    private func loadRange(_ range: ChartTimeRange) {
        var metrics = metricsToQuery.isEmpty ? Array(buffers.keys) : metricsToQuery
        metrics = Array(metrics.prefix(HistoryQueryRequest.maxMetrics))

        guard runtime.helperSupportsHistory, let client = runtime.xpcClient, !metrics.isEmpty else {
            series = [:]
            isLoading = false
            errorMessage = runtime.helperSupportsHistory
                ? nil
                : "История недоступна: хелпер не установлен или устарел."
            return
        }

        isLoading = true
        errorMessage = nil
        let request = HistoryQueryRequest(metrics: metrics, from: range.from, to: range.to)

        rangeTask = Task { [weak self] in
            // queryHistorySync блокирует поток (semaphore) — уводим с main.
            let response = await Task.detached(priority: .userInitiated) {
                client.queryHistorySync(request)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.applyRange(response)
        }
    }

    private func applyRange(_ response: HistoryQueryResponse?) {
        isLoading = false
        guard let response else {
            series = [:]
            errorMessage = "Не удалось загрузить историю."
            return
        }
        var dict: [String: [HistoryPoint]] = [:]
        for s in response.series {
            dict[s.metric] = s.points
        }
        series = dict
        rangeBucketSeconds = Swift.max(1, response.bucketSeconds)
        errorMessage = nil
    }

    /// Диапазонные точки метрики, разбитые на сегменты по разрывам
    /// (`Δts > 3 × bucketSeconds`).
    public func rangeSegments(for metric: String) -> [[HistoryPoint]] {
        Self.splitSegments(series[metric] ?? [], gap: Double(rangeBucketSeconds) * 3) { $0.ts }
    }

    // MARK: - Live merge

    /// Делит данные live-окна на «прошлое» (daemon-история) и «живой хвост» (буфер).
    /// Хвост — последний непрерывный сегмент буфера (свежие точки текущего капчера);
    /// история обрезается до его начала. Стале-фрагменты буфера от прошлых посещений
    /// страницы отбрасываются — их регион покрывает daemon-история.
    public static func liveMergeSplit(history: [HistoryPoint],
                                      bufferSegments: [[LiveMetricBuffer.Point]])
        -> (history: [HistoryPoint], tail: [LiveMetricBuffer.Point]) {
        guard let tail = bufferSegments.last, let tailStart = tail.first?.ts else {
            return (history, [])
        }
        return (history.filter { $0.ts < tailStart }, tail)
    }

    // MARK: - Segmentation

    /// Разбивает упорядоченный по времени ряд на сегменты по разрывам: новый
    /// сегмент начинается, когда зазор между соседними точками превышает `gap`.
    static func splitSegments<T>(_ points: [T], gap: TimeInterval, ts: (T) -> Date) -> [[T]] {
        guard let first = points.first else { return [] }
        var segments: [[T]] = []
        var current: [T] = [first]
        for i in 1..<points.count {
            if ts(points[i]).timeIntervalSince(ts(points[i - 1])) > gap {
                segments.append(current)
                current = [points[i]]
            } else {
                current.append(points[i])
            }
        }
        segments.append(current)
        return segments
    }
}
