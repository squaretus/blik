import SwiftUI
import BlikShared
import BlikCore
import BlikDesign

/// О программе: логотип, версия, обновления, ссылка на GitHub, destructive Удалить .blik.
struct AboutPage: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var showConfirmation = false

    var body: some View {
        BlikPageContainer {
            List {
                Section {
                    HStack(spacing: 18) {
                        BlikLogo(size: .xl)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Версия \(Constants.appVersion)").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .listRowInsets(BlikPageMetrics.rowInsets)

                Section("Обновления") {
                    HStack(spacing: 8) {
                        Text("Проверить обновления").fontWeight(.medium)
                        Spacer()
                        Button("Проверить") {
                            coordinator.update.checkForUpdateManually()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let result = coordinator.update.manualUpdateResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    updateAvailableBanner
                }
                .listRowInsets(BlikPageMetrics.rowInsets)

                Section("Ссылки") {
                    Link(
                        "GitHub",
                        destination: URL(string: "https://github.com/\(Constants.githubOwner)/\(Constants.githubRepo)")!
                    )
                }
                .listRowInsets(BlikPageMetrics.rowInsets)

                Section("Опасная зона") {
                    HStack(spacing: 8) {
                        Text("Удалить .blik").fontWeight(.medium)
                        Spacer()
                        Button("Удалить", role: .destructive) {
                            showConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.red)
                    }
                }
                .listRowInsets(BlikPageMetrics.rowInsets)
                .confirmationDialog(
                    "Удалить .blik?",
                    isPresented: $showConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Удалить", role: .destructive) {
                        coordinator.uninstallApp()
                    }
                    Button("Отмена", role: .cancel) {}
                } message: {
                    Text("Будут удалены приложение, daemon, CLI и все настройки. Это действие нельзя отменить.")
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    @ViewBuilder
    private var updateAvailableBanner: some View {
        if let update = coordinator.update.availableUpdate, update.isNewer {
            if coordinator.update.isInstallingUpdate {
                BlikBanner(
                    tone: .info,
                    systemImage: nil,
                    text: "Установка обновления..."
                ) {
                    ProgressView().controlSize(.small)
                }
            } else {
                BlikBanner(
                    tone: .info,
                    systemImage: "arrow.down.circle.fill",
                    text: "Доступно обновление v\(update.latestVersion)"
                ) {
                    Button("Обновить") { coordinator.update.installUpdate() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
