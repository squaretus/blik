import SwiftUI

// MARK: - Environment

private struct SearchQueryKey: EnvironmentKey {
    static let defaultValue: String = ""
}

public extension EnvironmentValues {
    /// Глобальный текст поиска по приложению. Заполняется в `MainContentView`
    /// из `.searchable(text:)` и пробрасывается в детальный pane через
    /// `.environment(\.searchQuery, ...)`. Любая страница / row может его
    /// прочитать и применить `.searchVisible(matches:)`.
    var searchQuery: String {
        get { self[SearchQueryKey.self] }
        set { self[SearchQueryKey.self] = newValue }
    }
}

// MARK: - Visibility modifier

/// Фильтр row/секции по `searchQuery`. При непустом query и **отсутствии**
/// совпадений хоть с одной из `matches` (case-insensitive substring) — row
/// не рендерится вовсе. Это нативный pattern macOS-приложений (Docker, System
/// Settings): пользователь печатает в search field — список схлопывается до
/// подходящих элементов, без подсветки. Подсветка для этого паттерна не
/// нужна — оставшиеся row'ы и так все «совпадение».
private struct SearchVisibilityModifier: ViewModifier {
    @Environment(\.searchQuery) private var searchQuery
    let matches: [String]

    func body(content: Content) -> some View {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        let isVisible = trimmed.isEmpty
            || matches.contains { $0.localizedCaseInsensitiveContains(trimmed) }

        Group {
            if isVisible {
                content
            }
        }
    }
}

public extension View {
    /// Скрывает row/секцию, если `searchQuery` непустой и не совпадает ни с одной
    /// из `matches`. При пустом query view рендерится без изменений.
    ///
    /// `matches` — все строки, по которым row считается «найденным» (видимый
    /// label, дополнительные ключевые слова RU/EN). Минимум — видимый label.
    func searchVisible(matches: [String]) -> some View {
        modifier(SearchVisibilityModifier(matches: matches))
    }

    /// Шорткат для одиночной строки.
    func searchVisible(_ match: String) -> some View {
        searchVisible(matches: [match])
    }
}
