import Foundation

/// XPC протокол для общения с привилегированным хелпером.
/// Data параметры -- JSON-encoded [FanInfo]/[SensorInfo].
/// String? параметры ошибок -- nil означает успех.
@objc public protocol BlikHelperProtocol {
    func readAllFans(reply: @escaping (Data?, String?) -> Void)
    func readAllSensors(reply: @escaping (Data?, String?) -> Void)
    /// Объединённое чтение — StateSnapshot JSON. Один XPC-раунд вместо двух.
    func readState(reply: @escaping (Data?, String?) -> Void)
    /// Сырой снимок системных ресурсов (CPU/RAM/GPU/Disk) — ResourceSnapshot JSON.
    /// Кумулятивные счётчики; дельту в rate считает клиент.
    func readResources(reply: @escaping (Data?, String?) -> Void)
    func setFanSpeedPreset(percentage: Int, reply: @escaping (String?) -> Void)
    func restoreAutoMode(reply: @escaping (String?) -> Void)
    func getHelperVersion(reply: @escaping (String) -> Void)
    func uninstallAll(reply: @escaping (String?) -> Void)
    func checkForUpdate(reply: @escaping (Data?, String?) -> Void)
    func checkForUpdateForced(reply: @escaping (Data?, String?) -> Void)
    func performUpdate(reply: @escaping (String?) -> Void)

    /// Запрос локальной истории метрик. `request` — JSON `HistoryQueryRequest`,
    /// reply — JSON `HistoryQueryResponse` (или строка ошибки).
    func queryHistory(request: Data, reply: @escaping (Data?, String?) -> Void)
    /// Список известных истории имён метрик. reply — JSON `[String]`.
    func listHistoryMetrics(reply: @escaping (Data?, String?) -> Void)
}
