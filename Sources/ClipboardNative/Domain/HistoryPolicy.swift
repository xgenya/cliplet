import Foundation

/// Pure history rules: independent of windows, preferences storage and the clock.
enum HistoryPolicy {
    static func retained(_ items: [ClipboardItem], days: Int, maximum: Int, now: Date) -> [ClipboardItem] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -max(days, 1), to: now) ?? now
        let sorted = items.filter { $0.isPinned || $0.createdAt >= cutoff }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard maximum > 0 else { return sorted }
        let pinned = sorted.filter(\.isPinned)
        return pinned + sorted.filter { !$0.isPinned }.prefix(max(0, maximum - pinned.count))
    }

    static func matching(_ items: [ClipboardItem], query: String, kind: ClipboardKind?) -> [ClipboardItem] {
        let needle = query.normalizedForClipboard.localizedLowercase
        return items.filter {
            (kind == nil || $0.kind == kind)
                && (needle.isEmpty || $0.searchableText.localizedLowercase.contains(needle))
        }
    }
}
