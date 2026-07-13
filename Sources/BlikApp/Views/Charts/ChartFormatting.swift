import SwiftUI
import BlikShared
import BlikDesign

/// Форматтеры значений и осей графиков по `MetricUnit`. Переиспользуют
/// конвенции вкладки «Ресурсы» (целые проценты, `ByteCountFormatter.memory`).
///
/// Возвращают строки — вызывающий рендерит их через `Text(verbatim:)`
/// (правило проекта: числа без locale-форматирования).
enum ChartFormatting {

    /// Полная подпись значения с суффиксом единицы (для крупных чисел/футеров).
    static func value(_ v: Double, unit: MetricUnit) -> String {
        switch unit {
        case .celsius:     return "\(Int(v.rounded()))°C"
        case .percent:     return "\(Int(v.rounded()))%"
        case .rpm:         return "\(Int(v.rounded())) RPM"
        case .bytes:       return bytes(v)
        case .bytesPerSec: return "\(bytes(v))/с"
        }
    }

    /// Короткая подпись деления оси Y (без суффикса «RPM»/«/с» для компактности).
    static func axis(_ v: Double, unit: MetricUnit) -> String {
        switch unit {
        case .celsius:     return "\(Int(v.rounded()))°"
        case .percent:     return "\(Int(v.rounded()))%"
        case .rpm:         return "\(Int(v.rounded()))"
        case .bytes, .bytesPerSec: return bytes(v)
        }
    }

    /// Байты в человекочитаемом виде (память → `.memory` стиль как на «Ресурсах»).
    static func bytes(_ v: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, v)), countStyle: .memory)
    }
}

// MARK: - Plot points

/// Точка графика, нормализованная под общий рендеринг live/range.
///
/// В live-режиме `lo == value == hi` (нет агрегации). В range-режиме
/// `value = avg`, `lo = min`, `hi = max` бакета — используется для min/max
/// маркеров и футеров.
struct ChartPlotPoint: Identifiable, Equatable {
    /// Индекс внутри сегмента — стабильная идентичность для `ForEach`.
    let id: Int
    let ts: Date
    let value: Double
    let lo: Double
    let hi: Double
}

/// Один непрерывный сегмент серии одной метрики. Сегменты разбиты по разрывам
/// (`ChartsVM.liveSegments`/`rangeSegments`), у каждого — собственный `id`,
/// чтобы Swift Charts не соединял линию/область через пропуск.
struct ChartSeriesSegment: Identifiable {
    let id: String
    let metric: String
    let points: [ChartPlotPoint]
}

/// Свод статистики серии (для футеров и min/max маркеров).
struct ChartStats {
    let min: Double
    let avg: Double
    let max: Double
    let minPoint: ChartPlotPoint?
    let maxPoint: ChartPlotPoint?
}

/// Резолвер данных серии из `ChartsVM` с учётом текущего режима (live/range).
/// `@MainActor` — читает `@Observable` VM (`mode`/`series`/буферы).
@MainActor
enum ChartData {

    /// Окно live-точек (сек) — соответствует ёмкости кольцевого буфера (~15 мин).
    static let liveWindow: TimeInterval = 900

    /// Максимум точек на сегмент для отрисовки. Swift Charts деградирует на многих
    /// marks; прореживание min/max-бакетами сохраняет форму и пики. Исходную
    /// историю не трогает — это только render-cap.
    static let renderPointCap = 600

    /// Сегменты серии метрики с учётом режима.
    static func segments(_ charts: ChartsVM, metric: String) -> [ChartSeriesSegment] {
        let raw: [[ChartPlotPoint]]
        switch charts.mode {
        case .live:
            let bufferSegments = charts.liveSegments(for: metric,
                                                     window: min(charts.liveWindowSeconds, liveWindow))
            if charts.liveHistory[metric]?.isEmpty ?? true {
                // Нет daemon-истории (helper недоступен / ещё не подгрузилась) — только live-буфер.
                raw = bufferSegments.map { seg in
                    seg.enumerated().map {
                        ChartPlotPoint(id: $0.offset, ts: $0.element.ts,
                                       value: $0.element.value, lo: $0.element.value, hi: $0.element.value)
                    }
                }
            } else {
                // Daemon-история (прошлое) + живой хвост буфера. Стале-фрагменты буфера
                // отброшены — их регион покрывает история.
                let (olderHistory, tail) = ChartsVM.liveMergeSplit(history: charts.liveHistory[metric] ?? [],
                                                                   bufferSegments: bufferSegments)
                let older = olderHistory.map {
                    ChartPlotPoint(id: 0, ts: $0.ts, value: $0.avg, lo: $0.min, hi: $0.max)
                }
                let tailPts = tail.map {
                    ChartPlotPoint(id: 0, ts: $0.ts, value: $0.value, lo: $0.value, hi: $0.value)
                }
                let merged = (older + tailPts).sorted { $0.ts < $1.ts }
                raw = splitByGap(merged, gap: Double(charts.rangeBucketSeconds) * 3).map { seg in
                    seg.enumerated().map {
                        ChartPlotPoint(id: $0.offset, ts: $0.element.ts,
                                       value: $0.element.value, lo: $0.element.lo, hi: $0.element.hi)
                    }
                }
            }
        case .range:
            raw = charts.rangeSegments(for: metric).map { seg in
                seg.enumerated().map {
                    ChartPlotPoint(id: $0.offset, ts: $0.element.ts,
                                   value: $0.element.avg, lo: $0.element.min, hi: $0.element.max)
                }
            }
        }
        return raw.enumerated().map { idx, pts in
            ChartSeriesSegment(id: "\(metric)#\(idx)", metric: metric, points: downsample(pts, cap: renderPointCap))
        }
    }

