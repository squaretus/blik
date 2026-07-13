import Foundation
import AppKit
@preconcurrency import BlikCore
import BlikXPC
import os

/// Vitals + управление кулерами + connection state.
/// Owns: polling Task (через XPC или прямой SMC), sleep/wake observers, preset state.
///
/// **Threading:** все мутации `@Observable` свойств — на main actor.
/// XPC callbacks приходят с XPC-очереди — внутри callback'а **обязателен**
/// `Task { @MainActor in ... }` перед любой записью в self.
@Observable
@MainActor
public final class FanControlVM {

    private static let logger = os.Logger(subsystem: "com.blik.shared", category: "FanControl")

    // MARK: - Observable state

    public var fans: [FanInfo] = []
    public var sensors: [SensorInfo] = []
    public var currentPreset: Int = 0
    public var isReadOnly: Bool = true
    public var isUnlocking: Bool = false
    public var isConnected: Bool = false
    public var helperMissing: Bool = false
    public var errorMessage: String?
    public var shouldTerminate: Bool = false

    /// Средняя температура CPU + E-Core + GPU (весь чип M4).
    public var averageChipTemp: Int {
        let chip = sensors.filter { [.cpuCores, .npuECores, .gpuCores].contains($0.group) }
        guard !chip.isEmpty else { return 0 }
        return Int(chip.map(\.temperature).reduce(0, +) / Double(chip.count))
    }

    /// Проектор отображаемых значений menu-bar иконки (уже квантованные Int).
    /// `MenuBarLabel` наблюдает ИХ, а не сырые `fans`/`sensors` — поэтому его body
    /// пере-вычисляется только при смене отображаемого числа (раз в несколько
    /// секунд), а не на каждый poll-тик (jitter RPM/температур в Double). Это
    /// режет частоту ре-рендера always-live status-item → меньше утечки
    /// observation-трекинга в `MenuBarExtra`. Обновляются в `applyUpdate` только при изменении.
    public private(set) var menuFan0RPM: Int?
    public private(set) var menuFan1RPM: Int?
    public private(set) var menuChipTemp: Int?

    // MARK: - Private

    @ObservationIgnored private let runtime: BlikRuntime
    @ObservationIgnored private weak var settings: AppSettingsVM?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var isSleeping: Bool = false
    /// Watchdog для `isUnlocking`: страховка от потерянного XPC-reply
    /// `setFanSpeedPreset`. Без него флаг (и спиннер «Разблокировка…») мог бы
    /// зависнуть навсегда, удерживая display-cycle активным при открытом окне.
    @ObservationIgnored private var unlockTimeoutTask: Task<Void, Never>?
    /// Полная разблокировка (Ftst + F{n}Md retry) укладывается в ~10–15с;
    /// 30с — заведомо больше нормального завершения, срабатывает только на
    /// реально потерянном reply. Инъектируется в init (тесты ставят малый порог).
    @ObservationIgnored private let unlockTimeout: Duration

    // MARK: - Init

    public init(runtime: BlikRuntime, settings: AppSettingsVM,
                unlockTimeout: Duration = .seconds(30)) {
        self.runtime = runtime
        self.settings = settings
        self.unlockTimeout = unlockTimeout

        // Реплицируем connection state из runtime в @Observable свойства.
        self.isConnected = (runtime.xpcClient != nil) || (runtime.reader != nil)
        self.isReadOnly = runtime.isReadOnly
        self.helperMissing = runtime.xpcClient == nil
        self.errorMessage = runtime.startupError

        // Начальное чтение через XPC (асинхронно) или прямой reader (синхронно).
        if let client = runtime.xpcClient, let helper = client.helper() {
            helper.readAllFans { [weak self] data, error in
                guard let data, error == nil,
                      let fans = try? JSONDecoder().decode([FanInfo].self, from: data) else { return }
                Task { @MainActor [weak self] in
                    self?.fans = fans
                }
            }
            helper.readAllSensors { [weak self] data, error in
                guard let data, error == nil,
                      let sensors = try? JSONDecoder().decode([SensorInfo].self, from: data) else { return }
                Task { @MainActor [weak self] in
                    self?.sensors = sensors
                }
            }
        } else if let reader = runtime.reader {
            self.fans = (try? reader.readAllFans()) ?? []
            self.sensors = (try? reader.readAllSensors()) ?? []
        }

        startSleepWakeObservers()
        restartPolling()
    }

