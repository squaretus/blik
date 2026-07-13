import SwiftUI

/// Капсула статуса — заменяет `LicenseCard.statusPill` и `OverviewPage.modeBadge`.
public struct BlikStatusPill: View {
    private let text: String
    private let color: Color
    private let filled: Bool

    public init(text: String, color: Color, filled: Bool = false) {
        self.text = text
        self.color = color
        self.filled = filled
    }

    public var body: some View {
        Text(text)
            .font(DesignTokens.fontPrimaryMedium)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(filled ? .white : color)
            .background(color.opacity(filled ? 1.0 : 0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(filled ? 0.0 : 0.15), lineWidth: 1))
    }
}
