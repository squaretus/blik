import SwiftUI

/// Группа пресетов скорости (0/25/50/75/100) — нативный segmented Picker.
public struct BlikPresetButtons: View {
    public enum Size {
        case regular
        case compact
    }

    private let currentPreset: Int
    private let presets: [Int]
    private let autoLabel: String
    private let size: Size
    private let onSelect: (Int) -> Void

    public init(
        currentPreset: Int,
        presets: [Int] = [0, 25, 50, 75, 100],
        autoLabel: String = "Авто",
        size: Size = .regular,
        onSelect: @escaping (Int) -> Void
    ) {
        self.currentPreset = currentPreset
        self.presets = presets
        self.autoLabel = autoLabel
        self.size = size
        self.onSelect = onSelect
    }

    public var body: some View {
        Picker(
            "Скорость",
            selection: Binding(
                get: { currentPreset },
                set: { onSelect($0) }
            )
        ) {
            ForEach(presets, id: \.self) { preset in
                Text(label(for: preset)).tag(preset)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(size == .compact ? .small : .regular)
    }

    private func label(for preset: Int) -> String {
        preset == 0 ? autoLabel : "\(preset)%"
    }
}
