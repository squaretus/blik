import BlikCore
import BlikXPC
import Foundation

/// Источник данных через XPC daemon (не требует sudo).
final class XPCDataSource: FanDataSource {
    private let xpcClient: BlikXPCClient

    init(xpcClient: BlikXPCClient) {
        self.xpcClient = xpcClient
    }

    var isReadOnly: Bool { false }

    var needsUnlockNotification: Bool { false }

    func readAllFans() throws -> [FanInfo] {
        guard let fans = xpcClient.readAllFansSync() else {
            throw XPCDataSourceError.readFailed("fans")
        }
        return fans
    }

    func readAllSensors() throws -> [SensorInfo] {
        guard let sensors = xpcClient.readAllSensorsSync() else {
            throw XPCDataSourceError.readFailed("sensors")
        }
        return sensors
    }

    func applyPreset(percentage: Int, fans: [FanInfo]) throws {
        if let error = xpcClient.setFanSpeedPresetSync(percentage: percentage) {
            throw XPCDataSourceError.presetFailed(error)
        }
    }

    func restoreAutoMode(fanCount: Int) {
        let _ = xpcClient.restoreAutoModeSync()
        xpcClient.disconnect()
    }

    func onStartup(state: inout AppState) {
        if let updateInfo = xpcClient.checkForUpdateSync(), updateInfo.isNewer {
            state.updateAvailable = updateInfo.latestVersion
            Logger.log("XPC: доступно обновление v\(updateInfo.latestVersion)")
        }

    }

    func mergeFanData(newFans: [FanInfo], into currentFans: inout [FanInfo], currentPreset: Int) {
        for (i, newFan) in newFans.enumerated() {
            guard i < currentFans.count else { continue }
            currentFans[i].actualSpeed = newFan.actualSpeed
            currentFans[i].minimumSpeed = newFan.minimumSpeed
            currentFans[i].maximumSpeed = newFan.maximumSpeed

            // При ручном режиме — daemon сам reinforce, не трогаем target/isForced
            if currentPreset == 0 {
                currentFans[i].targetSpeed = newFan.targetSpeed
                currentFans[i].isForced = newFan.isForced
            }
        }

        // Если количество вентиляторов изменилось
        if currentFans.count != newFans.count {
            currentFans = newFans
        }
    }
}

private enum XPCDataSourceError: LocalizedError {
    case readFailed(String)
    case presetFailed(String)

    var errorDescription: String? {
        switch self {
        case .readFailed(let what): return "XPC: не удалось прочитать \(what)"
        case .presetFailed(let message): return message
        }
    }
}
