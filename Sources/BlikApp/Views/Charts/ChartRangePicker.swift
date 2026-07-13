import SwiftUI
import BlikShared
import BlikDesign

/// Контрол окна графиков: нативный тумблер **Live** + селектор **периода**.
/// Live on — окно слежения за `now` (можно сравнить «что было N часов назад» и
/// «сейчас»); Live off — фиксированный диапазон `[now − период, now]`
/// (+ «свой диапазон…»). Период активен в обоих режимах.
struct ChartRangePicker: View {
    let mode: ChartMode
    let liveWindowSeconds: TimeInterval
    /// Войти/остаться в Live с окном длительностью `seconds`.
    let onLive: (TimeInterval) -> Void
    /// Перейти в фиксированный исторический диапазон.
    let onRange: (ChartTimeRange) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCustom = false
    @State private var customFrom = Date().addingTimeInterval(-3600)
    @State private var customTo = Date()

    var body: some View {
        // Контролы прижаты вправо (под поиском): селектор времени, затем Live-тумблер
        // у самой границы — выровнен с правым краем плиток/контента.
        HStack(spacing: 14) {
            Spacer(minLength: 0)

            Menu {
                ForEach(ChartRangePreset.allCases) { preset in
                    Button(preset.title) { selectPeriod(preset.seconds) }
                }
                if !isLive {
                    Divider()
                    Button("Свой диапазон…") { showingCustom = true }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: periodLabel)
                        .font(DesignTokens.fontPrimaryMedium)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .menuIndicator(.hidden)
            .popover(isPresented: $showingCustom, arrowEdge: .bottom) {
                customEditor
            }

            Toggle("Live", isOn: liveBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(DesignTokens.fontPrimaryMedium)
                .fixedSize()
        }
    }

    // MARK: - State

    private var isLive: Bool {
        if case .live = mode { return true }
        return false
    }

    /// Текущая длительность окна: live → окно слежения, range → охват диапазона.
    private var currentSeconds: TimeInterval {
        switch mode {
        case .live:         return liveWindowSeconds
        case .range(let r): return r.span
        }
    }

    private var liveBinding: Binding<Bool> {
        Binding(
            get: { isLive },
            set: { on in
                if on { onLive(currentSeconds) } else { onRange(rangeFor(currentSeconds)) }
            },
        )
    }

    private var periodLabel: String {
        if let preset = ChartRangePreset.allCases.first(where: { abs($0.seconds - currentSeconds) < 1 }) {
            return preset.title
        }
        return "Свой диапазон"
    }

    // MARK: - Actions

    private func selectPeriod(_ seconds: TimeInterval) {
        if isLive {
            onLive(seconds)
        } else {
            onRange(rangeFor(seconds))
        }
    }

    private func rangeFor(_ seconds: TimeInterval) -> ChartTimeRange {
        let now = Date()
        return ChartTimeRange(from: now.addingTimeInterval(-seconds), to: now)
    }

    // MARK: - Custom range

    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Свой диапазон")
                .font(DesignTokens.fontPrimaryMedium)
            DatePicker("С", selection: $customFrom, in: ...customTo)
                .font(DesignTokens.fontPrimary)
            DatePicker("По", selection: $customTo)
                .font(DesignTokens.fontPrimary)
            Text("Не глубже 7 дней — диапазон клампится автоматически.")
                .font(DesignTokens.fontSecondary)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button {
                    onRange(ChartTimeRange(from: customFrom, to: customTo))
                    showingCustom = false
                } label: {
                    Text("Применить")
                        .font(DesignTokens.fontPrimaryMedium)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.accent.resolve(colorScheme))
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
