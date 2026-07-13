import SwiftUI

/// Метрики единого page-каркаса. Один источник правды для всех вкладок.
public enum BlikPageMetrics {
    /// Верхний отступ поверх системного safe-area inset.
    /// `NavigationSplitView` сам резервирует зону под traffic lights — здесь 0.
    public static let topPadding: CGFloat = 0

    /// Горизонтальный отступ контейнера. Применяется ко **всем** страницам.
    /// Все страницы используют `List { Section }` (плоский стиль, без card-фонов).
    /// Контент секций растягивается на всю доступную ширину; кнопки/контролы
    /// внутри остаются inline-размером.
    public static let horizontalPadding: CGFloat = 40

    /// Единые insets для row'ов внутри `List { Section }`. Горизонталь = 0
    /// (всю горизонталь даёт `contentMargins(.horizontal, horizontalPadding)`),
    /// вертикаль задаёт ритм row'ов. Применяется на каждом `Section` всех страниц.
    public static let rowInsets: EdgeInsets = EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)

    /// Вертикальный зазор между категориями (секциями) списка. Реализуется
    /// footer-спейсером каждой `Section` (`.listSectionSpacing` на macOS недоступен).
    public static let sectionSpacing: CGFloat = 20
}

/// Единый каркас содержимого вкладок (`Обзор`, `Температура`, `Настройки`).
///
/// Контейнер сам применяет:
/// - фон темы `BlikPalette.bg`;
/// - `.scrollContentBackground(.hidden)` (убирает системный bg формы/листа);
/// - `.contentMargins(...)` сверху и по горизонтали.
///
/// Pages просто кладут scroll-примитив внутрь — никаких ручных отступов или
/// фоновых цветов в страницах быть не должно:
///
///     BlikPageContainer {
///         List {
///             Section { ... }.listRowInsets(BlikPageMetrics.rowInsets)
///         }
///         .scrollEdgeEffectStyle(.soft, for: .top)
///     }
///
/// Контракт: scroll-примитив страницы — `List { Section }` (плоский стиль,
/// без card-фонов). Контейнер сам ставит `.listStyle(.plain)` и убирает
/// системный bg через `.scrollContentBackground(.hidden)`. Контент внутри
/// секций растягивается на всю ширину (`Section` сам так делает), кнопки/пресеты
/// остаются inline-размером.
public struct BlikPageContainer<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .padding(.horizontal, BlikPageMetrics.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(BlikPalette.bg.resolve(colorScheme))
    }
}
