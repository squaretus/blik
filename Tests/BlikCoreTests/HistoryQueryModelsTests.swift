import XCTest
@testable import BlikCore

/// Codable-roundtrip XPC-контракта истории (сериализуется в JSON `Data`).
final class HistoryQueryModelsTests: XCTestCase {

    private func roundtrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func test_request_roundtrip_preserves_fields() throws {
        let req = HistoryQueryRequest(
            metrics: ["temp.X", "cpu.usage.overall"],
            from: Date(timeIntervalSince1970: 1_700_000_000),
            to: Date(timeIntervalSince1970: 1_700_003_600),
            maxPointsPerSeries: 500)
        XCTAssertEqual(try roundtrip(req), req)
    }

    func test_request_default_max_points() {
        let req = HistoryQueryRequest(metrics: ["m"],
                                      from: Date(timeIntervalSince1970: 0),
                                      to: Date(timeIntervalSince1970: 60))
        XCTAssertEqual(req.maxPointsPerSeries, HistoryQueryRequest.defaultMaxPoints)
    }

    func test_point_roundtrip() throws {
        let p = HistoryPoint(ts: Date(timeIntervalSince1970: 1_700_000_040), min: 1, avg: 2.5, max: 9)
        XCTAssertEqual(try roundtrip(p), p)
    }

    func test_response_roundtrip_with_series_and_points() throws {
        let resp = HistoryQueryResponse(
            series: [
                HistorySeries(metric: "m1", points: [
                    HistoryPoint(ts: Date(timeIntervalSince1970: 0), min: 0, avg: 1, max: 2),
                    HistoryPoint(ts: Date(timeIntervalSince1970: 60), min: 3, avg: 4, max: 5),
                ]),
                HistorySeries(metric: "m2", points: []),
            ],
            bucketSeconds: 60)
        XCTAssertEqual(try roundtrip(resp), resp)
    }
}
