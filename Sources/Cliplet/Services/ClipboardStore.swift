import Combine
import Foundation
import OSLog

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var storageError: String?

    private let settings: AppSettings
    private let repository: HistoryPersistence
    private let now: () -> Date
    private var revision = 0
    private var maintenanceTimer: Timer?
    private var settingsSubscription: AnyCancellable?
    private let logger = Logger(subsystem: "com.clipboardnative.macos", category: "history")

    init(
        settings: AppSettings, repository: HistoryPersistence,
        now: @escaping () -> Date = Date.init, maintenanceInterval: TimeInterval? = 60
    ) {
        self.settings = settings
        self.repository = repository
        self.now = now
        do { items = try repository.load() } catch { report(error) }
        applyRetentionPolicy()
        settingsSubscription = settings.$retentionDays.combineLatest(settings.$maximumItems)
            .dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.applyRetentionPolicy()
            }
        if let maintenanceInterval {
            let timer = Timer(timeInterval: maintenanceInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.applyRetentionPolicy() }
            }
            RunLoop.main.add(timer, forMode: .common)
            maintenanceTimer = timer
        }
    }

    @discardableResult
    func add(_ item: ClipboardItem) -> UUID {
        var item = item
        var updated = items
        if let index = updated.firstIndex(where: { $0.contentHash == item.contentHash }) {
            let existing = updated.remove(at: index)
            item.id = existing.id
            item.isPinned = existing.isPinned
            item.customName = existing.customName
            item.useCount = existing.useCount
            item.lastUsedAt = existing.lastUsedAt
            // Preserve completed OCR when the same image is captured again.
            if item.kind == .image, item.text == nil {
                item.text = existing.text
                item.recognitionCompleted = existing.recognitionCompleted
            }
        }
        updated.append(item)
        items = updated
        prune()
        scheduleSave()
        return item.id
    }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var updated = items
        updated[index].isPinned.toggle()
        // Publish pin state and its final ordering together, without exposing an
        // intermediate unsorted snapshot to selection and lazy-list observers.
        items = HistoryPolicy.retained(
            updated, days: settings.retentionDays,
            maximum: settings.maximumItems, now: now())
        scheduleSave()
    }

    func rename(_ id: UUID, to name: String?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].customName = cleaned?.isEmpty == false ? cleaned : nil
        scheduleSave()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        scheduleSave()
    }

    func clearUnpinned() {
        items.removeAll { !$0.isPinned }
        scheduleSave()
    }

    func applyRetentionPolicy() {
        if prune() { scheduleSave() }
    }

    func markUsed(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].lastUsedAt = now()
        items[index].useCount += 1
        scheduleSave()
    }

    func updateRecognizedText(_ text: String?, id: UUID, contentHash: String) {
        guard let index = items.firstIndex(where: { $0.id == id && $0.contentHash == contentHash }) else { return }
        guard items[index].recognitionCompleted != true || items[index].text != text else { return }
        items[index].text = text
        items[index].recognitionCompleted = true
        scheduleSave()
    }

    func flush() throws {
        do { try repository.flush() } catch { report(error); throw error }
    }

    func stopMaintenance() { maintenanceTimer?.invalidate() }

    @discardableResult
    private func prune() -> Bool {
        let retained = HistoryPolicy.retained(
            items, days: settings.retentionDays,
            maximum: settings.maximumItems, now: now())
        guard retained != items else { return false }
        items = retained
        return true
    }

    private func scheduleSave() {
        revision += 1
        let revision = revision
        repository.save(items) { [weak self] result in
            Task { @MainActor in
                guard let self, self.revision == revision else { return }
                switch result {
                case .success(let persisted):
                    self.items = persisted
                    self.storageError = nil
                case .failure(let error): self.report(error)
                }
            }
        }
    }

    private func report(_ error: Error) {
        storageError = error.localizedDescription
        logger.error("History storage failed; details are available in the application.")
    }

    isolated deinit { maintenanceTimer?.invalidate() }
}
