import Foundation
import AppKit
import os
import BlikCore

/// Идентификатор вкладки главного окна. Живёт в BlikShared, чтобы `AppCoordinator.pendingTab`
/// мог быть public (URL deep-link парсится в координаторе).
public enum SidebarTab: String, CaseIterable, Hashable, Sendable {
    case overview, temperature, resources, charts

    public var title: String {
        switch self {
        case .overview: return "Обзор"
        case .temperature: return "Температура"
        case .resources: return "Ресурсы"
        case .charts: return "Графики"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .temperature: return "thermometer.medium"
        case .resources: return "cpu"
        case .charts: return "chart.xyaxis.line"
        }
    }
}

/// Корневой координатор VM-слоя. Owns узкие VM (`fan`/`resource`/`update`/`settings`) и `runtime`.
/// Инжектится в SwiftUI environment один раз: `.environment(coordinator)`.
///
/// **Lifecycle:**
/// - В `init` создаёт `BlikRuntime`, затем VM'ы, затем подписывается на `NSApplication.willTerminateNotification`
///   для синхронного `runtime.cleanup()` (R2: гарантирует возврат fans в AUTO до выхода процесса).
/// - В `init` ставит наблюдение `withObservationTracking` на `settings.pollIntervalSeconds`,
///   чтобы при изменении интервала перезапускать polling Task в `fan` (R10).
/// - Реплицирует `update.shouldTerminate` в `fan.shouldTerminate` через Observation, чтобы
///   `MainContentView.onChange` имел один источник правды.
@Observable
@MainActor
public final class AppCoordinator {

    private static let logger = os.Logger(subsystem: "com.blik.shared", category: "Coordinator")

    @ObservationIgnored public let runtime: BlikRuntime
    @ObservationIgnored public let settings: AppSettingsVM
    @ObservationIgnored public let fan: FanControlVM
    @ObservationIgnored public let resource: ResourceVM
    @ObservationIgnored public let update: UpdateVM
    /// Кастомные имена датчиков/метрик (инлайн-переименование). Общий store
    /// для окна и menubar (suite `com.blik.shared`).
    @ObservationIgnored public let metricNames = MetricNameStore()
    /// VM вкладки «Графики»: live-буферы + диапазонные запросы истории через XPC.
    @ObservationIgnored public let charts: ChartsVM
    /// Конфигурации виджетов графиков (фиксированный набор, персист в suite
    /// `com.blik.shared`).
    @ObservationIgnored public let chartWidgets = ChartWidgetStore()

    /// Запрошенная через URL deep-link вкладка. View читает + сбрасывает в nil.
    /// Используется как «канал доставки» от `application(_:open:)` к `MainContentView`.
    public var pendingTab: SidebarTab?

    @ObservationIgnored private var willTerminateObserver: NSObjectProtocol?

    public init() {
        self.runtime = BlikRuntime()
        self.settings = AppSettingsVM()
        self.fan = FanControlVM(runtime: runtime, settings: settings)
        self.resource = ResourceVM(runtime: runtime, settings: settings)
        self.update = UpdateVM(runtime: runtime)
        self.charts = ChartsVM(runtime: runtime, settings: settings)
        self.charts.attach(fan: self.fan, resource: self.resource)

        // Cleanup на выходе процесса — sync restoreAutoMode (R2).
        // Closure доставляется на .main, поэтому MainActor.assumeIsolated безопасен.
        let nc = NotificationCenter.default
        willTerminateObserver = nc.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.runtime.cleanup(currentFanCount: self.fan.fans.count)
            }
        }

        // Pollinterval changes → restart polling Task в FanControlVM (R10).
        observePollInterval()
        // shouldTerminate из UpdateVM реплицируется в FanControlVM.
        observeUpdateShouldTerminate()
    }

    deinit {
        if let obs = willTerminateObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Uninstall

    /// Полное удаление: daemon-uninstall через FanControlVM,
    /// который сам выставит shouldTerminate.
    public func uninstallApp() {
        fan.uninstallApp()
    }

    // MARK: - Cross-VM observation

    /// Реакция на изменение `settings.pollIntervalSeconds` через `withObservationTracking`.
    /// `onChange` срабатывает один раз — после реакции переподписываемся рекурсивно.
    private func observePollInterval() {
        withObservationTracking {
            _ = settings.pollIntervalSeconds
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.fan.restartPolling()
                self.resource.restartPolling()
                self.observePollInterval()
            }
        }
    }

    /// Реплицирует `update.shouldTerminate` в `fan.shouldTerminate`, чтобы
    /// `MainContentView.onChange(coordinator.fan.shouldTerminate)` ловил оба источника.
    private func observeUpdateShouldTerminate() {
        withObservationTracking {
            _ = update.shouldTerminate
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.update.shouldTerminate {
                    self.fan.shouldTerminate = true
                }
                self.observeUpdateShouldTerminate()
            }
        }
    }

    // MARK: - Deep linking

    /// Парсит URL:
    /// - `blik://settings`/`blik://overview`/`blik://temperature` → set `pendingTab`.
    public func handleDeepLink(_ url: URL) {
        let token = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()

        guard let tab = SidebarTab(rawValue: token) else {
            Self.logger.info("deep-link unknown token \(token, privacy: .public), fallback to overview")
            pendingTab = .overview
            return
        }
        Self.logger.info("deep-link → \(tab.rawValue, privacy: .public)")
        pendingTab = tab
    }
}
