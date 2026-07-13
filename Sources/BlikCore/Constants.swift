import Foundation

/// Именованные константы, извлечённые из магических чисел по всему проекту.
/// Caseless enum предотвращает случайное создание экземпляров.
public enum Constants {
    /// Пауза основного цикла между итерациями (микросекунды)
    public static let pollIntervalMicroseconds: useconds_t = 50_000

    /// Пресеты скорости вентиляторов (проценты от min→max)
    public static let speedPresets: [Int] = [0, 25, 50, 75, 100]

    /// Максимальное отображаемое значение RPM (ограничение вывода)
    public static let maxDisplayRPM: Double = 99_999

    /// Ширина терминала по умолчанию (если ioctl не сработал)
    public static let defaultTerminalCols = 80

    /// Высота терминала по умолчанию (если ioctl не сработал)
    public static let defaultTerminalRows = 24

    /// Размер буфера чтения клавиатурного ввода (байт)
    public static let inputBufferSize = 64

    /// Порог «залива» ввода — если прочитано больше байт, считаем спамом (trackpad scroll)
    public static let inputFloodThreshold = 6

    /// Задержка после разблокировки Ftst для перехода F{n}Md из 3 в 0 (секунды)
    public static let ftstUnlockDelay: TimeInterval = 3.0

    /// Количество колонок в дашборде
    public static let dashboardColumnCount = 4

    /// Зазор между колонками дашборда (символов)
    public static let dashboardColumnGap = 1

    /// Минимальная ширина колонки дашборда (символов)
    public static let dashboardMinColumnWidth = 18

    /// Ширина прогресс-бара скорости вентилятора (символов)
    public static let fanProgressBarWidth = 6

    /// Минимальное количество видимых «Остальных» датчиков
    public static let minVisibleOtherSensors = 3

    /// Версия приложения
    public static let appVersion = "2.11.0"

    /// Минимальная версия daemon'а, поддерживающая объединённый XPC-метод `readState`.
    /// Клиент старше этой версии — использует `readAllFans` + `readAllSensors`.
    public static let minHelperVersionForReadState = "1.3.1"

    /// Минимальная версия daemon'а, поддерживающая локальную историю метрик
    /// (XPC-методы `queryHistory`/`listHistoryMetrics`). Клиент старше — range-режим
    /// графиков недоступен (empty-state вместо зависания на старом селекторе).
    /// Значение = релиз, в котором история появилась (== текущий `appVersion`),
    /// по образцу `minHelperVersionForReadState`. Не поднимать выше `appVersion` —
    /// иначе свежий helper будет ошибочно считаться неподдерживающим историю.
    public static let minHelperVersionForHistory = "2.11.0"

    // MARK: - History (локальная запись метрик в daemon'е)

    /// Шаг семплинга сырых точек истории, секунды.
    public static let historyRawCadenceSeconds: TimeInterval = 5

    /// Ретенция сырых точек `sample_raw`, секунды (24 ч).
    public static let historyRawRetention: TimeInterval = 86_400

    /// Ретенция 1-минутных роллапов `sample_1m`, секунды (7 дней).
    public static let historyRollupRetention: TimeInterval = 604_800

    /// Граница выбора таблицы в запросе: диапазон ≤ этого значения идёт по
    /// `sample_raw`, иначе по `sample_1m`, секунды (6 ч).
    public static let historyRawQueryWindow: TimeInterval = 21_600

    /// Путь к SQLite-файлу истории (root-owned, читается только через XPC).
    public static let historyDBPath = "/Library/Application Support/Blik/history.db"

    // MARK: - Polling

    /// Доступные интервалы обновления данных, секунды (UI настройка).
    public static let pollIntervalOptions: [TimeInterval] = [1, 5, 10]

    /// Интервал обновления по умолчанию, секунды.
    public static let defaultPollIntervalSeconds: TimeInterval = 1

    // MARK: - Auto-Update

    /// GitHub owner для проверки обновлений
    public static let githubOwner = "squaretus"

    /// GitHub repo для проверки обновлений
    public static let githubRepo = "blik"

    /// Интервал проверки обновлений (секунды): 6 часов
    public static let updateCheckInterval: TimeInterval = 21_600

    /// Задержка первой проверки обновления после старта daemon (секунды)
    public static let updateCheckInitialDelay: TimeInterval = 10
}
