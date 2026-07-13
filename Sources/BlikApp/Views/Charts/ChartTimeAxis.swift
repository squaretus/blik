import Foundation

/// Время для оси X графиков — порт серверной `telemetry-time.ts`.
///
/// Две задачи:
/// 1. Ось охватывает ВЕСЬ выбранное окно `[from, to]` (Grafana-style), а не
///    сжимается до экстента данных → домен X задаётся окном.
/// 2. «Круглые» тики: выбираем самый мелкий интервал, дающий ≤ target меток,
///    выравниваем суточные+ по локальной полуночи, мельче — по кратности.
///    Формат метки зависит от длины диапазона.
enum ChartTimeAxis {

    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 86_400

    /// Кандидаты-интервалы тиков (сек), от мелкого к крупному. Мелкие шаги нужны,
    /// чтобы короткое окно (5–15 мин) на широком графике давало частые «круглые»
    /// метки, а не прыгало 1м→5м.
    private static let intervals: [TimeInterval] = [
        10, 15, 30, minute, 2 * minute, 5 * minute, 10 * minute, 15 * minute,
        30 * minute, hour, 2 * hour, 3 * hour, 6 * hour, 12 * hour,
        day, 2 * day, 7 * day, 14 * day, 30 * day,
    ]

    /// «Круглые» тики на `[from, to]`.
    static func niceTicks(from: Date, to: Date, target: Int) -> [Date] {
        let span = to.timeIntervalSince(from)
        guard span > 0, target > 0 else { return [] }

        var interval = intervals[intervals.count - 1]
        for i in intervals where span / i <= Double(target) {
            interval = i
            break
        }

        var ticks: [Date] = []
        if interval >= day {
            // Суточные+ выравниваем по локальной полуночи (DST-safe через Calendar).
            let cal = Calendar.current
            let stepDays = max(1, Int((interval / day).rounded()))
            var d = cal.startOfDay(for: from)
            while d < from { d = cal.date(byAdding: .day, value: stepDays, to: d) ?? d.addingTimeInterval(interval) }
            while d <= to {
                ticks.append(d)
                d = cal.date(byAdding: .day, value: stepDays, to: d) ?? d.addingTimeInterval(interval)
            }
        } else {
            // Мельче суток — по кратности интервала (эпоха-секунды).
            let startE = from.timeIntervalSince1970
            let toE = to.timeIntervalSince1970
            var t = (startE / interval).rounded(.up) * interval
            while t <= toE {
                ticks.append(Date(timeIntervalSince1970: t))
                t += interval
            }
        }
        return ticks
    }

    /// Формат метки оси по длине диапазона:
    /// - ≤ 2 дней → `ЧЧ:ММ`; 2..14 дней → `ДД.ММ ЧЧ:ММ`; > 14 дней → `ДД.ММ`.
    static func axisLabel(_ d: Date, rangeSeconds: TimeInterval) -> String {
        if rangeSeconds <= 2 * day { return hhmm.string(from: d) }
        if rangeSeconds <= 14 * day { return "\(ddmm.string(from: d)) \(hhmm.string(from: d))" }
        return ddmm.string(from: d)
    }

    /// Формат метки тултипа: внутри 2 суток — `ЧЧ:ММ`, иначе — `ДД.ММ ЧЧ:ММ`.
    /// Для очень коротких окон (≤ 15 мин) добавляем секунды.
    static func tooltipLabel(_ d: Date, rangeSeconds: TimeInterval) -> String {
        if rangeSeconds <= 15 * minute { return hhmmss.string(from: d) }
        if rangeSeconds <= 2 * day { return hhmm.string(from: d) }
        return "\(ddmm.string(from: d)) \(hhmm.string(from: d))"
    }

    /// Целевое число тиков из ширины графика — метка с датой шире, ей нужен
    /// больший шаг. Делитель ширины на пиксельный зазор даёт адаптивное число
    /// меток (фикс. визуальный отступ при ресайзе).
    static func targetTickCount(width: CGFloat, rangeSeconds: TimeInterval) -> Int {
        let gap: CGFloat
        if rangeSeconds <= 2 * day { gap = 80 }
        else if rangeSeconds <= 14 * day { gap = 150 }
        else { gap = 90 }
        return max(2, Int(width / gap))
    }

    // MARK: - Formatters (локальное время, кэш)

    private static let hhmm = fixed("HH:mm")
    private static let hhmmss = fixed("HH:mm:ss")
    private static let ddmm = fixed("dd.MM")

    private static func fixed(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = format
        return f
    }
}
