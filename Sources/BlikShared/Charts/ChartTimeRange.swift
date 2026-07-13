import Foundation

/// Режим отображения графиков.
///
/// - `.live` — поллинг в реальном времени (наполнение `LiveMetricBuffer`).
/// - `.range` — исторический диапазон (загрузка через XPC-историю).
public enum ChartMode: Equatable, Sendable {
    case live
    case range(ChartTimeRange)
}

/// Пресеты периода. Дальше 7 дней локальная история не хранится (ретенция
/// роллапов = 7 дней), поэтому пресетов длиннее нет.
public enum ChartRangePreset: String, CaseIterable, Identifiable, Sendable {
    case m5, m15, m30, h1, h3, h6, h12, h24, d3, d7

    public var id: String { rawValue }

    /// Длительность пресета в секундах.
    public var seconds: TimeInterval {
        switch self {
        case .m5:  return 5 * 60
        case .m15: return 15 * 60
        case .m30: return 30 * 60
        case .h1:  return 3600
        case .h3:  return 3 * 3600
        case .h6:  return 6 * 3600
        case .h12: return 12 * 3600
        case .h24: return 24 * 3600
        case .d3:  return 3 * 86_400
        case .d7:  return 7 * 86_400
        }
    }

    /// Человекочитаемая метка для пикера.
    public var title: String {
        switch self {
        case .m5:  return "5 мин"
        case .m15: return "15 мин"
        case .m30: return "30 мин"
        case .h1:  return "1 ч"
        case .h3:  return "3 ч"
        case .h6:  return "6 ч"
        case .h12: return "12 ч"
        case .h24: return "24 ч"
        case .d3:  return "3 дня"
        case .d7:  return "7 дней"
        }
    }

    /// Диапазон `[now − seconds, now]`.
    public func range(now: Date = Date()) -> ChartTimeRange {
        ChartTimeRange(from: now.addingTimeInterval(-seconds), to: now)
    }
}

/// Замкнутый временной диапазон для исторического запроса. Инвариант: `from ≤ to`
/// и `to − from ≤ 7 дней` (кламп в `init`, т.к. глубже история не хранится).
public struct ChartTimeRange: Equatable, Sendable {
    /// Максимальный охват диапазона — 7 дней (ретенция роллапов).
    public static let maxSpan: TimeInterval = 7 * 86_400

    public let from: Date
    public let to: Date

    /// Нормализует порядок (`from ≤ to`) и клампит охват до 7 дней, двигая
    /// `from` вперёд (сохраняя более свежую границу `to`).
    public init(from: Date, to: Date) {
        let lo = min(from, to)
        let hi = max(from, to)
        if hi.timeIntervalSince(lo) > Self.maxSpan {
            self.from = hi.addingTimeInterval(-Self.maxSpan)
        } else {
            self.from = lo
        }
        self.to = hi
    }

    /// Охват диапазона в секундах.
    public var span: TimeInterval { to.timeIntervalSince(from) }
}
