import Combine
import Foundation

@MainActor
final class ClipboardViewState: ObservableObject {
    @Published var query = "" { didSet { refresh(store.items) } }
    @Published var filter: ClipboardKind? { didSet { refresh(store.items) } }
    @Published var selectedID: UUID?
    @Published var showActions = false
    private(set) var actionPresentationID = UUID()
    @Published private(set) var visibleItems: [ClipboardItem] = []
    private let store: ClipboardStore
    private var subscription: AnyCancellable?

    init(store: ClipboardStore) {
        self.store = store
        subscription = store.$items.sink { [weak self] items in self?.refresh(items) }
    }

    var selectedItem: ClipboardItem? { visibleItems.first { $0.id == selectedID } ?? visibleItems.first }

    func toggleActions() {
        if showActions {
            showActions = false
        } else if selectedItem != nil {
            actionPresentationID = UUID()
            showActions = true
        }
    }

    func select(offset: Int) {
        guard !visibleItems.isEmpty else { selectedID = nil; return }
        let current = visibleItems.firstIndex { $0.id == selectedID } ?? 0
        selectedID = visibleItems[min(max(current + offset, 0), visibleItems.count - 1)].id
    }

    func selectFirstIfNeeded() {
        if !visibleItems.contains(where: { $0.id == selectedID }) { selectedID = visibleItems.first?.id }
    }

    func cycleFilter() {
        let options: [ClipboardKind?] = [nil] + ClipboardKind.allCases.map(Optional.some)
        let index = options.firstIndex(where: { $0 == filter }) ?? 0
        filter = options[(index + 1) % options.count]
    }

    private func refresh(_ items: [ClipboardItem]) {
        visibleItems = HistoryPolicy.matching(items, query: query, kind: filter)
        selectFirstIfNeeded()
        if visibleItems.isEmpty { showActions = false }
    }
}
