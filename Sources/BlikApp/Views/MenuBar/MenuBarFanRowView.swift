import SwiftUI
import BlikCore
import BlikDesign

struct MenuBarFanRowView: View {
    let fan: FanInfo

    var body: some View {
        let ratio = fan.actualSpeed / max(1, fan.maximumSpeed)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "Fan \(fan.id)")
                    .font(.headline)

                Text(verbatim: "\(Int(fan.actualSpeed)) RPM")
                    .font(.system(.body, design: .monospaced))

                Spacer()

                Text(fan.isForced ? "MANUAL" : "AUTO")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(fan.isForced ? DesignTokens.amber.opacity(0.8) : DesignTokens.green.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            ProgressView(value: fan.actualSpeed, total: max(1, fan.maximumSpeed))
                .tint(tintForRatio(ratio))
        }
        .padding(.vertical, 2)
    }

    private func tintForRatio(_ ratio: Double) -> Color {
        if ratio > 0.8 { return DesignTokens.red }
        if ratio > 0.5 { return DesignTokens.amber }
        return DesignTokens.green
    }
}
