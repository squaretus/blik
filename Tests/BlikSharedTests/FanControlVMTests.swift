import XCTest
import BlikCore
@testable import BlikShared

/// Тесты watchdog-таймаута `isUnlocking` в `FanControlVM`.
///
/// Контракт: `isUnlocking` (спиннер «Разблокировка…») снимается либо reply'ем
/// `setFanSpeedPreset`, либо watchdog-таймаутом — никогда не висит вечно
/// (иначе спиннер удерживает display-cycle активным).
@MainActor
final class FanControlVMTests: XCTestCase {

    private func makeVM(helper: MockHelper, unlockTimeout: Duration) -> FanControlVM {
        let runtime = BlikRuntime(xpcClient: MockXPCClient(helper: helper))
        return FanControlVM(runtime: runtime, settings: AppSettingsVM(), unlockTimeout: unlockTimeout)
    }

    /// Потерянный XPC-reply: watchdog обязан снять `isUnlocking` по таймауту.
    func testUnlockWatchdogClearsFlagWhenReplyLost() async throws {
        let helper = MockHelper()
        helper.replyToPreset = false // reply не придёт
        let vm = makeVM(helper: helper, unlockTimeout: .milliseconds(150))

        vm.setSpeedPreset(percentage: 50)
        XCTAssertTrue(vm.isUnlocking, "isUnlocking взводится сразу для мгновенного UI feedback")

        try await Task.sleep(for: .milliseconds(450))
        XCTAssertFalse(vm.isUnlocking, "watchdog должен снять isUnlocking при потерянном reply")
    }

    /// Нормальный reply снимает `isUnlocking` сразу, не дожидаясь watchdog.
    func testUnlockClearedImmediatelyOnReply() async throws {
        let helper = MockHelper()
        helper.replyToPreset = true
        helper.presetError = nil
        let vm = makeVM(helper: helper, unlockTimeout: .seconds(30))

        vm.setSpeedPreset(percentage: 50)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(vm.isUnlocking, "reply должен снять isUnlocking задолго до watchdog")
    }

    /// menu-bar проектор отражает квантованные значения из данных. `MenuBarLabel`
    /// читает их вместо сырых fans/sensors → реже ре-рендерится.
    func testMenuProjectionReflectsData() async throws {
        let helper = MockHelper()
        helper.replyToReads = true
        helper.fans = [
            FanInfo(id: 0, actualSpeed: 2000, minimumSpeed: 1000, maximumSpeed: 5000, targetSpeed: 2000, isForced: false),
            FanInfo(id: 1, actualSpeed: 3000, minimumSpeed: 1000, maximumSpeed: 5000, targetSpeed: 3000, isForced: false),
        ]
        helper.sensors = [
            SensorInfo(key: "TC0P", name: "CPU", group: .cpuCores, temperature: 48),
            SensorInfo(key: "TG0P", name: "GPU", group: .gpuCores, temperature: 52),
        ]
        let vm = makeVM(helper: helper, unlockTimeout: .seconds(30))

        // polling loop (≈1с) → refreshData → applyUpdate → проектор.
        try await Task.sleep(for: .milliseconds(1300))
        XCTAssertEqual(vm.menuFan0RPM, 2000)
        XCTAssertEqual(vm.menuFan1RPM, 3000)
        XCTAssertEqual(vm.menuChipTemp, 50, "среднее (48+52)/2")
    }
}
