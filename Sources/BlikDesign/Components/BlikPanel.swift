import SwiftUI

/// Переиспользуемая карточка-панель дизайн-системы: фон `surface` (чуть выше фона
/// страницы), hairline-border `line`, радиус 8. Единый «плиточный» стиль для
/// модулей графиков и секций вкладок (Обзор/Температура/Ресурсы).
///
///     BlikPanel {
///         VStack(alignment: .leading) { header; content }
///     }
public struct BlikPanel<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    @Environment(\.colorScheme) private var scheme

    public init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BlikPalette.surface.resolve(scheme)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(BlikPalette.line.resolve(scheme), lineWidth: 1),
            )
    }
}
