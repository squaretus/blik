import ArgumentParser
import BlikCore
import BlikXPC
import Foundation

/// Разовый вывод одной строки метрик для statusLine Claude Code.
/// Daemon недоступен → пустой stdout и exit 0: статус-бар просто без метрик.
struct ClaudeStatusline: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-statusline",
        abstract: "Одна строка метрик (температуры, RAM/VRAM) для статус-бара Claude Code"
    )

    func run() throws {
        let client = BlikXPCClient()
        guard client.connectAndVerify() else { return }
        defer { client.disconnect() }

        let sensors = client.readAllSensorsSync() ?? []
        let snapshot = client.readResourcesSync()

        let now = Date()
        let history = client.queryHistorySync(HistoryQueryRequest(
            metrics: [
                MetricKey.tempPCoreAvg, MetricKey.tempECoreAvg, MetricKey.tempGPUAvg,
                MetricKey.memoryUsed, MetricKey.gpuMemoryUsed,
            ],
            from: now.addingTimeInterval(-StatuslineRenderer.historyWindow),
            to: now,
            maxPointsPerSeries: StatuslineRenderer.sparkPoints))

        let metrics = StatuslineRenderer.buildMetrics(
            sensors: sensors, snapshot: snapshot, history: history)
        guard !metrics.isEmpty else { return }
        print(StatuslineRenderer.render(metrics))
    }
}
