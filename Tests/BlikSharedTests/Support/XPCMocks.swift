import Foundation
import BlikCore
@testable import BlikXPC

/// Mock привилегированного хелпера для тестов VM-слоя.
///
/// По умолчанию методы НЕ вызывают reply — это эмулирует потерянный XPC-reply
/// (connection interruption), на котором проверяются watchdog-таймауты
/// `FanControlVM.isUnlocking` и `UpdateVM.isInstallingUpdate`.
final class MockHelper: NSObject, BlikHelperProtocol {

    /// Если true — `setFanSpeedPreset` синхронно вызывает reply с `presetError`.
    var replyToPreset = false
    var presetError: String?

    /// Если true — `performUpdate` синхронно вызывает reply с `updateError`.
    var replyToUpdate = false
    var updateError: String?

    /// Если true — `readAllFans`/`readAllSensors` отвечают JSON из `fans`/`sensors`.
    var replyToReads = false
    var fans: [FanInfo] = []
    var sensors: [SensorInfo] = []

    func setFanSpeedPreset(percentage: Int, reply: @escaping (String?) -> Void) {
        if replyToPreset { reply(presetError) }
    }

    func performUpdate(reply: @escaping (String?) -> Void) {
        if replyToUpdate { reply(updateError) }
    }

    // Остальные методы — no-op (reply не вызывается; вызывающий код guard'ит nil).
    func readAllFans(reply: @escaping (Data?, String?) -> Void) {
        if replyToReads, let d = try? JSONEncoder().encode(fans) { reply(d, nil) }
    }
    func readAllSensors(reply: @escaping (Data?, String?) -> Void) {
        if replyToReads, let d = try? JSONEncoder().encode(sensors) { reply(d, nil) }
    }
    func readState(reply: @escaping (Data?, String?) -> Void) {}
    func readResources(reply: @escaping (Data?, String?) -> Void) {}
    func restoreAutoMode(reply: @escaping (String?) -> Void) {}
    func getHelperVersion(reply: @escaping (String) -> Void) {}
    func uninstallAll(reply: @escaping (String?) -> Void) {}
    func checkForUpdate(reply: @escaping (Data?, String?) -> Void) {}
    func checkForUpdateForced(reply: @escaping (Data?, String?) -> Void) {}
    func queryHistory(request: Data, reply: @escaping (Data?, String?) -> Void) {}
    func listHistoryMetrics(reply: @escaping (Data?, String?) -> Void) {}
}

/// Mock XPC-клиента: отдаёт `MockHelper` вместо реального XPC-proxy и
/// контролирует `isConnected`. Подкласс возможен благодаря `@testable import BlikXPC`.
final class MockXPCClient: BlikXPCClient {
    private let mock: MockHelper
    private let connected: Bool

    init(helper: MockHelper, connected: Bool = true) {
        self.mock = helper
        self.connected = connected
        super.init()
    }

    override func helper() -> BlikHelperProtocol? { mock }
    override var isConnected: Bool { connected }
}
