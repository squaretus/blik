import XCTest
@testable import BlikCore

final class CPUTopologyTests: XCTestCase {

    func test_device_tree_entries_map_E_and_P() {
        // logical-cpu-id не обязан совпадать с порядком обхода — маппим по id.
        let topo = CPUTopology.from(entries: [
            (logicalId: 0, clusterType: "E"),
            (logicalId: 1, clusterType: "E"),
            (logicalId: 2, clusterType: "P"),
            (logicalId: 3, clusterType: "P"),
        ])
        XCTAssertEqual(topo.type(for: 0), .efficiency)
        XCTAssertEqual(topo.type(for: 1), .efficiency)
        XCTAssertEqual(topo.type(for: 2), .performance)
        XCTAssertEqual(topo.type(for: 3), .performance)
        XCTAssertEqual(topo.coreCount, 4)
    }

    func test_device_tree_performance_first_ordering() {
        // Обратный порядок (P-ядра с малыми id) — маппинг по cluster-type, не по позиции.
        let topo = CPUTopology.from(entries: [
            (logicalId: 0, clusterType: "P"),
            (logicalId: 1, clusterType: "P"),
            (logicalId: 2, clusterType: "E"),
        ])
        XCTAssertEqual(topo.type(for: 0), .performance)
        XCTAssertEqual(topo.type(for: 2), .efficiency)
    }

    func test_cluster_type_prefix_match_is_case_insensitive() {
        let topo = CPUTopology.from(entries: [
            (logicalId: 0, clusterType: "ECPU"),
            (logicalId: 1, clusterType: "pcpu"),
        ])
        XCTAssertEqual(topo.type(for: 0), .efficiency)
        XCTAssertEqual(topo.type(for: 1), .performance)
    }

    func test_uniform_topology_all_performance() {
        let topo = CPUTopology.uniform(logicalCount: 8)
        XCTAssertEqual(topo.coreCount, 8)
        for i in 0..<8 { XCTAssertEqual(topo.type(for: i), .performance) }
    }

    func test_unknown_index_defaults_to_performance() {
        let topo = CPUTopology.from(entries: [(logicalId: 0, clusterType: "E")])
        // Индекс вне карты — безопасный дефолт performance (не прячем нагрузку в E).
        XCTAssertEqual(topo.type(for: 99), .performance)
    }
}
