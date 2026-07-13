import SwiftUI
import AppKit
import BlikCore
import BlikShared
import BlikDesign

struct MenuBarLabel: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        if !coordinator.fan.isConnected {
            Text(".blik: —")
        } else {
            // Читаем квантованный проектор (`menu*`), а НЕ сырые fans/sensors —
            // body пере-вычисляется лишь при смене отображаемого числа, не каждый
            // poll-тик. Снижает частоту обновления always-live status-item.
            let image = MenuBarImageRenderer.image(
                fan0: coordinator.fan.menuFan0RPM ?? 0,
                fan1: coordinator.fan.menuFan1RPM,
                temp: coordinator.fan.menuChipTemp ?? 0
            )
            Image(nsImage: image)
        }
    }
}
