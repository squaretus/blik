import Foundation
import BlikCore

/// Общий модуль обновления для CLI и MenuBar.
/// Инкапсулирует логику проверки и установки обновлений через XPC.
public enum UpdateService {

    // MARK: - Result Types

    public enum CheckResult {
        case available(UpdateInfo)
        case upToDate(currentVersion: String)
        case error(String)
    }

    public enum InstallResult {
        case started
        case error(String)
    }

    // MARK: - Private Helpers

    private static func evaluate(_ info: UpdateInfo?) -> CheckResult {
        guard let info else { return .error("Не удалось проверить обновления") }
        return info.isNewer ? .available(info) : .upToDate(currentVersion: info.currentVersion)
    }

    private static func handleUpdateReply(data: Data?, error: String?, completion: @escaping (CheckResult) -> Void) {
        if let error {
            completion(.error(error))
            return
        }
        guard let data,
              let info = try? JSONDecoder().decode(UpdateInfo.self, from: data) else {
            completion(.error("Не удалось декодировать данные обновления"))
            return
        }
        completion(info.isNewer ? .available(info) : .upToDate(currentVersion: info.currentVersion))
    }

    // MARK: - Sync API (CLI)

    /// Проверяет наличие обновления (синхронно, из кэша daemon).
    public static func check(client: BlikXPCClient) -> CheckResult {
        evaluate(client.checkForUpdateSync())
    }

    /// Проверяет наличие обновления (синхронно, всегда запрашивает GitHub).
    public static func checkForced(client: BlikXPCClient) -> CheckResult {
        evaluate(client.checkForUpdateForcedSync())
    }

    /// Проверяет и устанавливает обновление (синхронно, всегда запрашивает GitHub).
    public static func checkAndInstall(client: BlikXPCClient) -> CheckResult {
        let result = checkForced(client: client)
        guard case .available(let info) = result else { return result }

        if let error = client.performUpdateSync() {
            return .error("Ошибка обновления: \(error)")
        }
        return .available(info)
    }

    // MARK: - Async API (MenuBar)

    /// Проверяет наличие обновления (асинхронно, из кэша daemon).
    public static func check(helper: BlikHelperProtocol, completion: @escaping (CheckResult) -> Void) {
        helper.checkForUpdate { data, error in
            handleUpdateReply(data: data, error: error, completion: completion)
        }
    }

    /// Проверяет наличие обновления (асинхронно, всегда запрашивает GitHub).
    public static func checkForced(helper: BlikHelperProtocol, completion: @escaping (CheckResult) -> Void) {
        helper.checkForUpdateForced { data, error in
            handleUpdateReply(data: data, error: error, completion: completion)
        }
    }

    /// Запускает установку обновления (асинхронно через XPC proxy).
    public static func install(helper: BlikHelperProtocol, completion: @escaping (InstallResult) -> Void) {
        helper.performUpdate { error in
            if let error {
                completion(.error(error))
            } else {
                completion(.started)
            }
        }
    }
}
