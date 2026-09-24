import Combine
import Foundation

@MainActor
final class ClipboardViewState: ObservableObject {
    @Published var query = "" { didSet { refresh(store.items) } }
    @Published var filter: ClipboardKind? { didSet { refresh(store.items) } }
    @Published var selectedID: UUID?
    @Published var showActions = false
    private(set) var actionPresentationID = UUID()
    /// Changes each time the panel opens, so the view can play its entrance.
    @Published private(set) var panelPresentationCount = 0
    @Published private(set) var visibleItems: [ClipboardItem] = []
    @Published private(set) var listRows: [HistoryListRow] = []
    private var itemIndices: [UUID: Int] = [:]
    private let store: ClipboardStore
    private var subscription: AnyCancellable?
    private var calendarSubscription: AnyCancellable?

    init(store: ClipboardStore) {
        self.store = store
        subscription = store.$items.sink { [weak self] items in self?.refresh(items) }
        calendarSubscription = NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                self.listRows = HistoryListRow.make(self.visibleItems)
            }
    }

    var selectedItem: ClipboardItem? {
        if let selectedID, let index = itemIndices[selectedID] { return visibleItems[index] }
        return visibleItems.first
    }

    func notePanelPresented() { panelPresentationCount += 1 }

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
        let current = selectedID.flatMap { itemIndices[$0] } ?? 0
        selectedID = visibleItems[min(max(current + offset, 0), visibleItems.count - 1)].id
    }

    func selectFirstIfNeeded() {
        if selectedID.flatMap({ itemIndices[$0] }) == nil { selectedID = visibleItems.first?.id }
    }

    func cycleFilter() {
        let options: [ClipboardKind?] = [nil] + ClipboardKind.allCases.map(Optional.some)
        let index = options.firstIndex(where: { $0 == filter }) ?? 0
        filter = options[(index + 1) % options.count]
    }

    private func refresh(_ items: [ClipboardItem]) {
        visibleItems = HistoryPolicy.matching(items, query: query, kind: filter)
        itemIndices = Dictionary(
            visibleItems.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        listRows = HistoryListRow.make(visibleItems)
        selectFirstIfNeeded()
        if visibleItems.isEmpty { showActions = false }
    }
}
