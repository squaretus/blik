import Foundation

/// Codable-контракт запроса истории через XPC (сериализуется в JSON `Data`).
public struct HistoryQueryRequest: Codable, Equatable, Sendable {
    /// Список метрик. Хелпер обрезает до `maxMetrics` (32).
    public var metrics: [String]
    public var from: Date
    public var to: Date
    /// Желаемое макс. число точек на серию. Клиент по умолчанию 720, хелпер
    /// клампит до `maxPointsHardCap` (2000).
    public var maxPointsPerSeries: Int

    /// Дефолт числа точек на серию (клиентская сторона).
    public static let defaultMaxPoints = 720
    /// Жёсткий потолок числа точек (кламп на стороне хелпера).
    public static let maxPointsHardCap = 2000
    /// Жёсткий потолок числа метрик в запросе.
    public static let maxMetrics = 32

    public init(metrics: [String], from: Date, to: Date,
                maxPointsPerSeries: Int = HistoryQueryRequest.defaultMaxPoints) {
        self.metrics = metrics
        self.from = from
        self.to = to
        self.maxPointsPerSeries = maxPointsPerSeries
    }
}

/// Одна агрегированная точка серии: границы бакета min/avg/max.
public struct HistoryPoint: Codable, Equatable, Sendable {
    public var ts: Date
    public var min: Double
    public var avg: Double
    public var max: Double

    public init(ts: Date, min: Double, avg: Double, max: Double) {
        self.ts = ts
        self.min = min
        self.avg = avg
        self.max = max
    }
}

/// Временной ряд одной метрики.
public struct HistorySeries: Codable, Equatable, Sendable {
    public var metric: String
    public var points: [HistoryPoint]

    public init(metric: String, points: [HistoryPoint]) {
        self.metric = metric
        self.points = points
    }
}

/// Ответ на запрос истории: серии + фактический размер бакета агрегации.
public struct HistoryQueryResponse: Codable, Equatable, Sendable {
    public var series: [HistorySeries]
    public var bucketSeconds: Int

    public init(series: [HistorySeries], bucketSeconds: Int) {
        self.series = series
        self.bucketSeconds = bucketSeconds
    }
}
