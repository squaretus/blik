import Foundation
import AppKit
@preconcurrency import BlikCore
import BlikXPC
import os

/// Системные ресурсы (CPU/RAM/GPU/Disk): polling + расчёт rate из дельты снимков.
///
/// Зеркалит `FanControlVM`: polling Task на интервале из `AppSettingsVM`,
/// sleep/wake observers, мутации `@Observable` только на main actor. Сырые
/// снимки читает хелпер по XPC (`readResources`) либо локальный `ResourceReader`
/// (read-only fallback — root не нужен); дельту в `ResourceReading` считает
/// `ResourceUsageCalculator`.
@Observable
@MainActor
public final class ResourceVM {

    private static let logger = os.Logger(subsystem: "com.blik.shared", category: "Resources")

    // MARK: - Observable state

    /// Производные показатели последнего интервала. `nil` до первой пары снимков.
    public var resources: ResourceReading?

    // MARK: - Private

    @ObservationIgnored private let runtime: BlikRuntime
    @ObservationIgnored private weak var settings: AppSettingsVM?
    @ObservationIgnored private let localReader = ResourceReader()
    /// Предыдущий сырой снимок — для расчёта дельты (CPU%/disk rate).
    @ObservationIgnored private var prevSnapshot: ResourceSnapshot?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var isSleeping = false

    // MARK: - Init

    public init(runtime: BlikRuntime, settings: AppSettingsVM) {
        self.runtime = runtime
        self.settings = settings
        startSleepWakeObservers()
        restartPolling()
    }

    deinit {
        pollingTask?.cancel()
        let nc = NSWorkspace.shared.notificationCenter
        if let obs = sleepObserver { nc.removeObserver(obs) }
        if let obs = wakeObserver { nc.removeObserver(obs) }
    }

    // MARK: - Polling

    public func restartPolling() {
        pollingTask?.cancel()
        guard !isSleeping else {
            pollingTask = nil
            return
        }
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    private func pollLoop() async {
        // Первый снимок сразу — чтобы второй (через интервал) уже дал rate.
        refresh()
        while !Task.isCancelled {
            let interval = settings?.pollIntervalSeconds ?? Constants.defaultPollIntervalSeconds
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return // cancelled
            }
            if Task.isCancelled { return }
            refresh()
        }
    }

    /// Триггерит одно чтение: XPC (асинхронно) либо локальный reader (синхронно).
    private func refresh() {
        if let helper = runtime.xpcClient?.helper() {
            helper.readResources { [weak self] data, error in
                guard let data, error == nil,
                      let snapshot = try? JSONDecoder().decode(ResourceSnapshot.self, from: data)
                else { return }
                Task { @MainActor [weak self] in
                    self?.apply(snapshot)
                }
            }
            return
        }
        // Read-only fallback: ResourceReader не требует root, читаем напрямую.
        apply(localReader.read())
    }

    private func apply(_ snapshot: ResourceSnapshot) {
        let reading = ResourceUsageCalculator.reading(from: prevSnapshot, to: snapshot)
        prevSnapshot = snapshot
        resources = reading
    }

    // MARK: - Sleep/Wake

    private func startSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pauseForSleep() }
        }
        wakeObserver = nc.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resumeAfterWake() }
        }
    }

    private func pauseForSleep() {
        isSleeping = true
        pollingTask?.cancel()
        pollingTask = nil
        // Снимок до сна устарел — после пробуждения считаем дельту заново.
        prevSnapshot = nil
        Self.logger.info("system will sleep: resource polling paused")
    }

    private func resumeAfterWake() {
        isSleeping = false
        restartPolling()
        Self.logger.info("system did wake: resource polling resumed")
    }
}
