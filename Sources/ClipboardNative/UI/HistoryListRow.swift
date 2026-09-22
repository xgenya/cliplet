import Foundation

enum HistorySection: String, CaseIterable {
    case pinned = "Pinned", today = "Today", yesterday = "Yesterday", earlier = "Earlier"
}

enum HistoryListRow: Identifiable {
    enum ID: Hashable {
        case header(HistorySection)
        case item(UUID)
    }

    case header(HistorySection)
    case item(ClipboardItem)

    var id: ID {
        switch self {
        case .header(let section): return .header(section)
        case .item(let item): return .item(item.id)
        }
    }

    static func make(_ items: [ClipboardItem], now: Date = Date(), calendar: Calendar = .current) -> [Self] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        var groups: [HistorySection: [ClipboardItem]] = [:]
        for item in items {
            let section: HistorySection
            if item.isPinned {
                section = .pinned
            } else if item.createdAt >= today && item.createdAt < tomorrow {
                section = .today
            } else if item.createdAt >= yesterday && item.createdAt < today {
                section = .yesterday
            } else {
                section = .earlier
            }
            groups[section, default: []].append(item)
        }
        return HistorySection.allCases.flatMap { section -> [Self] in
            guard let items = groups[section] else { return [] }
            return [.header(section)] + items.map(Self.item)
        }
    }
}
