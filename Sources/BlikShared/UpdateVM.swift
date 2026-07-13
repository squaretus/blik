import Foundation
@preconcurrency import BlikCore
import BlikXPC
import os

/// Проверка наличия обновлений + установка через daemon.
/// Owns 6h auto-check Task и manual check (без таймера).
///
/// `shouldTerminate` (флаг для перезапуска приложения после установки апдейта) реплицируется
/// в `FanControlVM.shouldTerminate` через `AppCoordinator` — там же и watch'ится в MainContentView.
@Observable
@MainActor
public final class UpdateVM {

    private static let logger = os.Logger(subsystem: "com.blik.shared", category: "Update")

    // MARK: - Observable state

    public var availableUpdate: UpdateInfo?
    public var isInstallingUpdate: Bool = false
    public var manualUpdateResult: String?

    /// Флаг «приложение должно завершиться» — после успешного запуска installer'а.
    /// Координатор пробрасывает его в `FanControlVM.shouldTerminate`.
    public var shouldTerminate: Bool = false

    // MARK: - Private

    @ObservationIgnored private let runtime: BlikRuntime
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var installMonitorTask: Task<Void, Never>?
    /// Hard-cap на установку: если за это время не пришёл ни reply `performUpdate`,
    /// ни disconnect daemon'а — установка зависла. Снимаем `isInstallingUpdate`,
    /// чтобы не висел спиннер «Установка обновления…» (удерживает display-cycle)
    /// и не крутился вечный 3с-poll `monitorInstall`. Нормальная установка
    /// завершается перезапуском задолго до этого. Инъектируется в init (тесты — малый порог).
    @ObservationIgnored private let installTimeoutSeconds: Int

    // MARK: - Init

    public init(runtime: BlikRuntime, installTimeoutSeconds: Int = 300) {
        self.runtime = runtime
        self.installTimeoutSeconds = installTimeoutSeconds
        checkForUpdate()
        checkTask = Task { [weak self] in
            await self?.checkLoop()
        }
    }

    deinit {
        checkTask?.cancel()
        installMonitorTask?.cancel()
    }

    // MARK: - Periodic check

    private func checkLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(Constants.updateCheckInterval))
            } catch {
                return
            }
            if Task.isCancelled { return }
            checkForUpdate()
        }
    }

    private func checkForUpdate() {
        guard let helper = runtime.xpcClient?.helper() else { return }
        UpdateService.checkForced(helper: helper) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .available(let info):
                    self.availableUpdate = info
                    Self.logger.info("Update available: v\(info.latestVersion)")
                case .upToDate, .error:
                    self.availableUpdate = nil
                }
            }
        }
    }

    // MARK: - Manual check

    public func checkForUpdateManually() {
        manualUpdateResult = nil
        guard let helper = runtime.xpcClient?.helper() else {
            manualUpdateResult = "Хелпер недоступен"
            return
        }
        UpdateService.checkForced(helper: helper) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .available(let info):
                    self.availableUpdate = info
                    self.manualUpdateResult = nil
                case .upToDate(let version):
                    self.availableUpdate = nil
                    self.manualUpdateResult = "Установлена последняя версия \(version)"
                case .error(let message):
                    self.manualUpdateResult = "Ошибка: \(message)"
                }
                try? await Task.sleep(for: .seconds(5))
                self.manualUpdateResult = nil
            }
        }
    }

    // MARK: - Install

    public func installUpdate() {
        guard let helper = runtime.xpcClient?.helper() else { return }
        isInstallingUpdate = true
        helper.performUpdate { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isInstallingUpdate {
                    Self.logger.info("performUpdate reply received during install, terminating")
                    self.shouldTerminate = true
                }
            }
        }

        // Мониторинг: когда daemon умрёт (installer делает bootout) — выйти, чтобы перезапуститься.
        installMonitorTask?.cancel()
        installMonitorTask = Task { [weak self] in
            await self?.monitorInstall()
        }
    }

    private func monitorInstall() async {
        // Опрашиваем подключение каждые 3с пока isInstallingUpdate.
        var elapsedSeconds = 0
        while !Task.isCancelled, isInstallingUpdate {
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            elapsedSeconds += 3
            guard let client = runtime.xpcClient, client.isConnected else {
                Self.logger.info("Daemon disconnected during update, terminating for relaunch")
                shouldTerminate = true
                return
            }
            if elapsedSeconds >= installTimeoutSeconds {
                // Ни reply, ни disconnect — установка зависла. Снимаем флаг.
                Self.logger.error("install watchdog fired: no reply/disconnect within \(self.installTimeoutSeconds)s")
                isInstallingUpdate = false
                manualUpdateResult = "Установка не завершилась. Попробуйте позже."
                return
            }
        }
    }
}
