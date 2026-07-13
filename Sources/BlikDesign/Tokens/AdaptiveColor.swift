import SwiftUI

/// Пара цветов для dark/light, резолвится по ColorScheme.
public struct AdaptiveColor {
    public let dark: Color
    public let light: Color

    public init(dark: Color, light: Color) {
        self.dark = dark
        self.light = light
    }

    public func resolve(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? dark : light
    }
}
