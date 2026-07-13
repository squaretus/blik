import SwiftUI
import BlikShared
import BlikCore
import BlikDesign

/// Вкладка «Температура»: сенсоры по группам + куллеры (обороты) и управление
/// скоростью. Обвязка (gating, поиск, список) — в общем `MetricSectionListPage`;
/// страница маппит данные сенсоров и добавляет секции куллеров/управления через
/// trailing-слот.
struct SensorsPage: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Куллеры + управление скоростью — в самом начале вкладки (leading-слот),
        // до категорий сенсоров.
        MetricSectionListPage(sections: sections) {
            coolersPanel
            controlPanel
        }
    }

    private var sections: [MetricSection] {
        orderedGroups.compactMap { group in
            let items = coordinator.fan.sensors.filter { $0.group == group }
            guard !items.isEmpty else { return nil }
            let avg = average(of: items)
            return MetricSection(
                id: "temp-\(group.rawValue)",
                title: group.title,
                badge: MetricBadge(text: "avg \(Int(avg))°C",
                                   color: TemperatureColor.color(for: avg)),
                rows: items.map { sensor in
                    let renameKey = MetricKey.temp(sensor.key)
                    let custom = coordinator.metricNames.displayName(for: renameKey, default: sensor.name)
                    return MetricRow(
                        id: "temp-\(sensor.key)",
                        label: custom,
                        value: "\(Int(sensor.temperature))°",
                        color: TemperatureColor.color(for: sensor.temperature),
                        searchTerms: [sensor.name, custom, group.title],
                        renameKey: renameKey,
                        defaultLabel: sensor.name,
                    )
                },
            )
        }
    }

    private var orderedGroups: [SensorGroup] {
        [.cpuCores, .npuECores, .gpuCores, .other]
    }

    private func average(of sensors: [SensorInfo]) -> Double {
        guard !sensors.isEmpty else { return 0 }
        return sensors.map(\.temperature).reduce(0, +) / Double(sensors.count)
    }

    // MARK: - Coolers (обороты)

    private var coolersPanel: some View {
        TitledCard(title: "Куллеры") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(coordinator.fan.fans, id: \.id) { fan in
                    fanRow(fan)
                }
            }
        }
        .searchVisible(matches: ["Куллеры", "куллер", "cooler", "fan", "rpm"])
    }

    private func fanRow(_ fan: FanInfo) -> some View {
        let range = fan.maximumSpeed - fan.minimumSpeed
        let percentage = range > 0 ? (fan.actualSpeed - fan.minimumSpeed) / range : 0
        let clamped = min(max(percentage, 0), 1)

        return VStack(spacing: 6) {
            HStack {
                Label {
                    EditableMetricLabel(key: MetricKey.fanRPM(fan.id), defaultName: "Fan \(fan.id)")
                } icon: {
                    AppIcons.FanIcon()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: formatRPM(fan.actualSpeed))
                        .font(.headline)
                        .monospacedDigit()
                    Text("RPM")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignTokens.progressBarBg.resolve(colorScheme))
                    Capsule()
                        .fill(TemperatureColor.fanGradient(percentage: clamped))
                        .frame(width: geo.size.width * clamped)
                }
            }
            .frame(height: DesignTokens.progressBarHeight)
        }
    }

    // MARK: - Control (управление скоростью)

    private var controlPanel: some View {
        TitledCard(title: "Управление") {
            VStack(alignment: .leading, spacing: 12) {
                if coordinator.fan.isUnlocking {
                    BlikBanner(tone: .accent, systemImage: nil, text: "Разблокировка управления...") {
                        ProgressView().controlSize(.small)
                    }
                }
                HStack {
                    BlikPresetButtons(currentPreset: coordinator.fan.currentPreset, size: .regular) { preset in
                        coordinator.fan.setSpeedPreset(percentage: preset)
                    }
                    .animation(.easeOut(duration: 0.15), value: coordinator.fan.currentPreset)
                    Spacer()
                    modeBadge
                }
            }
        }
        .searchVisible(matches: ["Управление", "control", "preset", "пресет", "auto", "manual", "авто"])
    }

    private var modeBadge: some View {
        let isAuto = coordinator.fan.currentPreset == 0
        return BlikStatusPill(
            text: isAuto ? "AUTO" : "MANUAL",
            color: isAuto ? DesignTokens.green : DesignTokens.amber
        )
    }

    // MARK: - Helpers

    private func formatRPM(_ rpm: Double) -> String {
        let clamped = min(rpm, Constants.maxDisplayRPM)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: clamped)) ?? "\(Int(clamped))"
    }
}
