import SwiftUI
import BlikShared
import BlikCore
import BlikDesign

/// Вкладка «Ресурсы»: CPU (по ядрам) / GPU / RAM / Disk IO. Обвязка — общий
/// `MetricSectionListPage`; страница маппит `ResourceVM.resources` в секции.
struct ResourcesPage: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        MetricSectionListPage(sections: sections)
    }

    private var sections: [MetricSection] {
        guard let r = coordinator.resource.resources else { return [] }
        var out: [MetricSection] = []
        out.append(contentsOf: cpuSections(r))
        if let gpu = r.gpu { out.append(gpuSection(gpu)) }
        out.append(memorySection(r.memory))
        if let disks = diskSection(r.disks) { out.append(disks) }
        return out
    }

    // MARK: - CPU (P-cores и E-cores отдельными секциями)

    private func cpuSections(_ r: ResourceReading) -> [MetricSection] {
        let byType: [(CPUCoreType, String)] = [(.performance, "CPU Performance"),
                                               (.efficiency, "CPU Efficiency")]
        return byType.compactMap { type, title in
            let cores = r.cpuCores.filter { $0.type == type }.sorted { $0.index < $1.index }
            guard !cores.isEmpty else { return nil }
            let avg = cores.map(\.busyPercent).reduce(0, +) / Double(cores.count)
            return MetricSection(
                id: "cpu-\(type.rawValue)",
                title: title,
                badge: MetricBadge(text: "\(Int(avg))%", color: Self.loadColor(avg)),
                rows: cores.map { core in
                    let defaultLabel = core.type == .performance ? "P-Core \(core.index)" : "E-Core \(core.index)"
                    let renameKey = MetricKey.cpuCoreUsage(core.index)
                    return MetricRow(
                        id: "cpu-\(core.index)",
                        label: coordinator.metricNames.displayName(for: renameKey, default: defaultLabel),
                        value: "\(Int(core.busyPercent))%",
                        color: Self.loadColor(core.busyPercent),
                        searchTerms: ["CPU", "ядро", "core", title, defaultLabel],
                        renameKey: renameKey,
                        defaultLabel: defaultLabel,
                    )
                },
            )
        }
    }

    // MARK: - GPU

    private func gpuSection(_ gpu: GPUStats) -> MetricSection {
        var rows: [MetricRow] = [
            MetricRow(id: "gpu-usage",
                      label: coordinator.metricNames.displayName(for: MetricKey.gpuUsage, default: "Загрузка"),
                      value: "\(Int(gpu.utilizationPercent))%",
                      color: Self.loadColor(gpu.utilizationPercent),
                      searchTerms: ["GPU", "загрузка", "usage"],
                      renameKey: MetricKey.gpuUsage, defaultLabel: "Загрузка"),
        ]
        if gpu.memoryTotal > 0 {
            rows.append(MetricRow(
                id: "gpu-mem",
                label: coordinator.metricNames.displayName(for: MetricKey.gpuMemory, default: "Память"),
                value: "\(Self.bytes(gpu.memoryUsed)) / \(Self.bytes(gpu.memoryTotal))",
                color: .secondary,
                searchTerms: ["GPU", "память", "memory"],
                renameKey: MetricKey.gpuMemory, defaultLabel: "Память",
            ))
        }
        return MetricSection(id: "gpu", title: "GPU", rows: rows)
    }

    // MARK: - RAM

    private func memorySection(_ m: MemoryStats) -> MetricSection {
        let rows: [MetricRow] = [
            row("mem-used", "Использовано", Self.bytes(m.used), MetricKey.memoryUsed),
            row("mem-wired", "Wired", Self.bytes(m.wired), MetricKey.memoryWired),
            row("mem-compressed", "Сжато", Self.bytes(m.compressed), MetricKey.memoryCompressed),
            row("mem-cached", "Кэш файлов", Self.bytes(m.cached), MetricKey.memoryCached),
            row("mem-total", "Всего", Self.bytes(m.total), MetricKey.memoryTotal),
            MetricRow(id: "mem-pressure",
                      label: coordinator.metricNames.displayName(for: MetricKey.memoryPressure, default: "Нагрузка на память"),
                      value: "\(Int(m.pressurePercent))%",
                      color: Self.loadColor(m.pressurePercent),
                      searchTerms: ["память", "memory", "pressure", "нагрузка"],
                      renameKey: MetricKey.memoryPressure, defaultLabel: "Нагрузка на память"),
        ]
        return MetricSection(
            id: "memory", title: "Оперативная память",
            badge: MetricBadge(text: "\(Int(m.pressurePercent))%",
                               color: Self.loadColor(m.pressurePercent)),
            rows: rows,
        )
    }

    private func row(_ id: String, _ label: String, _ value: String, _ renameKey: String) -> MetricRow {
        let custom = coordinator.metricNames.displayName(for: renameKey, default: label)
        return MetricRow(id: id, label: custom, value: value, color: .secondary,
                         searchTerms: [label, custom, "память", "memory"],
                         renameKey: renameKey, defaultLabel: label)
    }

    // MARK: - Disk IO

    private func diskSection(_ disks: [DiskIORate]) -> MetricSection? {
        guard !disks.isEmpty else { return nil }
        return MetricSection(
            id: "disk", title: "Дисковый ввод-вывод",
            rows: disks.sorted { $0.name < $1.name }.map { d in
                let renameKey = "disk.\(d.name)"
                return MetricRow(
                    id: "disk-\(d.name)",
                    label: coordinator.metricNames.displayName(for: renameKey, default: d.name),
                    value: "↓ \(Self.rate(d.readBytesPerSec))  ↑ \(Self.rate(d.writeBytesPerSec))",
                    color: .secondary,
                    searchTerms: [d.name, "диск", "disk", "io"],
                    renameKey: renameKey, defaultLabel: d.name,
                )
            },
        )
    }

    // MARK: - Formatters

    private static func loadColor(_ pct: Double) -> Color {
        switch pct {
        case ..<60: return .green
        case ..<85: return .orange
        default: return .red
        }
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private static func rate(_ bytesPerSec: Double) -> String {
        let v = Int64(max(0, bytesPerSec))
        return ByteCountFormatter.string(fromByteCount: v, countStyle: .file) + "/с"
    }
}
