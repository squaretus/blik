import XCTest
import BlikCore
@testable import BlikShared

/// Тесты VM графиков (`ChartsVM`): режим по умолчанию, кламп диапазона ≤ 7 дней,
/// старт/стоп live-капчера при смене режима, empty-state при недоступной истории.
@MainActor
final class ChartsVMTests: XCTestCase {

    private func makeRuntime(historySupported: Bool) -> BlikRuntime {
        BlikRuntime(xpcClient: MockXPCClient(helper: MockHelper()),
                    helperSupportsHistory: historySupported)
    }

    private func makeMemory(used: UInt64) -> MemoryStats {
        MemoryStats(used: used, wired: 0, compressed: 0, cached: 0, total: 16_000, pressurePercent: 10)
    }

    // MARK: - Дефолт

    func test_default_mode_is_live() {
        let runtime = makeRuntime(historySupported: true)
        let vm = ChartsVM(runtime: runtime, settings: AppSettingsVM())
        XCTAssertEqual(vm.mode, .live)
    }

    // MARK: - Кламп ≤ 7 дней

    func test_range_clamped_to_seven_days() {
        let now = Date()
        let range = ChartTimeRange(from: now.addingTimeInterval(-30 * 86_400), to: now)
        XCTAssertLessThanOrEqual(range.span, ChartTimeRange.maxSpan + 1,
                                 "охват > 7 дней клампится в ChartTimeRange.init")

        let vm = ChartsVM(runtime: makeRuntime(historySupported: false), settings: AppSettingsVM())
        vm.setMode(.range(range))
        guard case .range(let stored) = vm.mode else { return XCTFail("ожидался .range") }
        XCTAssertLessThanOrEqual(stored.span, ChartTimeRange.maxSpan + 1)
    }

    // MARK: - Empty-state при недоступной истории

    func test_range_mode_shows_empty_state_when_helper_unavailable() {
        let vm = ChartsVM(runtime: makeRuntime(historySupported: false), settings: AppSettingsVM())
        vm.metricsToQuery = [MetricKey.memoryUsed]
        vm.setMode(.range(ChartRangePreset.h1.range()))

        XCTAssertFalse(vm.helperAvailable)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.series.isEmpty)
        XCTAssertNotNil(vm.errorMessage, "показываем сообщение вместо зависания")
    }

    // MARK: - Live-капчер: старт/стоп при смене режима

    func test_switching_mode_stops_and_resumes_live_capture() async throws {
        let runtime = makeRuntime(historySupported: true)
        let settings = AppSettingsVM()
        let fanVM = FanControlVM(runtime: runtime, settings: settings)
        let resourceVM = ResourceVM(runtime: runtime, settings: settings)
        let vm = ChartsVM(runtime: runtime, settings: settings)
        vm.attach(fan: fanVM, resource: resourceVM)

        // Детерминированный источник значения памяти (MockHelper.readResources — no-op,
        // поэтому ResourceVM не перезапишет установленное значение).
        resourceVM.resources = ResourceReading.empty(
            timestamp: Date(), memory: makeMemory(used: 5_000), gpu: nil)

        // live + visible → капчер стартует, первый тик мгновенный.
        vm.setVisible(true)
        try await Task.sleep(for: .milliseconds(150))
        let captured = vm.livePoints(for: MetricKey.memoryUsed, window: 3_600).count
        XCTAssertGreaterThan(captured, 0, "капчер наполняет буфер в live-режиме")

        // Переход в range → капчер останавливается.
        vm.setMode(.range(ChartRangePreset.m5.range()))
        try await Task.sleep(for: .milliseconds(1_300))
        let afterStop = vm.livePoints(for: MetricKey.memoryUsed, window: 3_600).count
        XCTAssertEqual(afterStop, captured, "смена режима отменяет live-task — точки не растут")

        // Возврат в live (страница видима) → капчер возобновляется.
        vm.setMode(.live)
        try await Task.sleep(for: .milliseconds(1_300))
        let afterResume = vm.livePoints(for: MetricKey.memoryUsed, window: 3_600).count
        XCTAssertGreaterThan(afterResume, afterStop, "капчер возобновлён в live-режиме")
    }

    func test_capture_does_not_run_while_hidden() async throws {
        let runtime = makeRuntime(historySupported: true)
        let settings = AppSettingsVM()
        let fanVM = FanControlVM(runtime: runtime, settings: settings)
        let resourceVM = ResourceVM(runtime: runtime, settings: settings)
        let vm = ChartsVM(runtime: runtime, settings: settings)
        vm.attach(fan: fanVM, resource: resourceVM)
        resourceVM.resources = ResourceReading.empty(
            timestamp: Date(), memory: makeMemory(used: 5_000), gpu: nil)

        // Страница не видима — капчер не стартует даже в live-режиме.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(vm.livePoints(for: MetricKey.memoryUsed, window: 3_600).count, 0)
    }
}
