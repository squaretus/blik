import SwiftUI
import BlikShared
import BlikCore
import BlikDesign

/// Настройки приложения: тема, частота, autostart, daemon/helper статус.
/// Содержимое перенесено из legacy `AppInfoCard` + `StatusCard`.
struct AppPage: View {
    @Environment(AppCoordinator.self) private var coordinator
    @AppStorage("appTheme") private var appTheme: String = AppTheme.dark.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        BlikPageContainer {
            List {
                appearanceSection
                pollSection
                autoLaunchSection
                statusSection
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    private var appearanceSection: some View {
        Section("Внешний вид") {
            Picker("Тема", selection: $appTheme) {
                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.rawValue).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
        .listRowInsets(BlikPageMetrics.rowInsets)
    }

    private var pollSection: some View {
        Section("Опрос") {
            Picker("Частота обновления", selection: Binding(
                get: { coordinator.settings.pollIntervalSeconds },
                set: { coordinator.settings.pollIntervalSeconds = $0 }
            )) {
                Text("1с").tag(TimeInterval(1))
                Text("5с").tag(TimeInterval(5))
                Text("10с").tag(TimeInterval(10))
            }
            .pickerStyle(.segmented)
        }
        .listRowInsets(BlikPageMetrics.rowInsets)
    }

    private var autoLaunchSection: some View {
        Section("Запуск") {
            Toggle("Автозапуск", isOn: Binding(
                get: { coordinator.settings.launchAtLogin },
                set: { coordinator.settings.launchAtLogin = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.large)
            .tint(DesignTokens.accent.resolve(colorScheme))
            .disabled(!coordinator.settings.canManageLaunchAtLogin)
            .help(coordinator.settings.canManageLaunchAtLogin
                  ? "Запускать .blik при входе в систему"
                  : "Доступно после установки .blik из PKG")
        }
        .listRowInsets(BlikPageMetrics.rowInsets)
    }

    private var statusSection: some View {
        Section("Статус") {
            statusRow(label: "Daemon", isOk: coordinator.fan.isConnected,
                      okText: "Подключён", errorText: "Не подключён")
            statusRow(label: "Helper", isOk: !coordinator.fan.helperMissing,
                      okText: "Установлен", errorText: "Не установлен")
            statusRow(label: "Режим", isOk: !coordinator.fan.isReadOnly,
                      okText: "Полный доступ", errorText: "Только чтение")
            if let error = coordinator.fan.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.red)
                    .font(.caption)
                    .lineLimit(3)
            }
        }
        .listRowInsets(BlikPageMetrics.rowInsets)
    }

    private func statusRow(label: String, isOk: Bool, okText: String, errorText: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOk ? DesignTokens.green : DesignTokens.red)
                    .frame(width: 6, height: 6)
                Text(isOk ? okText : errorText)
                    .foregroundStyle(isOk ? Color.green : Color.red)
            }
        }
    }
}
