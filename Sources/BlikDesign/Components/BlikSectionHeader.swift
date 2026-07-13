import SwiftUI

/// Uppercase-заголовок секции плитки (например, «УПРАВЛЕНИЕ»).
/// Опциональный trailing-слот — для бейджа/статуса справа.
public struct BlikSectionHeader<Trailing: View>: View {
    private let text: String
    private let trailing: () -> Trailing

    @Environment(\.colorScheme) private var colorScheme

    public init(_ text: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.text = text
        self.trailing = trailing
    }

    public var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 9))
                .foregroundColor(DesignTokens.textTertiary.resolve(colorScheme))
                .textCase(.uppercase)
                .tracking(0.08 * 9)
            Spacer()
            trailing()
        }
    }
}
