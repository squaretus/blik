import Foundation

/// Кольцевой буфер live-точек одной метрики. Чистая структура без I/O —
/// наполняется `ChartsVM` на каждом тике поллинга, читается виджетами.
///
/// При переполнении `capacity` вытесняются самые старые точки.
public struct LiveMetricBuffer: Equatable, Sendable {

    /// Точка ряда: момент времени + значение.
    public struct Point: Equatable, Sendable {
        public let ts: Date
        public let value: Double
        public init(ts: Date, value: Double) {
            self.ts = ts
            self.value = value
        }
    }

    /// Ёмкость буфера (число точек). ~900 ≈ 15 минут при поллинге 1 с.
    public let capacity: Int

    /// Точки в хронологическом порядке (старые → новые).
    public private(set) var points: [Point] = []

    public init(capacity: Int = 900) {
        self.capacity = Swift.max(1, capacity)
    }

    /// Добавляет точку в конец, вытесняя самые старые при переполнении.
    public mutating func append(ts: Date, value: Double) {
        points.append(Point(ts: ts, value: value))
        if points.count > capacity {
            points.removeFirst(points.count - capacity)
        }
    }

    /// Удаляет точки старше `cutoff`.
    public mutating func trim(before cutoff: Date) {
        if let idx = points.firstIndex(where: { $0.ts >= cutoff }) {
            if idx > 0 { points.removeFirst(idx) }
        } else {
            points.removeAll(keepingCapacity: true)
        }
    }

    /// Точки, попадающие в замкнутый диапазон.
    public func points(in range: ClosedRange<Date>) -> [Point] {
        points.filter { range.contains($0.ts) }
    }

    /// Точки не старше `cutoff`.
    public func points(since cutoff: Date) -> [Point] {
        points.filter { $0.ts >= cutoff }
    }
}
