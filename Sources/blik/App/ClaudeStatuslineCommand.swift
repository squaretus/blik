import ArgumentParser
import BlikCore
import BlikXPC
import Foundation

/// Разовый вывод таблицы метрик для statusLine Claude Code.
/// Daemon недоступен → пустой stdout и exit 0: статус-бар просто без метрик.
struct ClaudeStatusline: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-statusline",
        abstract: "Таблица метрик (температуры, RAM/VRAM) для статус-бара Claude Code"
    )

    func run() throws {
        let client = BlikXPCClient()
        guard client.connectAndVerify() else { return }
        defer { client.disconnect() }

        let sensors = client.readAllSensorsSync() ?? []
        let snapshot = client.readResourcesSync()

        let metrics = StatuslineRenderer.buildMetrics(sensors: sensors, snapshot: snapshot)
        guard !metrics.isEmpty else { return }
        print(StatuslineRenderer.render(metrics))
    }
}
