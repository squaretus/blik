import BlikCore
import Foundation

class FanController {
    private let dataSource: FanDataSource
    private let interval: Double
    private let terminal = Terminal()
    private var state: AppState

    init(dataSource: FanDataSource, interval: Double) {
        self.dataSource = dataSource
        self.interval = interval
        self.state = AppState(
            fans: [],
            sensors: [],
            currentPreset: 0,
            isRunning: true,
            lastError: nil,
            readOnlyMode: dataSource.isReadOnly
        )
    }

    func run() throws {
        state.fans = try dataSource.readAllFans()
        state.sensors = try dataSource.readAllSensors()
        Logger.log("Начальные данные: \(state.fans.count) вент., \(state.sensors.count) сенсоров")

        dataSource.onStartup(state: &state)

        terminal.enterAltScreen()
        terminal.enableRawMode()
        terminal.hideCursor()
        terminal.clearScreen()

        defer { cleanup() }

        var lastPoll = Date()

        while state.isRunning {
            if SignalHandler.shouldTerminate {
                state.isRunning = false
                break
            }

            let key = KeyboardInput.readKey()
            if case .none = key {} else {
                Logger.log("Key: \(key)")
            }
            handleKey(key)

            let now = Date()
            if now.timeIntervalSince(lastPoll) >= interval {
                refreshData()
                lastPoll = now
            }

            DashboardView.render(state: state, terminal: terminal)

            usleep(Constants.pollIntervalMicroseconds)
        }
    }

    private func cleanup() {
        dataSource.restoreAutoMode(fanCount: state.fans.count)
        terminal.showCursor()
        terminal.disableRawMode()
        terminal.leaveAltScreen()
        Logger.log("Cleanup завершён")
        Logger.close()
        print("blik: управление вентиляторами восстановлено в автоматический режим.")
    }

    // MARK: - Input Handling

    private func handleKey(_ key: KeyEvent) {
        switch key {
        case .quit:
            state.isRunning = false

        case .preset(let percentage):
            applyPreset(percentage: percentage)

        case .up, .pageUp:
            state.otherSensorsScrollOffset = max(0, state.otherSensorsScrollOffset - 1)

        case .down, .pageDown:
            let otherCount = state.sensors.filter { $0.group == .other }.count
            let maxOffset = max(0, otherCount - state.maxVisibleOtherSensors)
            state.otherSensorsScrollOffset = min(maxOffset, state.otherSensorsScrollOffset + 1)

        case .none:
            break
        }
    }

    private func applyPreset(percentage: Int) {
        guard !dataSource.isReadOnly else {
            state.lastError = "Режим только для чтения"
            return
        }

        state.lastError = nil

        // Сохраняем оригинальные fans ДО обновления state (writer проверяет isForced)
        let originalFans = state.fans

        // Мгновенно обновляем UI до блокирующей операции
        state.currentPreset = percentage
        if percentage == 0 {
            for i in 0..<state.fans.count {
                state.fans[i].isForced = false
            }
        } else {
            let fraction = Double(percentage) / 100.0
            for i in 0..<state.fans.count {
                let rpm = state.fans[i].minimumSpeed + (state.fans[i].maximumSpeed - state.fans[i].minimumSpeed) * fraction
                state.fans[i].targetSpeed = rpm
                state.fans[i].isForced = true
            }

            // Показываем уведомление о разблокировке если нужно
            if dataSource.needsUnlockNotification {
                state.isUnlocking = true
                DashboardView.render(state: state, terminal: terminal)
            }
        }

        do {
            try dataSource.applyPreset(percentage: percentage, fans: originalFans)
            state.isUnlocking = false
            Logger.log("applyPreset: \(percentage)%")
        } catch {
            state.isUnlocking = false
            state.lastError = error.localizedDescription
            Logger.log("applyPreset error: \(error)")
        }
    }

    // MARK: - Data Refresh

    private func refreshData() {
        if let fans = try? dataSource.readAllFans() {
            dataSource.mergeFanData(newFans: fans, into: &state.fans, currentPreset: state.currentPreset)
        }

        if let sensors = try? dataSource.readAllSensors() {
            state.sensors = sensors
        }
    }
}
