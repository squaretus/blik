import Foundation
import os

/// Хранилище конфигураций виджетов графиков. Набор фиксирован
/// (`ChartWidgetConfig.defaults`) — store хранит только пользовательские правки
/// поверх дефолтов, без add/remove.
///
/// Persist в **`UserDefaults(suiteName: "com.blik.shared")`** (общий для
/// BlikApp/BlikMenuBar), ключ `"chartWidgets.v1"`, значение — JSON-массив
/// `ChartWidgetConfig`. `@AppStorage` в `@Observable` не работает (правило
/// проекта) — работаем с `UserDefaults` напрямую.
@Observable
@MainActor
public final class ChartWidgetStore {

    private static let logger = os.Logger(subsystem: "com.blik.shared", category: "ChartWidgetStore")

    /// Итоговый список виджетов: дефолты, перекрытые сохранёнными правками.
    /// Порядок = порядок `ChartWidgetConfig.defaults`.
    public private(set) var widgets: [ChartWidgetConfig]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "chartWidgets.v1"

    /// - Parameter defaults: инжектируемое хранилище (тесты — временный suite).
    public init(defaults: UserDefaults = UserDefaults(suiteName: "com.blik.shared") ?? .standard) {
        self.defaults = defaults
        let stored = Self.loadOverrides(from: defaults, key: storageKey)
        // stored ∪ defaults: известный id из stored перекрывает дефолт,
        // неизвестные id из хранилища отбрасываются.
        self.widgets = ChartWidgetConfig.defaults.map { stored[$0.id] ?? $0 }
    }

    /// Сохраняет правку виджета. Неизвестные id игнорируются (набор фиксирован).
    public func update(_ config: ChartWidgetConfig) {
        guard let idx = widgets.firstIndex(where: { $0.id == config.id }) else { return }
        widgets[idx] = config
        persist()
    }

    /// Сбрасывает виджет к дефолту.
    public func reset(id: String) {
        guard let def = ChartWidgetConfig.defaults.first(where: { $0.id == id }),
              let idx = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[idx] = def
        persist()
    }

    // MARK: - Persistence

    private static func loadOverrides(from defaults: UserDefaults, key: String) -> [String: ChartWidgetConfig] {
        guard let data = defaults.data(forKey: key),
              let configs = try? JSONDecoder().decode([ChartWidgetConfig].self, from: data) else {
            return [:]
        }
        let knownIDs = Set(ChartWidgetConfig.defaults.map(\.id))
        var out: [String: ChartWidgetConfig] = [:]
        for cfg in configs where knownIDs.contains(cfg.id) {
            out[cfg.id] = cfg
        }
        return out
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(widgets) else {
            Self.logger.error("failed to encode chart widgets")
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
