import ArgumentParser
import BlikCore
import BlikXPC
import Foundation
import MCP

/// Реальный источник метрик: XPC к root-daemon'у BlikHelper.
/// Переподключается лениво — daemon мог перезапуститься между вызовами.
final class XPCMetricsSource: MCPMetricsSource {
    private let client: BlikXPCClient

    init(client: BlikXPCClient) {
        self.client = client
    }

    private func ensureConnected() -> Bool {
        client.isConnected || client.connectAndVerify()
    }

    func currentMetrics() -> CurrentMetricsPayload? {
        guard ensureConnected() else { return nil }
        guard let sensors = client.readAllSensorsSync(),
              let fans = client.readAllFansSync() else { return nil }

        // CPU% — производная: нужны два снимка с дельтой ~1 с.
        var reading: ResourceReading?
        if let first = client.readResourcesSync() {
            Thread.sleep(forTimeInterval: 1.0)
            if let second = client.readResourcesSync() {
                reading = ResourceUsageCalculator.reading(from: first, to: second)
            }
        }
        return CurrentMetricsPayload.build(sensors: sensors, fans: fans, reading: reading)
    }

    func listMetrics() -> [String]? {
        guard ensureConnected() else { return nil }
        return client.listHistoryMetricsSync()
    }

    func queryHistory(metric: String, from: Date, to: Date) -> HistoryQueryResponse? {
        guard ensureConnected() else { return nil }
        return client.queryHistorySync(HistoryQueryRequest(
            metrics: [metric], from: from, to: to))
    }

    func setFanPreset(percentage: Int) -> String? {
        guard ensureConnected() else { return "XPC-соединение с daemon недоступно" }
        return client.setFanSpeedPresetSync(percentage: percentage)
    }
}

/// MCP-сервер поверх stdio. stdout — канал протокола: никаких print().
/// Процесс живёт, пока Claude Code держит stdin открытым.
struct MCPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "MCP-сервер (stdio) с метриками и управлением кулерами для Claude Code"
    )

    func run() throws {
        let client = BlikXPCClient()
        _ = client.connectAndVerify()   // неуспех не фатален: источник переподключится
        let source = XPCMetricsSource(client: client)

        let server = Server(
            name: "blik",
            version: Constants.appVersion,
            capabilities: .init(tools: .init(listChanged: false)))

        Task {
            await server.withMethodHandler(ListTools.self) { _ in
                .init(tools: BlikMCPTools.toolList)
            }
            await server.withMethodHandler(CallTool.self) { params in
                BlikMCPTools.handle(name: params.name, arguments: params.arguments,
                                    source: source)
            }
            do {
                try await server.start(transport: StdioTransport())
                await server.waitUntilCompleted()
            } catch {
                FileHandle.standardError.write(Data("blik mcp: \(error)\n".utf8))
            }
            client.disconnect()
            Foundation.exit(0)
        }
        dispatchMain()
    }
}
