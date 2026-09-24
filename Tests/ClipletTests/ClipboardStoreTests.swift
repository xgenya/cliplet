import Combine
import XCTest
@testable import ClipletKit

// Async entry points avoid the isolated-deinit runtime bug in synchronous XCTest.
// https://github.com/swiftlang/swift/issues/85663
final class ClipboardStoreTests: XCTestCase {
    @MainActor
    func testStartupAndPeriodicRetentionPersistWhileRecordingIsPaused() async throws {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        settings.retentionDays = 1
        settings.isPaused = true
        var now = Date()
        let pinned = fixtureItem("pinned", date: now.addingTimeInterval(-300_000), pinned: true)
        let old = fixtureItem("expired", date: now.addingTimeInterval(-300_000))
        let current = fixtureItem("current", date: now)
        let repository = MemoryHistoryRepository(items: [old, current, pinned])
        let store = ClipboardStore(settings: settings, repository: repository, now: { now }, maintenanceInterval: 0.01)
        defer { store.stopMaintenance() }
        try store.flush()
        XCTAssertEqual(try repository.load().map(\.id), [pinned.id, current.id])
        now = now.addingTimeInterval(200_000)
        try await waitUntil { store.items.map(\.id) == [pinned.id] }
        try store.flush()
        XCTAssertEqual(try repository.load().map(\.id), [pinned.id])
    }

    @MainActor
    func testEqualHashesOfDifferentKindsAreNotMerged() async throws {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let store = ClipboardStore(settings: settings, repository: MemoryHistoryRepository(), maintenanceInterval: nil)
        let text = fixtureItem("file:///tmp/example")
        var file = fixtureItem("file:///tmp/example")
        file.kind = .file
        file.text = nil
        file.fileURLs = [URL(fileURLWithPath: "/tmp/example")]
        store.add(text)
        store.add(file)
        XCTAssertEqual(Set(store.items.map(\.kind)), [.text, .file])
    }

    @MainActor
    func testSettingsApplyWithoutSettingsWindow() async throws {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let date = Date()
        let repository = MemoryHistoryRepository(items: [
            fixtureItem("new", date: date), fixtureItem("old", date: date.addingTimeInterval(-10)),
        ])
        let store = ClipboardStore(settings: settings, repository: repository, maintenanceInterval: nil)
        settings.maximumItems = 1
        try await waitUntil { store.items.count == 1 }
        XCTAssertEqual(store.items.first?.text, "new")
        try store.flush()
        XCTAssertEqual(try repository.load().count, 1)
    }

    @MainActor
    func testDuplicateKeepsIdentityAndUserMetadataButUpdatesContent() async throws {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let store = ClipboardStore(settings: settings, repository: MemoryHistoryRepository(), maintenanceInterval: nil)
        let first = fixtureItem("same")
        let id = store.add(first)
        store.togglePin(id)
        store.rename(id, to: "saved name")
        store.markUsed(id)
        var duplicate = fixtureItem("same", date: Date().addingTimeInterval(10))
        duplicate.htmlData = Data("<b>same</b>".utf8)
        XCTAssertEqual(store.add(duplicate), id)
        XCTAssertEqual(store.items.count, 1)
        let result = try XCTUnwrap(store.items.first)
        XCTAssertTrue(result.isPinned)
        XCTAssertEqual(result.customName, "saved name")
        XCTAssertEqual(result.useCount, 1)
        XCTAssertEqual(result.htmlData, duplicate.htmlData)
    }

    @MainActor
    func testSelectionAndSearchAreIndependentOfPersistence() async {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let store = ClipboardStore(settings: settings, repository: MemoryHistoryRepository(), maintenanceInterval: nil)
        let state = ClipboardViewState(store: store)
        let id = store.add(fixtureItem("search me"))
        _ = store.add(fixtureItem("other"))
        state.query = "SEARCH"
        XCTAssertEqual(state.visibleItems.map(\.id), [id])
        XCTAssertEqual(state.selectedItem?.id, id)
        store.add(fixtureItem("search me"))
        XCTAssertEqual(state.selectedItem?.id, id)
        store.delete(id)
        XCTAssertNil(state.selectedItem)
        state.query = ""
        XCTAssertEqual(state.selectedItem?.text, "other")
    }

    @MainActor
    func testActionMenuCannotRemainOpenWithoutAVisibleEntry() async {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let store = ClipboardStore(settings: settings, repository: MemoryHistoryRepository(), maintenanceInterval: nil)
        let state = ClipboardViewState(store: store)
        state.toggleActions()
        XCTAssertFalse(state.showActions)

        let id = store.add(fixtureItem("menu target"))
        state.toggleActions()
        XCTAssertTrue(state.showActions)
        store.delete(id)
        XCTAssertFalse(state.showActions)

        store.add(fixtureItem("another target"))
        state.toggleActions()
        state.query = "no matching entry"
        XCTAssertFalse(state.showActions)
        state.toggleActions()
        XCTAssertFalse(state.showActions)
    }

    @MainActor
    func testPinAndUnpinPublishConsistentSelectionAndPersistLatestState() async throws {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let repository = MemoryHistoryRepository()
        let store = ClipboardStore(settings: settings, repository: repository, maintenanceInterval: nil)
        let state = ClipboardViewState(store: store)
        let older = store.add(fixtureItem("older", date: Date().addingTimeInterval(-60)))
        let newer = store.add(fixtureItem("newer"))
        state.selectedID = older
        var snapshots: [[ClipboardItem]] = []
        let subscription = store.$items.dropFirst().sink { snapshots.append($0) }
        defer { subscription.cancel() }

        for _ in 0..<3 {
            store.togglePin(older)
            XCTAssertEqual(state.selectedID, older)
            XCTAssertTrue(try XCTUnwrap(state.selectedItem).isPinned)
            XCTAssertEqual(state.visibleItems.map(\.id), [older, newer])
            XCTAssertEqual(snapshots.last?.first?.id, older)
            store.togglePin(older)
            XCTAssertEqual(state.selectedID, older)
            XCTAssertFalse(try XCTUnwrap(state.selectedItem).isPinned)
            XCTAssertEqual(state.visibleItems.map(\.id), [newer, older])
        }
        // Old asynchronous save completions must not revert the latest toggle.
        for _ in 0..<4 { await Task.yield() }
        try store.flush()
        XCTAssertFalse(try XCTUnwrap(state.selectedItem).isPinned)
        XCTAssertFalse(try XCTUnwrap(repository.load().first { $0.id == older }).isPinned)
    }

    @MainActor
    func testLateRecognitionCannotResurrectDeletedHistory() async {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let store = ClipboardStore(settings: settings, repository: MemoryHistoryRepository(), maintenanceInterval: nil)
        let item = fixtureItem(image: Data([1, 2]))
        store.add(item)
        store.delete(item.id)
        store.updateRecognizedText("late text", id: item.id, contentHash: item.contentHash)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testRetentionKeepsPinsAndChoosesNewestEvenForUnsortedInput() {
        let now = Date()
        let pinned = fixtureItem("pinned", date: now.addingTimeInterval(-1_000_000), pinned: true)
        let older = fixtureItem("older", date: now.addingTimeInterval(-10))
        let newer = fixtureItem("newer", date: now)
        XCTAssertEqual(
            HistoryPolicy.retained([older, newer, pinned], days: 1, maximum: 2, now: now).map(\.id),
            [pinned.id, newer.id])
        XCTAssertEqual(HistoryPolicy.retained([older, newer, pinned], days: 1, maximum: 0, now: now).count, 3)
    }
}
