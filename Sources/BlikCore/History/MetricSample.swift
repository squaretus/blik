import Foundation

/// Одна точка временного ряда одной метрики. Единица записи истории.
public struct MetricSample: Equatable, Sendable {
    public let metric: String
    public let ts: Date
    public let value: Double

    public init(metric: String, ts: Date, value: Double) {
        self.metric = metric
        self.ts = ts
        self.value = value
    }
}
