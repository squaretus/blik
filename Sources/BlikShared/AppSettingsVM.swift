import Foundation
@preconcurrency import BlikCore
import os

/// Предпочтения приложения, привязанные к UserDefaults.
/// `@AppStorage` — property wrapper для View, в `@Observable` классе не работает,
/// поэтому читаем/пишем UserDefaults напрямую с `didSet`.
///
/// `appTheme` (тёмная/светлая) **не** живёт здесь — это View-уровневая display-only настройка,
/// остаётся `@AppStorage("appTheme")` в `BlikAppMain` / `MainContentView` / `AppInfoCard`.
@Observable
@MainActor
public final class AppSettingsVM {

    private static let logger = os.Logger(subsystem: "com.blik.shared", category: "Settings")
    private static let pollIntervalKey = "pollIntervalSeconds"

    /// Интервал опроса SMC. Допустимые значения — `Constants.pollIntervalOptions`.
    public var pollIntervalSeconds: TimeInterval {
        didSet {
            guard Constants.pollIntervalOptions.contains(pollIntervalSeconds) else {
                pollIntervalSeconds = oldValue
                return
            }
            UserDefaults.standard.set(pollIntervalSeconds, forKey: Self.pollIntervalKey)
            Self.logger.info("poll interval set to \(self.pollIntervalSeconds, privacy: .public)s")
        }
    }

    /// Включён ли автозапуск через LaunchAgent. Чтение/запись синхронно через `launchctl`.
    public var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            let ok = launchAtLogin ? LaunchAgentController.enable() : LaunchAgentController.disable()
            if !ok {
                // Откат — `launchctl` упал, возвращаем UI в реальное состояние.
                launchAtLogin = !launchAtLogin
                Self.logger.error("launchctl \(self.launchAtLogin ? "bootstrap" : "bootout", privacy: .public) failed")
            }
        }
    }

    /// True, если LaunchAgent plist установлен (PKG прогнан).
    public var canManageLaunchAtLogin: Bool {
        LaunchAgentController.isInstalled
    }

    public init() {
        let stored = UserDefaults.standard.double(forKey: Self.pollIntervalKey)
        self.pollIntervalSeconds = Constants.pollIntervalOptions.contains(stored)
            ? stored
            : Constants.defaultPollIntervalSeconds
        self.launchAtLogin = LaunchAgentController.isEnabled
    }

    /// Синхронизирует launchAtLogin со state launchctl (вызывать на onAppear главного окна).
    public func refreshLaunchAtLogin() {
        let actual = LaunchAgentController.isEnabled
        if actual != launchAtLogin {
            launchAtLogin = actual
        }
    }
}
