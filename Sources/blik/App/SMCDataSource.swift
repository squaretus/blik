import BlikCore

/// Источник данных через прямой SMC-доступ (требует sudo).
final class SMCDataSource: FanDataSource {
    private let reader: SMCReader
    private let writer: SMCWriter?

    init(reader: SMCReader, writer: SMCWriter?) {
        self.reader = reader
        self.writer = writer
    }

    var isReadOnly: Bool { writer == nil }

    var needsUnlockNotification: Bool {
        writer?.modifiedFanIds.isEmpty == true
    }

    func readAllFans() throws -> [FanInfo] {
        try reader.readAllFans()
    }

    func readAllSensors() throws -> [SensorInfo] {
        try reader.readAllSensors()
    }

    func applyPreset(percentage: Int, fans: [FanInfo]) throws {
        guard let writer else { return }
        try writer.setAllFansSpeed(percentage: percentage, fans: fans)
    }

    func restoreAutoMode(fanCount: Int) {
        writer?.restoreAutoMode(fanCount: fanCount)
    }

    func onStartup(state: inout AppState) {
        if let writer {
            writer.restoreAutoMode(fanCount: state.fans.count)
            Logger.log("Startup: сброс всех кулеров в auto")
        }
    }

    func mergeFanData(newFans: [FanInfo], into currentFans: inout [FanInfo], currentPreset: Int) {
        for (i, newFan) in newFans.enumerated() {
            guard i < currentFans.count else { continue }
            currentFans[i].actualSpeed = newFan.actualSpeed
            currentFans[i].minimumSpeed = newFan.minimumSpeed
            currentFans[i].maximumSpeed = newFan.maximumSpeed

            if writer?.modifiedFanIds.contains(i) != true {
                currentFans[i].targetSpeed = newFan.targetSpeed
                currentFans[i].isForced = newFan.isForced
            } else {
                writer?.reinforceSpeed(fan: i, rpm: currentFans[i].targetSpeed)
            }
        }
    }
}
