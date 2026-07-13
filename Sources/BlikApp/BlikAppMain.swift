import SwiftUI
import BlikShared
import BlikDesign
import AppKit

// MARK: - Singleton Guard

private final class SingleInstanceGuard {
    static let portName = "com.blik.app.singleton" as CFString
    private var port: CFMessagePort?

    func acquire() -> Bool {
        var context = CFMessagePortContext()
        var isRemote: DarwinBoolean = false
        port = CFMessagePortCreateLocal(nil, Self.portName, { _, _, _, _ in
            return nil
        }, &context, &isRemote)
        return port != nil
    }
}

// MARK: - App Entry Point

@main
struct BlikAppEntry: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var coordinator = AppCoordinator()
    @AppStorage("appTheme") private var appTheme: String = AppTheme.dark.rawValue
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window(".blik", id: "main") {
            MainContentView()
                .environment(coordinator)
                .onAppear {
                    delegate.setupWindowDelegate()
                    delegate.consumePendingDeepLink(into: coordinator)
                    updateDockIcon()
                }
                .onChange(of: appTheme) {
                    updateDockIcon()
                }
                .onOpenURL { url in
                    coordinator.handleDeepLink(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: .deepLinkReceived)) { note in
                    if let url = note.userInfo?["url"] as? URL {
                        coordinator.handleDeepLink(url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in
                    openWindow(id: "main")
                    DispatchQueue.main.async {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
        }
        .defaultSize(
            width: DesignTokens.windowMinWidth,
            height: DesignTokens.windowMinHeight
        )
        .windowResizability(.contentMinSize)

        // Нативный SwiftUI `Settings` scene — auto-привязка к menu "Blik → Settings…" + ⌘,.
        //
        // `.onOpenURL` НЕ дублируем сюда: AppDelegate.application(_:open:) перехватывает
        // Apple Event и публикует через `.deepLinkReceived` notification. Main Window
        // получает URL через `.onOpenURL` (cold-start) и notification publisher (warm).
        // Settings scene получать URL отдельно не нужно — coordinator dedup'нет повтор.
        Settings {
            PreferencesView()
                .environment(coordinator)
                .preferredColorScheme(appTheme == AppTheme.light.rawValue ? .light : .dark)
        }

        MenuBarExtra {
            MenuBarPopupView()
                .environment(coordinator)
                .preferredColorScheme(appTheme == AppTheme.light.rawValue ? .light : .dark)
        } label: {
            MenuBarLabel()
                .environment(coordinator)
        }
        .menuBarExtraStyle(.window)
    }

    private func updateDockIcon() {
        let name = appTheme == AppTheme.light.rawValue ? "dock_icon_light" : "dock_icon_dark"
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let singletonGuard = SingleInstanceGuard()
    private let windowDelegate = WindowHideDelegate()

    /// Cold-start backstop для URL scheme: AppDelegate `application(_:open:)` вызывается до того,
    /// как SwiftUI-сцена `.onOpenURL` способна получать события. Сохраняем URL'ы во временный
    /// буфер и применяем их к `AppCoordinator` через `.onAppear` главного окна (см. `consumePendingDeepLink`).
    private var pendingDeepLinkURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !Self.singletonGuard.acquire() {
            // Активировать существующий экземпляр и завершить дубль
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            return
        }

        // Показать в Dock
        NSApplication.shared.setActivationPolicy(.regular)

        // Минимальный размер окна
        DispatchQueue.main.async {
            let minSize = NSSize(
                width: DesignTokens.windowMinWidth,
                height: DesignTokens.windowMinHeight
            )
            for window in NSApplication.shared.windows {
                window.minSize = minSize
                var frame = window.frame
                var changed = false
                if frame.size.width < minSize.width {
                    frame.size.width = minSize.width
                    changed = true
                }
                if frame.size.height < minSize.height {
                    frame.size.height = minSize.height
                    changed = true
                }
                if changed {
                    window.setFrame(frame, display: true)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Клик на иконку в Dock — показать окно.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    /// Handler для URL scheme. Если SwiftUI Window ещё не готов (cold-start) — буферим
    /// в `pendingDeepLinkURLs`, иначе сразу пробрасываем через NotificationCenter.
    ///
    /// Без NotificationCenter SwiftUI `.onOpenURL` не выстреливает: реализация
    /// `application(_:open:)` перехватывает Apple Event раньше SwiftUI и event
    /// до сцены не доходит.
    ///
    /// Main window мог быть закрыт юзером (WindowHideDelegate скрывает окно при
    /// close) — поэтому безусловно показываем main window при любом deep-link'е.
    func application(_ application: NSApplication, open urls: [URL]) {
        pendingDeepLinkURLs.append(contentsOf: urls)
        NSApplication.shared.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: .showMainWindow, object: nil)
        for url in urls {
            NotificationCenter.default.post(
                name: .deepLinkReceived,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }

    /// Вызывается из `MainContentView.onAppear` — replay буферизованных
    /// cold-start URL'ов (notification, выпущенный до появления subscriber'а,
    /// был потерян). Удаляет URL'ы из буфера после replay.
    @MainActor
    func consumePendingDeepLink(into coordinator: AppCoordinator) {
        let urls = pendingDeepLinkURLs
        pendingDeepLinkURLs.removeAll()
        for url in urls {
            coordinator.handleDeepLink(url)
        }
    }

    /// Назначить WindowHideDelegate на главное окно (вызывается из onAppear).
    func setupWindowDelegate() {
        DispatchQueue.main.async { [self] in
            for window in NSApplication.shared.windows where window.canBecomeMain {
                window.delegate = windowDelegate
                window.minSize = NSSize(
                    width: DesignTokens.windowMinWidth,
                    height: DesignTokens.windowMinHeight
                )
                // Chrome (titlebar/toolbar/sidebar glass) отдаём системе целиком:
                // НЕ трогаем `titlebarAppearsTransparent`/`backgroundColor`.
                // `backgroundColor` красит ВСЁ окно, включая стекло сайдбара →
                // ломает его вид. Тему под тулбар заводим точечно в detail-колонке
                // через `backgroundExtensionEffect()` (см. MainContentView) —
                // canonical macOS 26 паттерн, не затрагивает сайдбар.
                break
            }
        }
    }

    private func showMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: .showMainWindow, object: nil)
    }
}

extension Notification.Name {
    static let showMainWindow = Notification.Name("showMainWindow")
    static let deepLinkReceived = Notification.Name("blik.deepLinkReceived")
}
