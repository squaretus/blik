import SwiftUI

/// Утилита для определения цвета по температуре.
/// Пороги:
/// - <60: green
/// - 60..<75: amber
/// - 75..<85: dark amber
/// - >=85: red
public enum TemperatureColor {
    public static func color(for temperature: Double) -> Color {
        switch temperature {
        case ..<60:
            return DesignTokens.green
        case 60..<75:
            return DesignTokens.amber
        case 75..<85:
            return DesignTokens.amberDark
        default:
            return DesignTokens.red
        }
    }

    /// Gradient для отображения температуры крупным шрифтом.
    public static func gradient(for temperature: Double) -> LinearGradient {
        if temperature > 60 {
            return LinearGradient(
                colors: [DesignTokens.amber, DesignTokens.amberDark],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color(hex: 0x6EE7B7), DesignTokens.green],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// Ambient glow цвет для температурной карточки.
    public static func ambientGlow(for temperature: Double) -> Color {
        if temperature > 60 {
            return DesignTokens.amberDark.opacity(0.15)
        } else {
            return DesignTokens.green.opacity(0.12)
        }
    }

    /// Gradient для progress bar вентилятора (по проценту загрузки).
    public static func fanGradient(percentage: Double) -> LinearGradient {
        if percentage > 0.6 {
            return LinearGradient(
                colors: [DesignTokens.green, DesignTokens.amber],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient(
                colors: [DesignTokens.green, DesignTokens.green],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    /// Glow-цвет для progress bar fill.
    public static func fanGlowColor(percentage: Double) -> Color {
        if percentage > 0.6 {
            return DesignTokens.amber.opacity(0.3)
        } else {
            return DesignTokens.green.opacity(0.3)
        }
    }
}
