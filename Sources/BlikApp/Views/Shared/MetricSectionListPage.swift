import SwiftUI
import BlikShared
import BlikCore
import BlikDesign

/// Одна секция списка метрик (группа): заголовок + опциональный badge + строки.
struct MetricSection: Identifiable {
    let id: String
    let title: String
    /// Бейдж справа в заголовке секции (например «avg 56°C» или «45%»).
    let badge: MetricBadge?
    let rows: [MetricRow]

    init(id: String, title: String, badge: MetricBadge? = nil, rows: [MetricRow]) {
        self.id = id
        self.title = title
        self.badge = badge
        self.rows = rows
    }
}

struct MetricBadge {
    let text: String
    let color: Color
}

/// Строка метрики: label + значение (цветное, моноширинное).
struct MetricRow: Identifiable {
    let id: String
    let label: String
    let value: String
    let color: Color
    /// Термины для поиска (RU + EN). Пустой query → показываем всё.
    let searchTerms: [String]
    /// Стабильный ключ метрики для инлайн-переименования (`MetricKey.*`).
    /// nil → строка не переименовывается (label рендерится обычным `Text`).
    let renameKey: String?
    /// Дефолтное имя для переименования (обычно совпадает с `label`).
    let defaultLabel: String?

    init(id: String, label: String, value: String, color: Color, searchTerms: [String] = [],
         renameKey: String? = nil, defaultLabel: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.color = color
        self.searchTerms = searchTerms.isEmpty ? [label] : searchTerms
        self.renameKey = renameKey
        self.defaultLabel = defaultLabel
    }
}

/// Общий каркас вкладок-списков метрик («Температура», «Ресурсы»): единый
/// `BlikPageContainer` + auth/subscription gating + поиск + рендер секций.
/// Конкретные вкладки лишь собирают `[MetricSection]` и передают сюда.
struct MetricSectionListPage<Leading: View>: View {
    let sections: [MetricSection]
    /// Доп. кастомные секции ПЕРЕД метрик-секциями (напр. куллеры + управление
    /// в начале вкладки «Температура»). По умолчанию — `EmptyView` (convenience-init).
    private let leading: Leading

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.searchQuery) private var searchQuery

    init(sections: [MetricSection], @ViewBuilder leading: () -> Leading) {
        self.sections = sections
        self.leading = leading()
    }

    var body: some View {
        BlikPageContainer {
            metricsList
        }
    }

    private var metricsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BlikPageMetrics.sectionSpacing) {
                leading
                ForEach(visibleSections) { section in
                    MetricPanel(section: filtered(section))
                }
            }
            .padding(.vertical, 6)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    /// Секция с отфильтрованными по поиску строками. Если заголовок совпал с
    /// query — показываем все строки; пустой query — всю секцию.
    private func filtered(_ section: MetricSection) -> MetricSection {
        let q = trimmedQuery
        guard !q.isEmpty, !section.title.localizedCaseInsensitiveContains(q) else { return section }
        return MetricSection(id: section.id, title: section.title, badge: section.badge,
                             rows: section.rows.filter(matchesSearch))
    }

    // MARK: - Search

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespaces)
    }

    /// Секция видима, если её заголовок совпадает с query или есть видимые строки.
    private var visibleSections: [MetricSection] {
        let q = trimmedQuery
        guard !q.isEmpty else { return sections }
        return sections.filter { section in
            section.title.localizedCaseInsensitiveContains(q)
                || section.rows.contains(where: matchesSearch)
        }
    }

    private func matchesSearch(_ row: MetricRow) -> Bool {
        let q = trimmedQuery
        guard !q.isEmpty else { return true }
        if let title = sections.first(where: { $0.rows.contains(where: { $0.id == row.id }) })?.title,
           title.localizedCaseInsensitiveContains(q) {
            return true
        }
        return row.searchTerms.contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

/// Без leading-секций — стандартный список метрик (`Ресурсы`).
extension MetricSectionListPage where Leading == EmptyView {
    init(sections: [MetricSection]) {
        self.init(sections: sections) { EmptyView() }
    }
}
