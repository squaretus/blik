import SwiftUI

/// Дизайн-токены приложения. Цвета — тонкие алиасы на `BlikPalette`,
/// чтобы вся палитра конфигурировалась из одного места
/// (см. `BlikPalette.swift` и эталон `icon/blik/palette/palette.json`).
///
/// Не-цветовые токены (размеры, шрифты) живут здесь.
public enum DesignTokens {

    // MARK: - Accent (бренд-цвет)

    /// Бирюзовый акцент для тёмной темы.
    public static let accentDark = BlikPalette.darkTheme.accent
    /// Светлая тема использует тот же бренд-teal в более тёмной (контрастной) насыщенности.
    public static let accentLight = BlikPalette.lightTheme.accent

    // MARK: - Status colors (semantic — green = healthy, amber = warn, red = error)

    /// Статус «healthy» — зелёный. Семантический цвет, не бренд.
    public static let green = BlikPalette.darkTheme.statusSuccess     // #00D68F
    /// Статус «warning» — янтарный.
    public static let amber = BlikPalette.darkTheme.statusWarn        // #FFB300
    /// Тёплый акцент для горячих температур (между amber и red).
    public static let amberDark = Color(hex: 0xE07700)
    /// Статус «error / hot» — красный.
    public static let red   = BlikPalette.darkTheme.statusError       // #FF4D6D

    // MARK: - Window

    public static let windowMinWidth: CGFloat = 900
    public static let windowMinHeight: CGFloat = 600

    // MARK: - Progress bar

    public static let progressBarHeight: CGFloat = 6
    public static let progressBarBg = AdaptiveColor(
        dark: Color.white.opacity(0.06),
        light: Color.black.opacity(0.08)
    )

    // MARK: - Typography

    /// Единый primary-шрифт всего приложения: метки, тело, кнопки, сайдбар.
    public static let fontPrimary: Font = .system(size: 13, weight: .regular)
    /// Primary-шрифт с medium-весом для интерактивных элементов (кнопки, активные пункты).
    public static let fontPrimaryMedium: Font = .system(size: 13, weight: .medium)
    /// Secondary-шрифт (зарезервирован — пока не применяется).
    public static let fontSecondary: Font = .system(size: 11, weight: .regular)
}

public extension DesignTokens {
    /// Адаптивный accent — резолвится по `colorScheme`.
    static let accent = BlikPalette.accent

    static let textSecondary = AdaptiveColor(
        dark: Color.white.opacity(0.65),
        light: Color.black.opacity(0.55)
    )
    static let textTertiary = AdaptiveColor(
        dark: Color.white.opacity(0.45),
        light: Color.black.opacity(0.45)
    )
}
