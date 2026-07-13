import SwiftUI
import BlikDesign

/// Секция с заголовком НАД карточкой: `заголовок [· бейдж]` сверху, ниже —
/// `BlikPanel` с контентом. Единый паттерн для всех вкладок (Обзор/Температура/
/// Ресурсы) — заголовок категории вынесен за карточку.
struct TitledCard<Content: View>: View {
    let title: String
    var badgeText: String? = nil
    var badgeColor: Color = .secondary
    var panelPadding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(DesignTokens.fontPrimaryMedium)
                Spacer(minLength: 0)
                if let badgeText {
                    Text(verbatim: badgeText)
                        .font(DesignTokens.fontSecondary)
                        .foregroundStyle(badgeColor)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 4)

            BlikPanel(padding: panelPadding) {
                content()
            }
        }
    }
}
