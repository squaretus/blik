import SwiftUI
import BlikCore

struct SensorSectionView: View {
    let group: SensorGroup
    let sensors: [SensorInfo]

    private var averageTemp: Double {
        guard !sensors.isEmpty else { return 0 }
        return sensors.map(\.temperature).reduce(0, +) / Double(sensors.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(group.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("avg \(String(format: "%.0f", averageTemp))\u{00B0}C")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 2
            ) {
                ForEach(sensors, id: \.key) { sensor in
                    HStack(spacing: 4) {
                        Text(sensor.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        Text("\(String(format: "%.0f", sensor.temperature))\u{00B0}C")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(temperatureColor(sensor.temperature))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func temperatureColor(_ temp: Double) -> Color {
        switch temp {
        case ..<60:
            return .green
        case 60..<85:
            return .orange
        default:
            return .red
        }
    }
}
