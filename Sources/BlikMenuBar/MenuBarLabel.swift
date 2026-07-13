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
            let image = MenuBarImageRenderer.image(
                fan0: Int(coordinator.fan.fans.first?.actualSpeed ?? 0),
                fan1: coordinator.fan.fans.count > 1 ? Int(coordinator.fan.fans[1].actualSpeed) : nil,
                temp: coordinator.fan.averageChipTemp
            )
            Image(nsImage: image)
        }
    }
}
