import SwiftUI
import BlikCore
import BlikShared
import BlikDesign
import AppKit

struct MenuBarPopupView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    /// Видим ли popup сейчас. `.menuBarExtraStyle(.window)` держит контент
    /// примонтированным даже когда popup закрыт, и SwiftUI пере-вычисляет его body
    /// на каждое изменение наблюдаемых `coordinator.*` (а они меняются каждый
    /// poll-тик) — регистрируя observation-трекинг, который MenuBarExtra не
    /// освобождает (утечка ~1-2 записи/сек → деградация CPU/RAM за часы).
    /// Пока popup закрыт — рендерим пустышку, не читающую `coordinator.*`.
    @State private var isPresented = false

    var body: some View {
        Group {
            if isPresented {
                presentedBody
            } else {
                Color.clear.frame(width: 340, height: 1)
            }
        }
        .onAppear { isPresented = true }
        .onDisappear { isPresented = false }
    }

    private var presentedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            validBody
        }
        .padding(12)
        .frame(width: 340)
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

    // MARK: - Valid body (full popup)

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

            // Fans
            ForEach(coordinator.fan.fans, id: \.id) { fan in
                MenuBarFanRowView(fan: fan)
            }

            // Preset buttons
            if !coordinator.fan.isReadOnly {
                BlikPresetButtons(currentPreset: coordinator.fan.currentPreset, size: .compact) { preset in
                    coordinator.fan.setSpeedPreset(percentage: preset)
                }
                .disabled(coordinator.fan.isUnlocking)
            }

            if !coordinator.fan.sensors.isEmpty {
                Divider()

                // Кастомные имена применяются лениво, только пока popup открыт
                // (внутри presentedBody) — не читаем store при закрытом popup,
                // чтобы не сломать фикс утечки observation.
                let grouped = Dictionary(grouping: renamedSensors, by: \.group)
                ForEach(Array(grouped.keys.sorted()), id: \.self) { group in
                    if let items = grouped[group], !items.isEmpty {
                        MenuBarSensorSectionView(group: group, sensors: items)
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
                Text("Панель")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(DesignTokens.accent.resolve(colorScheme).opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // willTerminateNotification observer в AppCoordinator выполнит cleanup +
            // sync restoreAutoMode перед фактическим выходом процесса.
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Выход")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }

    /// Показать главное окно приложения (уже в том же процессе) и свернуть
    /// popup menu bar в иконку.
    ///
    /// Popup MenuBarExtra(`.window`) при клике по кнопке — текущее key-окно;
    /// публичного dismiss-API у `.menuBarExtraStyle(.window)` нет, поэтому
    /// закрываем key-окно вручную. Показ/активацию главного окна
    /// централизуем через `.showMainWindow` (обработчик в `BlikAppMain`
    /// делает `openWindow(id:"main")` + `activate(ignoringOtherApps:)`).
    private func openPanel() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.keyWindow?.close()
        NotificationCenter.default.post(name: .showMainWindow, object: nil)
    }
}