    /// Прореживание сегмента до `cap` точек min/max-бакетами (сохраняет пики и
    /// огибающую). Первую/последнюю точки всегда оставляем.
    static func downsample(_ points: [ChartPlotPoint], cap: Int) -> [ChartPlotPoint] {
        let n = points.count
        guard n > cap, cap > 4 else { return points }
        let buckets = cap / 2
        var out: [ChartPlotPoint] = []
        out.reserveCapacity(cap + 2)
        out.append(points[0])
        for b in 0..<buckets {
            let lo = 1 + (n - 2) * b / buckets
            let hi = 1 + (n - 2) * (b + 1) / buckets
            guard lo < hi else { continue }
            let slice = points[lo..<min(hi, n - 1)]
            guard let minP = slice.min(by: { $0.value < $1.value }),
                  let maxP = slice.max(by: { $0.value < $1.value }) else { continue }
            if minP.ts <= maxP.ts {
                out.append(minP)
                if maxP.ts != minP.ts { out.append(maxP) }
            } else {
                out.append(maxP)
                out.append(minP)
            }
        }
        out.append(points[n - 1])
        return out.enumerated().map {
            ChartPlotPoint(id: $0.offset, ts: $0.element.ts, value: $0.element.value,
                           lo: $0.element.lo, hi: $0.element.hi)
        }
    }

    /// Плоский список точек серии (для статистики).
    static func points(_ charts: ChartsVM, metric: String) -> [ChartPlotPoint] {
        segments(charts, metric: metric).flatMap(\.points)
    }

    /// Текущее значение метрики: live → последняя точка, range → среднее.
    static func current(_ charts: ChartsVM, metric: String) -> Double? {
        let pts = points(charts, metric: metric)
        guard !pts.isEmpty else { return nil }
        if case .range = charts.mode {
            return pts.map(\.value).reduce(0, +) / Double(pts.count)
        }
        return pts.last?.value
    }

    /// Статистика по набору точек (min/avg/max + точки экстремумов).
    static func stats(_ points: [ChartPlotPoint]) -> ChartStats? {
        guard !points.isEmpty else { return nil }
        let minP = points.min { $0.lo < $1.lo }
        let maxP = points.max { $0.hi < $1.hi }
        let avg = points.map(\.value).reduce(0, +) / Double(points.count)
        return ChartStats(min: minP?.lo ?? 0, avg: avg, max: maxP?.hi ?? 0,
                          minPoint: minP, maxPoint: maxP)
    }

    /// Разбивает упорядоченный по времени ряд на сегменты по разрывам
    /// (`Δts > gap`) — чтобы график не мостил простои интерполяцией.
    static func splitByGap(_ points: [ChartPlotPoint], gap: TimeInterval) -> [[ChartPlotPoint]] {
        guard let first = points.first else { return [] }
        var segments: [[ChartPlotPoint]] = []
        var current: [ChartPlotPoint] = [first]
        for i in 1..<points.count {
            if points[i].ts.timeIntervalSince(points[i - 1].ts) > gap {
                segments.append(current)
                current = [points[i]]
            } else {
                current.append(points[i])
            }
        }
        segments.append(current)
        return segments
    }
}

// MARK: - Series colors

/// Палитра цветов серий графиков (по индексу метрики внутри виджета).
enum ChartSeriesColor {
    static let palette: [Color] = [
        BlikPalette.light,       // teal (бренд)
        Color(hex: 0xFFB300),    // amber
        Color(hex: 0x8B5CF6),    // violet
        Color(hex: 0x00D68F),    // green
        Color(hex: 0xFF4D6D),    // pink/red
        Color(hex: 0x4C9AFF),    // blue
    ]

    static func color(_ index: Int) -> Color {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    /// Цвет по значению относительно порогов warn/crit (для gauge).
    static func threshold(value: Double, warn: Double?, crit: Double?) -> Color {
        if let crit, value >= crit { return DesignTokens.red }
        if let warn, value >= warn { return DesignTokens.amber }
        return DesignTokens.green
    }
}
