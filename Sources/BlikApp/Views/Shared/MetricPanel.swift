import SwiftUI
import BlikShared
import BlikCore
import BlikDesign

/// Карточка-секция вкладок метрик (Обзор/Температура/Ресурсы): заголовок + бейдж +
/// строки. Единый «плиточный» стиль (`BlikPanel`), как модули на «Графиках».
/// Строки с `renameKey` поддерживают инлайн-переименование (`EditableMetricLabel`).
struct MetricPanel: View {
    let section: MetricSection

    var body: some View {
        TitledCard(title: section.title,
                   badgeText: section.badge?.text,
                   badgeColor: section.badge?.color ?? .secondary) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(section.rows) { row in
                    metricRow(row)
                }
            }
        }
    }

    @ViewBuilder
    private func metricRow(_ row: MetricRow) -> some View {
        HStack(spacing: 8) {
            if let key = row.renameKey {
                EditableMetricLabel(key: key, defaultName: row.defaultLabel ?? row.label)
            } else {
                Text(row.label)
            }
            Spacer(minLength: 8)
            Text(verbatim: row.value)
                .foregroundStyle(row.color)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}
