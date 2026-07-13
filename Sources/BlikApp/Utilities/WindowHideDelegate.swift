import SwiftUI
import UserNotifications
import BlikDesign

/// Перехватывает закрытие окна — скрывает вместо закрытия.
/// Приложение продолжает работать в MenuBar.
final class WindowHideDelegate: NSObject, NSWindowDelegate {
    private var hasShownNotification = false

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        showBackgroundNotificationIfNeeded()
        return false
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        var size = frameSize
        if size.width < DesignTokens.windowMinWidth {
            size.width = DesignTokens.windowMinWidth
        }
        if size.height < DesignTokens.windowMinHeight {
            size.height = DesignTokens.windowMinHeight
        }
        return size
    }

    private func showBackgroundNotificationIfNeeded() {
        guard !hasShownNotification else { return }
        hasShownNotification = true

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = ".blik"
            content.body = "Приложение работает в фоне в строке меню"
            let request = UNNotificationRequest(
                identifier: "blik-background-mode",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
