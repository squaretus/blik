import XCTest
@testable import BlikShared

/// Тесты инлайн-переименования датчиков (`MetricNameStore`). Хранилище инжектится
/// временным suite'ом, чтобы не задевать общий `com.blik.shared`.
@MainActor
final class MetricNameStoreTests: XCTestCase {

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

    func test_display_name_returns_default_when_unset() {
        let store = MetricNameStore(defaults: defaults)
        XCTAssertEqual(store.displayName(for: "temp.X", default: "Датчик X"), "Датчик X")
    }

    func test_set_name_overrides_default() {
        let store = MetricNameStore(defaults: defaults)
        store.setName("CPU крышка", for: "temp.X")
        XCTAssertEqual(store.displayName(for: "temp.X", default: "Датчик X"), "CPU крышка")
    }

    func test_set_name_trims_whitespace() {
        let store = MetricNameStore(defaults: defaults)
        store.setName("  Мой датчик  ", for: "temp.X")
        XCTAssertEqual(store.displayName(for: "temp.X", default: "def"), "Мой датчик")
    }

    func test_empty_name_resets_to_default() {
        let store = MetricNameStore(defaults: defaults)
        store.setName("Custom", for: "temp.X")
        store.setName("   ", for: "temp.X")
        XCTAssertEqual(store.displayName(for: "temp.X", default: "def"), "def")
        XCTAssertNil(store.names["temp.X"])
    }

    func test_nil_name_resets_to_default() {
        let store = MetricNameStore(defaults: defaults)
        store.setName("Custom", for: "temp.X")
        store.setName(nil, for: "temp.X")
        XCTAssertEqual(store.displayName(for: "temp.X", default: "def"), "def")
    }

    func test_names_persist_across_store_instances() {
        let first = MetricNameStore(defaults: defaults)
        first.setName("Сохранённое", for: "temp.X")

        let second = MetricNameStore(defaults: defaults)
        XCTAssertEqual(second.displayName(for: "temp.X", default: "def"), "Сохранённое")
    }

    func test_reset_persists_removal() {
        let first = MetricNameStore(defaults: defaults)
        first.setName("Custom", for: "temp.X")
        first.setName("", for: "temp.X")

        let second = MetricNameStore(defaults: defaults)
        XCTAssertEqual(second.displayName(for: "temp.X", default: "def"), "def")
    }
}
