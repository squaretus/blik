import SwiftUI
import BlikCore
import BlikShared
import AppKit

/// Singleton-гейт через named Mach port.
/// Защищает от запуска нескольких бинарников напрямую (терминал, debug).
private final class SingleInstanceGuard {
    static let portName = "com.blik.menubar.singleton" as CFString
    private var port: CFMessagePort?

    /// Возвращает true если это единственный экземпляр.
    func acquire() -> Bool {
        var context = CFMessagePortContext()
        var isRemote: DarwinBoolean = false

        port = CFMessagePortCreateLocal(nil, Self.portName, { _, _, _, _ in
            return nil
        }, &context, &isRemote)

        return port != nil
    }
}

@main
struct BlikMenuBarApp: App {
    @State private var coordinator = AppCoordinator()
    private static let guard_ = SingleInstanceGuard()

    init() {
        if !Self.guard_.acquire() {
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            return
        }
        // BlikMenuBar — accessory app (без иконки в Dock), в отличие от BlikApp.
        // Раньше этот вызов жил в `SMCViewModel.init`; перенесён сюда после миграции на @Observable.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            FanDetailView()
                .environment(coordinator)
                .frame(width: 340)
        } label: {
            MenuBarLabel()
                .environment(coordinator)
        }
        .menuBarExtraStyle(.window)
    }
}
