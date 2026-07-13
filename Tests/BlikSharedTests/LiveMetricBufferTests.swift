import XCTest
@testable import BlikShared

/// Тесты кольцевого буфера live-точек (`LiveMetricBuffer`) — чистая структура.
final class LiveMetricBufferTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

    func test_append_keeps_chronological_order() {
        var buf = LiveMetricBuffer(capacity: 10)
        buf.append(ts: at(0), value: 1)
        buf.append(ts: at(1), value: 2)
        buf.append(ts: at(2), value: 3)
        XCTAssertEqual(buf.points.map(\.value), [1, 2, 3])
    }

    func test_capacity_evicts_oldest_points() {
        var buf = LiveMetricBuffer(capacity: 3)
        for i in 0..<5 {
            buf.append(ts: at(Double(i)), value: Double(i))
        }
        XCTAssertEqual(buf.points.count, 3)
        XCTAssertEqual(buf.points.map(\.value), [2, 3, 4], "остаются три самые свежие точки")
    }

    func test_capacity_floor_is_one() {
        var buf = LiveMetricBuffer(capacity: 0)
        buf.append(ts: at(0), value: 1)
        buf.append(ts: at(1), value: 2)
        XCTAssertEqual(buf.points.map(\.value), [2], "минимальная ёмкость — 1")
    }

    func test_trim_removes_points_before_cutoff() {
        var buf = LiveMetricBuffer(capacity: 10)
        for i in 0..<5 { buf.append(ts: at(Double(i)), value: Double(i)) }
        buf.trim(before: at(2))
        XCTAssertEqual(buf.points.map(\.value), [2, 3, 4])
    }

    func test_trim_clears_all_when_all_older() {
        var buf = LiveMetricBuffer(capacity: 10)
        for i in 0..<3 { buf.append(ts: at(Double(i)), value: Double(i)) }
        buf.trim(before: at(100))
        XCTAssertTrue(buf.points.isEmpty)
    }

    func test_points_in_range_filters_inclusive() {
        var buf = LiveMetricBuffer(capacity: 10)
        for i in 0..<5 { buf.append(ts: at(Double(i)), value: Double(i)) }
        let inRange = buf.points(in: at(1)...at(3))
        XCTAssertEqual(inRange.map(\.value), [1, 2, 3])
    }

    func test_points_since_cutoff_is_inclusive() {
        var buf = LiveMetricBuffer(capacity: 10)
        for i in 0..<5 { buf.append(ts: at(Double(i)), value: Double(i)) }
        let recent = buf.points(since: at(3))
        XCTAssertEqual(recent.map(\.value), [3, 4])
    }
}