    deinit {
        // pollingTask cancellation — без await, deinit nonisolated.
        pollingTask?.cancel()
        unlockTimeoutTask?.cancel()
        // observers cleanup — synchronous, NotificationCenter API thread-safe.
        let nc = NSWorkspace.shared.notificationCenter
        if let obs = sleepObserver { nc.removeObserver(obs) }
        if let obs = wakeObserver { nc.removeObserver(obs) }
    }

    // MARK: - Polling

    /// Отменяет текущий polling Task и запускает новый. Безопасно вызывать при изменении
    /// `pollIntervalSeconds` или после wake from sleep.
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
        while !Task.isCancelled {
            // Читаем live-значение интервала — изменения в Settings подхватываются на следующей итерации.
            let interval = settings?.pollIntervalSeconds ?? Constants.defaultPollIntervalSeconds
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return // cancelled
            }
            if Task.isCancelled { return }
            refreshData()
        }
    }

    /// Триггерит одно чтение vitals (XPC-путь — асинхронный, прямой SMC — синхронный).
    private func refreshData() {
        if let client = runtime.xpcClient, let helper = client.helper() {
            if runtime.supportsReadState {
                helper.readState { [weak self] data, error in
                    guard let data, error == nil,
                          let snapshot = try? JSONDecoder().decode(StateSnapshot.self, from: data) else { return }
                    Task { @MainActor [weak self] in
                        self?.applyUpdate(fans: snapshot.fans, sensors: snapshot.sensors)
                    }
                }
            } else {
                helper.readAllFans { [weak self] data, error in
                    guard let self, !Task.isCancelled,
                          let data, error == nil,
                          let newFans = try? JSONDecoder().decode([FanInfo].self, from: data) else { return }
                    helper.readAllSensors { [weak self] sensorData, sensorError in
                        guard let self, !Task.isCancelled,
                              let sensorData, sensorError == nil,
                              let newSensors = try? JSONDecoder().decode([SensorInfo].self, from: sensorData) else { return }
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.applyUpdate(fans: newFans, sensors: newSensors)
                        }
                    }
                }
            }
            return
        }

        // Direct SMC read-only path
        guard let reader = runtime.reader else { return }
        do {
            let newFans = try reader.readAllFans()
            let newSensors = try reader.readAllSensors()
            applyUpdate(fans: newFans, sensors: newSensors)
        } catch {
            Self.logger.error("refreshData failed: \(error)")
            errorMessage = "Ошибка чтения: \(error.localizedDescription)"
        }
    }

    /// Публикует данные только при реальном изменении — избегаем лишних перерисовок SwiftUI.
    private func applyUpdate(fans newFans: [FanInfo], sensors newSensors: [SensorInfo]) {
        if fans != newFans { fans = newFans }
        if sensors != newSensors { sensors = newSensors }
        updateMenuProjection(fans: newFans, sensors: newSensors)
    }

    /// Пересчитывает квантованные menu-bar значения и пишет их ТОЛЬКО при
    /// изменении — чтобы наблюдатели `menuFan0RPM`/`menuFan1RPM`/`menuChipTemp`
    /// (т.е. `MenuBarLabel`) не дёргались на каждый poll-тик.
    private func updateMenuProjection(fans newFans: [FanInfo], sensors newSensors: [SensorInfo]) {
        let f0 = newFans.first.map { Int($0.actualSpeed) }
        let f1 = newFans.count > 1 ? Int(newFans[1].actualSpeed) : nil
        let chip = newSensors.filter { [.cpuCores, .npuECores, .gpuCores].contains($0.group) }
        let temp = chip.isEmpty ? nil : Int(chip.map(\.temperature).reduce(0, +) / Double(chip.count))
        if menuFan0RPM != f0 { menuFan0RPM = f0 }
        if menuFan1RPM != f1 { menuFan1RPM = f1 }
        if menuChipTemp != temp { menuChipTemp = temp }
    }

    // MARK: - Sleep/Wake

    private func startSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pauseForSleep()
            }
        }
        wakeObserver = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resumeAfterWake()
            }
        }
    }

    private func pauseForSleep() {
        isSleeping = true
        pollingTask?.cancel()
        pollingTask = nil
        Self.logger.info("system will sleep: polling paused")
    }

    private func resumeAfterWake() {
        isSleeping = false
        restartPolling()
        Self.logger.info("system did wake: polling resumed")
    }

    // MARK: - Fan Control

    public func setSpeedPreset(percentage: Int) {
        if let client = runtime.xpcClient, let helper = client.helper() {
            errorMessage = nil
            currentPreset = percentage

            // Мгновенный UI feedback
            if percentage == 0 {
                for i in 0..<fans.count {
                    fans[i].isForced = false
                }
            } else {
                if !fans.contains(where: \.isForced) {
                    beginUnlock()
                }
                let fraction = Double(percentage) / 100.0
                for i in 0..<fans.count {
                    fans[i].targetSpeed = fans[i].minimumSpeed + (fans[i].maximumSpeed - fans[i].minimumSpeed) * fraction
                    fans[i].isForced = true
                }
            }

            helper.setFanSpeedPreset(percentage: percentage) { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.endUnlock()
                    if let error {
                        self?.errorMessage = error
                    }
                }
            }
            return
        }

        // Direct SMC недоступен в read-only режиме
        errorMessage = "Режим только для чтения"
    }

    /// Включает индикатор разблокировки и взводит watchdog-таймаут на случай
    /// потерянного XPC-reply (см. `unlockTimeoutTask`).
    private func beginUnlock() {
        isUnlocking = true
        unlockTimeoutTask?.cancel()
        let timeout = unlockTimeout
        unlockTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, !Task.isCancelled, self.isUnlocking else { return }
            self.isUnlocking = false
            Self.logger.error("unlock watchdog fired: setFanSpeedPreset reply lost")
        }
    }

    /// Снимает индикатор разблокировки и отменяет watchdog. Идемпотентно.
    private func endUnlock() {
        unlockTimeoutTask?.cancel()
        unlockTimeoutTask = nil
        isUnlocking = false
    }

    public func restoreAutoMode() {
        setSpeedPreset(percentage: 0)
    }

    // MARK: - Uninstall

    public func uninstallApp() {
        if let helper = runtime.xpcClient?.helper() {
            helper.uninstallAll { [weak self] error in
                Task { @MainActor [weak self] in
                    if let error {
                        self?.errorMessage = "Ошибка удаления: \(error)"
                    }
                    // App завершится автоматически — daemon остановит LaunchAgent.
                    // Подстраховка через 6с (daemon может тушить LaunchAgent дольше 2с).
                    try? await Task.sleep(for: .seconds(6))
                    self?.shouldTerminate = true
                }
            }
        } else {
            uninstallViaScript()
        }
    }

    private func uninstallViaScript() {
        guard let scriptURL = Bundle.main.url(forResource: "uninstall-helper", withExtension: "sh") else {
            errorMessage = "Скрипт удаления не найден"
            return
        }

        let tmpPath = "/tmp/uninstall-helper.sh"
        try? FileManager.default.removeItem(atPath: tmpPath)
        try? FileManager.default.copyItem(atPath: scriptURL.path, toPath: tmpPath)

        // process.run() возвращается мгновенно — раньше app тушился через 2с,
        // а osascript ещё ждал sudo-пароль у юзера: pwd-prompt оставался без
        // родителя, мог зацикливаться. Теперь ждём `waitUntilExit` в фоновом
        // Task и только потом ставим shouldTerminate.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"bash \(tmpPath)\" with administrator privileges"
        ]
        do {
            try process.run()
            Task.detached(priority: .userInitiated) { [weak self] in
                process.waitUntilExit()
                await MainActor.run {
                    self?.shouldTerminate = true
                }
            }
        } catch {
            errorMessage = "Ошибка запуска удаления: \(error.localizedDescription)"
        }
    }
}
