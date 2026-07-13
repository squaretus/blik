import XCTest
@testable import BlikShared

/// Тест hard-cap'а установки в `UpdateVM`.
///
/// Контракт: если за `installTimeoutSeconds` не пришёл ни reply `performUpdate`,
/// ни disconnect daemon'а — `isInstallingUpdate` снимается (спиннер «Установка…»
/// не висит вечно, вечный 3с-poll `monitorInstall` останавливается).
@MainActor
final class UpdateVMTests: XCTestCase {

    /// Зависшая установка (нет ни reply, ни disconnect): watchdog снимает флаг.
    func testInstallWatchdogClearsFlagWhenStuck() async throws {
        let helper = MockHelper()
        helper.replyToUpdate = false // performUpdate не отвечает
        // connected: true → monitorInstall не сработает по disconnect, только по таймауту.
        let runtime = BlikRuntime(xpcClient: MockXPCClient(helper: helper, connected: true))
        let vm = UpdateVM(runtime: runtime, installTimeoutSeconds: 0)

        vm.installUpdate()
        XCTAssertTrue(vm.isInstallingUpdate, "флаг взводится сразу")

        // monitorInstall спит фиксированные 3с между опросами, затем elapsed(3) >= 0 → fire.
        try await Task.sleep(for: .seconds(4))
        XCTAssertFalse(vm.isInstallingUpdate, "watchdog должен снять isInstallingUpdate при зависшей установке")
        XCTAssertNotNil(vm.manualUpdateResult, "пользователю показано сообщение об ошибке установки")
    }
}
