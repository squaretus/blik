import SwiftUI
import BlikShared
import BlikCore
import BlikDesign

struct OverviewPage: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        BlikPageContainer {
            validList
        }
    }

    private var validList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BlikPageMetrics.sectionSpacing) {
                TitledCard(title: "Температура") { temperatureSection }
                TitledCard(title: "Ресурсы") { resourceSection }
            }
            .padding(.vertical, 6)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    // MARK: - Grid

    /// Трёхколоночная сетка KPI-ячеек — общая для температур и ресурсов
    /// (единый ритм и выравнивание).
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 28, alignment: .leading), count: 3)
    }

    private var temperatureSection: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
            tempCell("CPU P-CORE", .cpuCores)
            tempCell("CPU E-CORE", .npuECores)
            tempCell("GPU", .gpuCores)
        }
        .searchVisible(matches: ["Температура", "temperature", "CPU", "GPU", "P-CORE", "E-CORE"])
    }

    private var resourceSection: some View {
        let r = coordinator.resource.resources
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
            pctCell("CPU", r?.averagePerformanceBusy)
            pctCell("E-CPU", r?.averageEfficiencyBusy)
            pctCell("GPU", r?.gpu?.utilizationPercent)
            bytesCell("VRAM", used: r?.gpu?.memoryUsed, total: r?.gpu?.memoryTotal)
            bytesCell("RAM", used: r?.memory.used, total: r?.memory.total)
            rateCell("Диск I/O", r?.totalDiskBytesPerSec)
        }
        .searchVisible(matches: ["Ресурсы", "resources", "CPU", "E-CPU", "GPU", "VRAM", "RAM", "память", "диск", "disk", "io"])
    }

    // MARK: - Cells

    /// Температура — цвет по `TemperatureColor` (как на вкладке «Температура»).
    @ViewBuilder
    private func tempCell(_ label: String, _ group: SensorGroup) -> some View {
        let t = averageTemperature(for: group)
        metricCell(label: label, value: "\(Int(t))", unit: "°", tint: TemperatureColor.color(for: t))
    }

    /// Загрузка в % — цвет по нагрузке (green/amber/red).
    @ViewBuilder
    private func pctCell(_ label: String, _ v: Double?) -> some View {
        if let v {
            metricCell(label: label, value: "\(Int(v))", unit: "%", tint: Self.loadColor(v))
        } else {
            dashCell(label)
        }
    }

    /// Память — цвет по доле использования (used / total).
    @ViewBuilder
    private func bytesCell(_ label: String, used: UInt64?, total: UInt64?) -> some View {
        if let used {
            let parts = Self.bytesParts(used)
            let ratio = (total ?? 0) > 0 ? Double(used) / Double(total!) * 100 : nil
            metricCell(label: label, value: parts.0, unit: parts.1,
                       tint: ratio.map(Self.loadColor) ?? .primary)
        } else {
            dashCell(label)
        }
    }

    /// Скорость диска — без порога, нейтральный цвет.
    @ViewBuilder
    private func rateCell(_ label: String, _ v: Double?) -> some View {
        if let v {
            let parts = Self.rateParts(v)
            metricCell(label: label, value: parts.0, unit: parts.1, tint: .primary)
        } else {
            dashCell(label)
        }
    }

    @ViewBuilder
    private func dashCell(_ label: String) -> some View {
        metricCell(label: label, value: "—", unit: "",
                   tint: DesignTokens.textTertiary.resolve(colorScheme))
    }

    /// Единая KPI-ячейка: uppercase-метка + крупное моноширинное число + мелкий
    /// юнит. Цвет числа (`tint`) семантический — по состоянию метрики (нагрузка/
    /// температура/доля памяти), как на детальных вкладках.
    private func metricCell<S: ShapeStyle>(label: String, value: String, unit: String, tint: S) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary.resolve(colorScheme))
                .textCase(.uppercase)
                .tracking(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textTertiary.resolve(colorScheme))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Цвет по нагрузке (%): healthy → warn → hot.
    private static func loadColor(_ pct: Double) -> Color {
        switch pct {
        case ..<60: return DesignTokens.green
        case ..<85: return DesignTokens.amber
        default: return DesignTokens.red
        }
    }

    // MARK: - Helpers

    private func averageTemperature(for group: SensorGroup) -> Double {
        let groupSensors = coordinator.fan.sensors.filter { $0.group == group }
        guard !groupSensors.isEmpty else { return 0 }
        return groupSensors.map(\.temperature).reduce(0, +) / Double(groupSensors.count)
    }

    /// Разбивает `ByteCountFormatter` («1,23 GB») на (число, юнит).
    private static func bytesParts(_ value: UInt64) -> (String, String) {
        let s = ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
        return splitLastToken(s)
    }

    /// Скорость диска → (число, юнит «MB/с»).
    private static func rateParts(_ bytesPerSec: Double) -> (String, String) {
        let s = ByteCountFormatter.string(fromByteCount: Int64(max(0, bytesPerSec)), countStyle: .file)
        let parts = splitLastToken(s)
        return (parts.0, parts.1.isEmpty ? "/с" : parts.1 + "/с")
    }

    private static func splitLastToken(_ s: String) -> (String, String) {
        guard let i = s.lastIndex(of: " ") else { return (s, "") }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }
}
