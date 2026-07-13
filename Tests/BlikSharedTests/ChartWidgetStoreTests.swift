import XCTest
@testable import BlikShared

/// Тесты хранилища конфигураций виджетов графиков (`ChartWidgetStore`).
/// Набор виджетов фиксирован; store хранит только правки поверх дефолтов.
@MainActor
final class ChartWidgetStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_fresh_store_returns_default_widget_set() {
        let store = ChartWidgetStore(defaults: defaults)
        XCTAssertEqual(store.widgets.map(\.id), ChartWidgetConfig.defaults.map(\.id))
        XCTAssertEqual(store.widgets, ChartWidgetConfig.defaults)
    }

    func test_update_persists_edits_across_instances() {
        let store = ChartWidgetStore(defaults: defaults)
        guard var gpu = store.widgets.first(where: { $0.id == "gpu" }) else {
            return XCTFail("нет дефолтного виджета gpu")
        }
        gpu.warnThreshold = 60
        gpu.critThreshold = 85
        gpu.enabledMetrics = []
        store.update(gpu)

        let reopened = ChartWidgetStore(defaults: defaults)
        let saved = reopened.widgets.first { $0.id == "gpu" }
        XCTAssertEqual(saved?.warnThreshold, 60)
        XCTAssertEqual(saved?.critThreshold, 85)
        XCTAssertEqual(saved?.enabledMetrics, [])
    }

    func test_update_ignores_unknown_id() {
        let store = ChartWidgetStore(defaults: defaults)
        let ghost = ChartWidgetConfig(id: "ghost", kind: .gauge, title: "X", metrics: ["m"])
        store.update(ghost)
        XCTAssertEqual(store.widgets.map(\.id), ChartWidgetConfig.defaults.map(\.id))
        XCTAssertFalse(store.widgets.contains { $0.id == "ghost" })
    }

    func test_unknown_stored_ids_are_discarded_on_load() throws {
        // Сохраняем в suite смесь известного override и неизвестного id.
        var gpu = ChartWidgetConfig.defaults.first { $0.id == "gpu" }!
        gpu.warnThreshold = 51
        let ghost = ChartWidgetConfig(id: "ghost", kind: .gauge, title: "X", metrics: ["m"])
        let data = try JSONEncoder().encode([gpu, ghost])
        defaults.set(data, forKey: "chartWidgets.v1")

        let store = ChartWidgetStore(defaults: defaults)
        XCTAssertEqual(store.widgets.count, ChartWidgetConfig.defaults.count)
        XCTAssertFalse(store.widgets.contains { $0.id == "ghost" }, "неизвестный id отброшен")
        XCTAssertEqual(store.widgets.first { $0.id == "gpu" }?.warnThreshold, 51,
                       "известный override применён")
    }

    func test_reset_restores_default_and_persists() {
        let store = ChartWidgetStore(defaults: defaults)
        var gpu = store.widgets.first { $0.id == "gpu" }!
        gpu.warnThreshold = 5
        store.update(gpu)

        store.reset(id: "gpu")
        let defaultGpu = ChartWidgetConfig.defaults.first { $0.id == "gpu" }!
        XCTAssertEqual(store.widgets.first { $0.id == "gpu" }, defaultGpu)

        let reopened = ChartWidgetStore(defaults: defaults)
        XCTAssertEqual(reopened.widgets.first { $0.id == "gpu" }, defaultGpu)
    }
}
