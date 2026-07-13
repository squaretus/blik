import SwiftUI
import AppKit
import BlikShared
import BlikDesign

/// Захватывает `NSWindow` хостящего SwiftUI-view (для позиционирования окна
/// настроек). `NSViewRepresentable` — единственный способ дотянуться до окна
/// `Settings { }`-сцены из SwiftUI.
private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Корневое представление окна `Settings { }` сцены.
///
/// macOS 26 `Settings { }` scene применяет к `NavigationSplitView` свой
/// system style — пилюли крупнее, paddings шире (как в `System Settings.app`).
/// Это HIG-поведение, не боремся.
///
/// Что переопределяем:
/// - selection-цвет: vanilla list selection использует system controlAccentColor
///   (синий), который из SPM-таргета без AccentColor asset не переопределить.
///   Поэтому рисуем pill вручную через `.listRowBackground` (так же как в
///   `MainContentView.sidebarRow(for:)`).
/// - sidebar toggle убран (юзер: «не должно быть возможности скрыть»).
/// - top inset под traffic-lights — `.safeAreaInset(.top)`, потому что
///   Settings scene без toolbar не резервирует safe-area сверху.
struct PreferencesView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var selected: PreferencesTab = .app
    @State private var settingsWindow: NSWindow?

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(PreferencesTab.allCases, id: \.self) { tab in
                    sidebarRow(for: tab)
                }
            }
            .scrollContentBackground(.hidden)
            .background(BlikPalette.surface.resolve(colorScheme))
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 28)
            }
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailView
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: 28)
                }
                .toolbar(removing: .sidebarToggle)
        }
        .frame(minWidth: 820, minHeight: 560)
        .tint(DesignTokens.accent.resolve(colorScheme))
        .background(WindowAccessor(window: $settingsWindow))
        .onAppear { if let settingsWindow { centerOverMain(settingsWindow) } }
        .onChange(of: settingsWindow) { _, window in
            if let window { centerOverMain(window) }
        }
    }

    /// Центрирует окно настроек поверх главного окна приложения (а не в
    /// «случайном» месте). Главное окно ищем по identifier `main`, затем по
    /// заголовку `.blik`, иначе берём самое широкое видимое окно; fallback —
    /// центр экрана.
    private func centerOverMain(_ settings: NSWindow) {
        let others = NSApp.windows.filter { $0 != settings && $0.isVisible }
        let main = others.first { $0.identifier?.rawValue == "main" }
            ?? others.first { $0.title == ".blik" }
            ?? others.max { $0.frame.width < $1.frame.width }
        guard let main else {
            settings.center()
            return
        }
        let m = main.frame
        let s = settings.frame
        let origin = NSPoint(x: m.midX - s.width / 2, y: m.midY - s.height / 2)
        settings.setFrameOrigin(origin)
    }

    @ViewBuilder
    private func sidebarRow(for tab: PreferencesTab) -> some View {
        let isSelected = selected == tab
        let isWindowKey = controlActiveState == .key
        let textColor: Color = isSelected && isWindowKey ? Color.white : Color.primary

        Button {
            selected = tab
        } label: {
            Label(tab.title, systemImage: tab.systemImage)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowFill(isSelected: isSelected, isWindowKey: isWindowKey))
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
        )
    }

    private func rowFill(isSelected: Bool, isWindowKey: Bool) -> Color {
        guard isSelected else { return .clear }
        if isWindowKey {
            return DesignTokens.accent.resolve(colorScheme)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selected {
        case .app: AppPage()
        case .about: AboutPage()
        }
    }
}

enum PreferencesTab: String, CaseIterable, Hashable {
    case app, about

    var title: String {
        switch self {
        case .app: return "Приложение"
        case .about: return "О программе"
        }
    }

    var systemImage: String {
        switch self {
        case .app: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}
