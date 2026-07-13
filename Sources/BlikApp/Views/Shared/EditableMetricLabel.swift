import SwiftUI
import BlikShared
import BlikDesign

/// Инлайн-переименование метрики без иконки карандаша:
/// hover → подсветка фона; клик → `TextField`; автосейв при потере фокуса и по
/// Enter; пустое значение сбрасывает к дефолту; Esc отменяет правку.
///
/// Имя хранится в общем `coordinator.metricNames` (suite `com.blik.shared`).
struct EditableMetricLabel: View {
    let key: String
    let defaultName: String

    @Environment(AppCoordinator.self) private var coordinator
    @State private var isEditing = false
    @State private var isHovering = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField(defaultName, text: $draft)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.fontPrimary)
                    .focused($focused)
                    .onSubmit { commit() }
                    .onExitCommand { cancel() }
                    .onChange(of: focused) { _, nowFocused in
                        if !nowFocused { commit() }
                    }
            } else {
                Text(coordinator.metricNames.displayName(for: key, default: defaultName))
                    .font(DesignTokens.fontPrimary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isHovering ? Color.secondary.opacity(0.15) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onHover { isHovering = $0 }
                    .help("Переименовать")
                    .onTapGesture { beginEditing() }
            }
        }
    }

    private func beginEditing() {
        // Поле заполнено кастомным именем; для дефолтного — пустое.
        draft = coordinator.metricNames.names[key] ?? ""
        isEditing = true
        focused = true
    }

    private func commit() {
        guard isEditing else { return }
        coordinator.metricNames.setName(draft, for: key)
        isEditing = false
        isHovering = false
    }

    private func cancel() {
        isEditing = false
        isHovering = false
    }
}
