import SwiftUI

/// Канонiчная палитра бренда `.blik`.
///
/// Эталон лежит в `icon/blik/palette/palette.json` (вместе с `palette.css`
/// для лендинга / кабинета / админки). Этот файл — Swift-порт того же
/// эталона. При изменении палитры — синхронизируй оба места.
///
/// Использование:
///     BlikPalette.primary
///     BlikPalette.theme(colorScheme).bg
///     BlikPalette.theme(colorScheme).statusOK
public enum BlikPalette {

    // MARK: - Brand (общие, не зависят от темы)

    /// Основной teal — кнопки, акценты, status pill.
    public static let primary    = Color(hex: 0x007479)
    /// Светлый teal — accent на тёмном, status-точка в трее, charts.
    public static let light      = Color(hex: 0x2FB3B8)
    /// Глубокий тёмно-петролевый — UI base.
    public static let deep       = Color(hex: 0x003C40)
    /// Мятный mid в orb-градиенте.
    public static let mintMid    = Color(hex: 0x7FDCDE)
    /// Core блика, glass-highlight.
    public static let mintGlass  = Color(hex: 0xCBF3F2)

    // MARK: - Theme

    public struct Theme {
        public let bg:            Color
        public let surface:       Color
        public let surface2:      Color
        public let text:          Color
        public let muted:         Color
        public let line:          Color
        public let accent:        Color
        public let statusOK:      Color
        public let statusWarn:    Color
        public let statusError:   Color
        public let statusSuccess: Color
    }

    public static let darkTheme = Theme(
        bg:            Color(hex: 0x0A0D14),
        surface:       Color(hex: 0x11151F),
        surface2:      Color(hex: 0x161B27),
        text:          Color(hex: 0xE6E8EE),
        muted:         Color(hex: 0x8B93A6),
        line:          Color.white.opacity(0.08),
        accent:        Color(hex: 0x2FB3B8),
        statusOK:      Color(hex: 0x2FB3B8),
        statusWarn:    Color(hex: 0xFFB300),
        statusError:   Color(hex: 0xFF4D6D),
        statusSuccess: Color(hex: 0x00D68F)
    )

    public static let lightTheme = Theme(
        bg:            Color(hex: 0xF4F1EB),
        surface:       Color(hex: 0xFBFAF6),
        surface2:      Color(hex: 0xF0ECE2),
        text:          Color(hex: 0x0F1318),
        muted:         Color(hex: 0x5A6470),
        line:          Color(hex: 0x003C40, opacity: 0.10),
        accent:        Color(hex: 0x007479),
        statusOK:      Color(hex: 0x007479),
        statusWarn:    Color(hex: 0xC87C00),
        statusError:   Color(hex: 0xD63249),
        statusSuccess: Color(hex: 0x008458)
    )

    public static func theme(_ scheme: ColorScheme) -> Theme {
        scheme == .dark ? darkTheme : lightTheme
    }

    // MARK: - Adaptive aliases (для use-case'ов, где не доступен ColorScheme)

    public static let bg            = AdaptiveColor(dark: darkTheme.bg,            light: lightTheme.bg)
    public static let surface       = AdaptiveColor(dark: darkTheme.surface,       light: lightTheme.surface)
    public static let surface2      = AdaptiveColor(dark: darkTheme.surface2,      light: lightTheme.surface2)
    public static let text          = AdaptiveColor(dark: darkTheme.text,          light: lightTheme.text)
    public static let muted         = AdaptiveColor(dark: darkTheme.muted,         light: lightTheme.muted)
    public static let line          = AdaptiveColor(dark: darkTheme.line,          light: lightTheme.line)
    public static let accent        = AdaptiveColor(dark: darkTheme.accent,        light: lightTheme.accent)
    public static let statusOK      = AdaptiveColor(dark: darkTheme.statusOK,      light: lightTheme.statusOK)
    public static let statusWarn    = AdaptiveColor(dark: darkTheme.statusWarn,    light: lightTheme.statusWarn)
    public static let statusError   = AdaptiveColor(dark: darkTheme.statusError,   light: lightTheme.statusError)
    public static let statusSuccess = AdaptiveColor(dark: darkTheme.statusSuccess, light: lightTheme.statusSuccess)
}
