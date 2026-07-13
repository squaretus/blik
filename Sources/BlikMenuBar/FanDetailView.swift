import SwiftUI
import BlikCore
import BlikShared
import BlikDesign
import AppKit

struct FanDetailView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var colorScheme

    /// Открывает GUI-приложение BlikApp (через bundle path или dev-биндинг).
    private func openPanel() {
        let bundlePath = "/Applications/Blik.app"
        if FileManager.default.fileExists(atPath: bundlePath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: bundlePath))
        } else {
            let devPath = Bundle.main.bundlePath
                .components(separatedBy: "/")
                .dropLast()
                .joined(separator: "/") + "/BlikApp"
            if FileManager.default.fileExists(atPath: devPath) {
                Process.launchedProcess(launchPath: devPath, arguments: [])
            }
        }
    }

    /// Открывает GUI-приложение и переключает его на вкладку «Настройки» через URL scheme `blik://settings`.
    /// Cold-start: NSWorkspace.shared.open запустит BlikApp, AppDelegate.application(_:open:) поймает URL.
    /// Warm: запущенный процесс получит URL через тот же AppDelegate hook + .onOpenURL.
    private func openSettings() {
        if let url = URL(string: "blik://settings") {
            NSWorkspace.shared.open(url)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            validBody
        }
        .padding(12)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(".blik")
                .font(.headline)
            Spacer()
            if coordinator.fan.isReadOnly {
                Text("Read Only")
                    .font(.caption)
                    .foregroundColor(DesignTokens.textSecondary.resolve(colorScheme))
            }
        }
    }

    // MARK: - Valid body

    private var validBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = coordinator.fan.errorMessage {
                BlikBanner(tone: .error, systemImage: "exclamationmark.triangle", text: error)
            }

            if coordinator.fan.helperMissing {
                BlikBanner(
                    tone: .warn,
                    systemImage: "exclamationmark.circle",
                    text: "Хелпер не установлен. Запустите Blik.pkg для полного функционала."
                )
            }

            if let update = coordinator.update.availableUpdate, update.isNewer {
                BlikBanner(
                    tone: .info,
                    systemImage: coordinator.update.isInstallingUpdate ? nil : "arrow.down.circle.fill",
                    text: coordinator.update.isInstallingUpdate
                        ? "Установка обновления..."
                        : "Доступно обновление v\(update.latestVersion)"
                ) {
                    if coordinator.update.isInstallingUpdate {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Обновить") { coordinator.update.installUpdate() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }

            if coordinator.fan.isUnlocking {
                BlikBanner(tone: .accent, systemImage: nil, text: "Разблокировка управления...") {
                    ProgressView().controlSize(.small)
                }
            }

            Divider()

            ForEach(coordinator.fan.fans, id: \.id) { fan in
                FanRowView(fan: fan)
            }

            if !coordinator.fan.isReadOnly {
                BlikPresetButtons(currentPreset: coordinator.fan.currentPreset, size: .compact) { preset in
                    coordinator.fan.setSpeedPreset(percentage: preset)
                }
                .disabled(coordinator.fan.isUnlocking)
            }

            if !coordinator.fan.sensors.isEmpty {
                Divider()

                // Кастомные имена применяются лениво внутри presentedBody
                // (только при открытом popup).
                let grouped = Dictionary(grouping: renamedSensors, by: \.group)
                ForEach(Array(grouped.keys.sorted()), id: \.self) { group in
                    if let items = grouped[group], !items.isEmpty {
                        SensorSectionView(group: group, sensors: items)
                    }
                }
            }

            Divider()

            footer
        }
    }

    /// Копии сенсоров с применённым кастомным именем (read-only переименование).
    /// Читается только из `validBody`, т.е. при открытом popup.
    private var renamedSensors: [SensorInfo] {
        coordinator.fan.sensors.map { sensor in
            let display = coordinator.metricNames.displayName(for: MetricKey.temp(sensor.key), default: sensor.name)
            guard display != sensor.name else { return sensor }
            return SensorInfo(key: sensor.key, name: display, group: sensor.group, temperature: sensor.temperature)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                openPanel()
            } label: {
                Text("Открыть панель")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(DesignTokens.accent.resolve(colorScheme).opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // willTerminateNotification observer в AppCoordinator выполнит cleanup (sync restoreAutoMode).
            Button("Выход") {
                NSApplication.shared.terminate(nil)
            }
            .foregroundColor(DesignTokens.textSecondary.resolve(colorScheme))
        }
    }
}
