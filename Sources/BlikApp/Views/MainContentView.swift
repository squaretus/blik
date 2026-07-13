import SwiftUI
import BlikShared
import BlikDesign
import AppKit

enum AppTheme: String, CaseIterable {
    case dark = "Тёмная"
    case light = "Светлая"
}

struct MainContentView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var selectedTab: SidebarTab? = .overview
    @State private var searchQuery: String = ""
    @AppStorage("appTheme") private var appTheme: String = AppTheme.dark.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.openSettings) private var openSettings

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appTheme) ?? .dark
    }

    var body: some View {
        splitView
            .navigationTitle("")
            .searchable(text: $searchQuery, prompt: "Поиск")
            .toolbar { trailingSpacerItem }
            // Прячем СЕРЫЙ системный материал тулбара: он перекрывал тёмный фон,
            // заведённый под бар через `backgroundExtensionEffect()` в detail
            // (см. splitView). Без материала проявляется тёмная тема — бар
            // сливается с контентом, без серой полосы и hairline-сепаратора.
            // Поиск остаётся (item на своей glass-капсуле). Раньше `.hidden` без
            // тёмного фона под баром давал серый фон окна — теперь фон есть.
            .toolbarBackground(.hidden, for: .windowToolbar)
            .environment(\.searchQuery, searchQuery)
            .tint(DesignTokens.accent.resolve(colorScheme))
            .font(DesignTokens.fontPrimary)
            .preferredColorScheme(selectedTheme == .dark ? .dark : .light)
            .onChange(of: coordinator.pendingTab) {
                if let tab = coordinator.pendingTab {
                    selectedTab = tab
                    coordinator.pendingTab = nil
                }
            }
            .onChange(of: coordinator.fan.shouldTerminate) {
                if coordinator.fan.shouldTerminate {
                    NSApplication.shared.terminate(nil)
                }
            }
    }

    private var splitView: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List {
                    ForEach(SidebarTab.allCases, id: \.self) { tab in
                        sidebarRow(for: tab)
                    }
                }
                .scrollContentBackground(.hidden)
                settingsButton
            }
            .background(BlikPalette.surface.resolve(colorScheme))
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            // Канон macOS 26 (WWDC25 «Build a SwiftUI app with the new design»):
            // тёмная тема заводится под системное Liquid Glass стекло тулбара
            // через `backgroundExtensionEffect()` на фоновом слое detail-колонки.
            // Этот API создаёт размытую зеркальную копию фона в safe-area, с
            // которой стекло адаптируется (translucent), — в отличие от сплошного
            // `ignoresSafeArea`-фона, который читается как opaque. Только detail →
            // сайдбар не затрагивается.
            ZStack {
                BlikPalette.bg.resolve(colorScheme)
                    .backgroundExtensionEffect()
                detailView
            }
        }
    }

    /// Открыть нативный Settings-window через SwiftUI-окружение.
    private var settingsButton: some View {
        OpenSettingsButton()
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab ?? .overview {
        case .overview: OverviewPage()
        case .temperature: SensorsPage()
        case .resources: ResourcesPage()
        case .charts: ChartsPage()
        }
    }

    /// macOS 26: материализуем search field как явный `DefaultToolbarItem(kind: .search)`,
    /// тогда последующий `ToolbarSpacer(.fixed)` реально сдвигает его влево.
    @ToolbarContentBuilder
    private var trailingSpacerItem: some ToolbarContent {
        DefaultToolbarItem(kind: .search, placement: .primaryAction)
        ToolbarSpacer(.fixed, placement: .primaryAction)
    }

    /// Минимальный кастомный row сайдбара: нативная List-pill, но selection
    /// окрашивается в наш accent (а не в системный controlAccentColor — синий).
    /// `controlAccentColor` в SPM-таргете без Asset Catalog AccentColor через
    /// SwiftUI не переопределить, поэтому единственный способ получить бренд-цвет —
    /// рисовать selection-фон через `.listRowBackground` вручную.
    @ViewBuilder
    private func sidebarRow(for tab: SidebarTab) -> some View {
        let isSelected = selectedTab == tab
        // Акцент держим, только пока окно — key. При потере key-статуса
        // (Cmd-Tab, открыт sheet/popover, другое окно процесса в фокусе)
        // сайдбар дим-серым — так делает System Settings.app.
        let isWindowKey = controlActiveState == .key

        let textColor: Color = isSelected && isWindowKey ? Color.white : Color.primary
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(textColor)
                    .frame(width: 18)
                Text(tab.title)
                    .foregroundStyle(textColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
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
}
