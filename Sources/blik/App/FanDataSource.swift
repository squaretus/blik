import BlikCore

/// Абстракция источника данных для CLI-контроллера вентиляторов.
/// Две реализации: SMCDataSource (прямой доступ через IOKit) и XPCDataSource (через XPC daemon).
protocol FanDataSource {
    func readAllFans() throws -> [FanInfo]
    func readAllSensors() throws -> [SensorInfo]

    /// Применяет пресет скорости (0 = авто). fans — текущее состояние до мутации UI.
    func applyPreset(percentage: Int, fans: [FanInfo]) throws

    func restoreAutoMode(fanCount: Int)

    /// Вызывается после начального чтения данных.
    func onStartup(state: inout AppState)

    /// Объединяет свежие данные кулеров с текущим state.
    func mergeFanData(newFans: [FanInfo], into currentFans: inout [FanInfo], currentPreset: Int)

    var isReadOnly: Bool { get }

    /// Нужно ли показывать уведомление "Разблокировка управления..." при первом переключении в ручной режим.
    var needsUnlockNotification: Bool { get }
}
