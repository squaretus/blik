import Foundation
import BlikCore

/// Клиент для взаимодействия с привилегированным XPC-хелпером blik.
/// Предоставляет как асинхронные (через reply), так и синхронные обертки для CLI.
public class BlikXPCClient {
    private var connection: NSXPCConnection?
    private let lock = NSLock()

    public init() {}

    // MARK: - Connection

    /// Создает и настраивает XPC-соединение с привилегированным хелпером.
    public func connect() {
        lock.lock()
        defer { lock.unlock() }

        let conn = NSXPCConnection(
            machServiceName: BlikXPCConstants.machServiceName,
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: BlikHelperProtocol.self)

        conn.invalidationHandler = { [weak self] in
            self?.lock.lock()
            self?.connection = nil
            self?.lock.unlock()
        }

        conn.interruptionHandler = { [weak self] in
            self?.lock.lock()
            self?.connection = nil
            self?.lock.unlock()
        }

        conn.resume()
        connection = conn
    }

    /// Создает XPC-соединение и проверяет доступность хелпера через ping.
    /// Возвращает true если хелпер доступен и отвечает.
    public func connectAndVerify() -> Bool {
        connect()

        guard let helper = proxy() else { return false }

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        helper.getHelperVersion { _ in
            success = true
            semaphore.signal()
        }

        let timeout = semaphore.wait(timeout: .now() + 2.0)
        if timeout == .timedOut || !success {
            disconnect()
            return false
        }
        return true
    }

    /// Закрывает XPC-соединение.
    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }

        connection?.invalidate()
        connection = nil
    }

    /// Возвращает true, если XPC-соединение установлено.
    public var isConnected: Bool {
        lock.lock()
        let result = connection != nil
        lock.unlock()
        return result
    }

    /// Возвращает proxy-объект для асинхронных вызовов к хелперу.
    /// Возвращает nil если соединение не установлено.
    public func helper() -> BlikHelperProtocol? {
        return proxy()
    }

    // MARK: - Private helpers

    private func proxy() -> BlikHelperProtocol? {
        lock.lock()
        let conn = connection
        lock.unlock()

        return conn?.remoteObjectProxyWithErrorHandler { error in
            NSLog("BlikXPCClient: remote object proxy error: \(error)")
        } as? BlikHelperProtocol
    }

    /// Generic sync wrapper для XPC-методов, возвращающих Decodable данные.
    private func callSync<T: Decodable>(_ type: T.Type, timeout: DispatchTime = .distantFuture,
        _ body: (BlikHelperProtocol, @escaping (Data?, String?) -> Void) -> Void) -> T? {
        guard let helper = proxy() else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        body(helper) { data, errorString in
            defer { semaphore.signal() }
            guard errorString == nil, let data else { return }
            result = try? JSONDecoder().decode(T.self, from: data)
        }
        if semaphore.wait(timeout: timeout) == .timedOut { return nil }
        return result
    }

    /// Generic sync wrapper для XPC-методов, возвращающих String? ошибку.
    private func callErrorSync(timeout: DispatchTime = .distantFuture,
        _ body: (BlikHelperProtocol, @escaping (String?) -> Void) -> Void) -> String? {
        guard let helper = proxy() else { return "XPC connection not established" }
        let semaphore = DispatchSemaphore(value: 0)
        var result: String? = "XPC call did not complete"
        body(helper) { errorString in
            result = errorString
            semaphore.signal()
        }
        if semaphore.wait(timeout: timeout) == .timedOut { return "XPC call timed out" }
        return result
    }

    // MARK: - Synchronous wrappers (for CLI)

    /// Читает информацию о всех кулерах через XPC-хелпер.
    /// Возвращает nil при ошибке соединения или декодирования.
    public func readAllFansSync() -> [FanInfo]? {
        callSync([FanInfo].self) { $0.readAllFans(reply: $1) }
    }

    /// Читает информацию о всех сенсорах через XPC-хелпер.
    /// Возвращает nil при ошибке соединения или декодирования.
    public func readAllSensorsSync() -> [SensorInfo]? {
        callSync([SensorInfo].self) { $0.readAllSensors(reply: $1) }
    }

    /// Устанавливает пресет скорости для всех кулеров.
    /// Возвращает nil при успехе, строку ошибки при неудаче.
    public func setFanSpeedPresetSync(percentage: Int) -> String? {
        callErrorSync { $0.setFanSpeedPreset(percentage: percentage, reply: $1) }
    }

    /// Восстанавливает автоматический режим управления кулерами.
    /// Возвращает nil при успехе, строку ошибки при неудаче.
    public func restoreAutoModeSync() -> String? {
        callErrorSync { $0.restoreAutoMode(reply: $1) }
    }

    /// Проверяет наличие обновления через XPC-хелпер (из кэша daemon).
    /// Возвращает UpdateInfo или nil при ошибке.
    public func checkForUpdateSync() -> UpdateInfo? {
        callSync(UpdateInfo.self, timeout: .now() + 5.0) { $0.checkForUpdate(reply: $1) }
    }

    /// Проверяет наличие обновления через XPC-хелпер (всегда запрашивает GitHub).
    /// Используется для ручной проверки.
    public func checkForUpdateForcedSync() -> UpdateInfo? {
        callSync(UpdateInfo.self, timeout: .now() + 10.0) { $0.checkForUpdateForced(reply: $1) }
    }

    /// Читает сырой снимок системных ресурсов через XPC-хелпер.
    /// Возвращает nil при ошибке соединения или декодирования.
    public func readResourcesSync() -> ResourceSnapshot? {
        callSync(ResourceSnapshot.self) { $0.readResources(reply: $1) }
    }

    /// Запускает обновление через XPC-хелпер.
    /// Возвращает nil при успехе (обновление начато), строку ошибки при неудаче.
    public func performUpdateSync() -> String? {
        callErrorSync { $0.performUpdate(reply: $1) }
    }

    /// Полное удаление blik: восстановление авто-режима, удаление файлов и сервисов.
    /// Возвращает nil при успехе, строку ошибки при неудаче.
    public func uninstallAllSync() -> String? {
        callErrorSync { $0.uninstallAll(reply: $1) }
    }

    // MARK: - History

    /// Запрашивает локальную историю метрик через XPC-хелпер.
    /// Возвращает `HistoryQueryResponse` или nil при ошибке/таймауте (10 с).
    /// Все чтения истории идут ТОЛЬКО через XPC — root-owned WAL-БД
    /// нечитаема напрямую из user-процессов.
    public func queryHistorySync(_ request: HistoryQueryRequest) -> HistoryQueryResponse? {
        guard let payload = try? JSONEncoder().encode(request) else { return nil }
        return callSync(HistoryQueryResponse.self, timeout: .now() + 10.0) {
            $0.queryHistory(request: payload, reply: $1)
        }
    }

    /// Список известных истории имён метрик. Возвращает nil при ошибке/таймауте (10 с).
    public func listHistoryMetricsSync() -> [String]? {
        callSync([String].self, timeout: .now() + 10.0) { $0.listHistoryMetrics(reply: $1) }
    }

}
