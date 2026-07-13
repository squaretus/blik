import Foundation

/// Хранилище кастомных имён метрик (инлайн-переименование датчиков).
///
/// Разделяется между исполняемыми файлами `BlikApp` и `BlikMenuBar` через
/// **`UserDefaults(suiteName: "com.blik.shared")`** — `.standard` между разными
/// процессами НЕ разделяется, поэтому именованный suite обязателен.
///
/// `@AppStorage` внутри `@Observable` не работает (правило проекта) — работаем
/// с `UserDefaults` напрямую.
@Observable
@MainActor
public final class MetricNameStore {

    /// Кастомные имена: `metricKey → пользовательское имя`.
    /// Отсутствие ключа означает «использовать дефолт».
    public private(set) var names: [String: String]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "metricCustomNames.v1"

    /// - Parameter defaults: инжектируемое хранилище (для тестов — временный suite).
    ///   По умолчанию — общий для BlikApp/BlikMenuBar suite `com.blik.shared`.
    public init(defaults: UserDefaults = UserDefaults(suiteName: "com.blik.shared") ?? .standard) {
        self.defaults = defaults
        self.names = (defaults.dictionary(forKey: "metricCustomNames.v1") as? [String: String]) ?? [:]
    }

    /// Отображаемое имя метрики: кастомное, если задано, иначе `defaultName`.
    public func displayName(for key: String, default defaultName: String) -> String {
        names[key] ?? defaultName
    }

    /// Задаёт кастомное имя. Пустая строка/`nil` (после trim) — сброс к дефолту.
    public func setName(_ name: String?, for key: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            names.removeValue(forKey: key)
        } else {
            names[key] = trimmed
        }
        persist()
    }

    private func persist() {
        if names.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else {
            defaults.set(names, forKey: storageKey)
        }
    }
}
