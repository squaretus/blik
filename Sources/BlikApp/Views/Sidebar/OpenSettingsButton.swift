import SwiftUI
import BlikDesign
import AppKit

/// Кнопка "Настройки" внизу сайдбара. Стилизация совпадает с unselected
/// nav-row в `MainContentView.sidebarRow(for:)`.
struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            openSettings()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.primary)
                    .frame(width: 18)
                Text("Настройки")
                    .foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }
}
