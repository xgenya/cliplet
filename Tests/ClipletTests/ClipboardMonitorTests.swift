import AppKit
import Combine
import XCTest
@testable import ClipletKit

private actor SuspendedRecognizer: ImageRecognizing {
    private(set) var started = false
    var continuation: CheckedContinuation<String?, Never>?
    func recognize(_ data: Data) async throws -> String? {
        await withCheckedContinuation {
            continuation = $0
            started = true
        }
    }
    func finish() {
        continuation?.resume(returning: "recognized test text")
        continuation = nil
    }
}

private actor RestartableRecognizer: ImageRecognizing {
    private var continuations: [CheckedContinuation<String?, Never>] = []
    var startedCount: Int { continuations.count }

    func recognize(_ data: Data) async throws -> String? {
        await withCheckedContinuation { continuations.append($0) }
    }

    func finish(_ index: Int, with text: String?) {
        continuations[index].resume(returning: text)
    }
}

// Use async entry points for services with isolated deinit on the CI runtime.
// https://github.com/swiftlang/swift/issues/85663
final class ClipboardMonitorTests: XCTestCase {
    @MainActor
    func testImageCaptureDoesNotWaitForRecognitionAndTextCaptureContinues() async throws {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let store = ClipboardStore(settings: settings, repository: MemoryHistoryRepository(), maintenanceInterval: nil)
        let pasteboard = MemoryClipboard()
        let recognizer = SuspendedRecognizer()
        let monitor = ClipboardMonitor(
            store: store, settings: settings, pasteboard: pasteboard,
            source: { ClipboardSource(bundleIdentifier: "test.source", name: "Test") }, recognizer: recognizer)
        defer { monitor.stop() }
        pasteboard.setData(fixtureImage(), forType: .png)
        monitor.poll()
        let imageID = try XCTUnwrap(store.items.first?.id)
        XCTAssertEqual(store.items.first?.kind, .image)
        XCTAssertNil(store.items.first?.text)
        for _ in 0..<200 {
            if await recognizer.started { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let didStart = await recognizer.started
        XCTAssertTrue(didStart)
        pasteboard.clearContents()
        pasteboard.setString("next clipboard entry", forType: .string)
        monitor.poll()
        XCTAssertEqual(store.items.count, 2)
        await recognizer.finish()
        try await waitUntil { store.items.contains { $0.id == imageID && $0.text == "recognized test text" } }
        XCTAssertEqual(store.items.count, 2)
    }

    @MainActor
    func testExcludedPrivateAndPausedContentNeverEntersHistory() async {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let store = ClipboardStore(settings: settings, repository: MemoryHistoryRepository(), maintenanceInterval: nil)
        let pasteboard = MemoryClipboard()
        var source = "test.excluded"
        settings.excludedBundleIDsText = source
        let monitor = ClipboardMonitor(
            store: store, settings: settings, pasteboard: pasteboard,
            source: { ClipboardSource(bundleIdentifier: source, name: "Test") })
        pasteboard.setString("excluded", forType: .string)
        monitor.poll()
        XCTAssertTrue(store.items.isEmpty)
        source = "test.allowed"
        pasteboard.clearContents()
        pasteboard.setString("concealed", forType: .string)
        pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        monitor.poll()
        XCTAssertTrue(store.items.isEmpty)
        settings.isPaused = true
        pasteboard.clearContents()
        pasteboard.setString("paused", forType: .string)
        monitor.poll()
        settings.isPaused = false
        monitor.poll()
        XCTAssertTrue(store.items.isEmpty)
    }

    @MainActor
    func testOwnRichTextWritesAreIgnoredUsingFinalChangeCount() async throws {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let store = ClipboardStore(settings: settings, repository: MemoryHistoryRepository(), maintenanceInterval: nil)
        let pasteboard = MemoryClipboard()
        let monitor = ClipboardMonitor(
            store: store, settings: settings, pasteboard: pasteboard,
            source: { ClipboardSource(bundleIdentifier: "test.external", name: "Test") })
        let paste = PasteService(settings: settings, pasteboard: pasteboard)
        paste.monitor = monitor
        var item = fixtureItem()
        item.htmlData = Data("<b>synthetic</b>".utf8)
        XCTAssertTrue(paste.write(item))
        monitor.poll()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(pasteboard.data(forType: .html), item.htmlData)
        // Plain-text preference must still paste an image when it has no recognized text.
        XCTAssertTrue(paste.write(fixtureItem(image: fixtureImage()), plainText: true))
        // Recognized text is for search; plain-text preference must not replace the image.
        var recognized = fixtureItem(image: fixtureImage())
        recognized.text = "ocr text"
        recognized.recognitionCompleted = true
        XCTAssertTrue(paste.write(recognized, plainText: true))
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    @MainActor
    func testPasteWithoutAccessibilityCopiesImmediately() async {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let pasteboard = MemoryClipboard()
        let paste = PasteService(settings: settings, pasteboard: pasteboard, isTrusted: { false })
        var outcomes: [PasteOutcome] = []
        paste.paste(fixtureItem("needs permission"), into: .current) { outcomes.append($0) }
        XCTAssertEqual(outcomes, [.needsAccessibility])
        XCTAssertEqual(pasteboard.string(forType: .string), "needs permission")

        settings.pasteAutomatically = false
        paste.paste(fixtureItem("copy only"), into: .current) { outcomes.append($0) }
        var broken = fixtureItem()
        broken.payloadReferences = ["rtf": "invalid-reference"]
        paste.paste(broken, into: .current) { outcomes.append($0) }
        XCTAssertEqual(outcomes, [.needsAccessibility, .copied, .failed])
        XCTAssertEqual(pasteboard.string(forType: .string), "copy only")
    }

    @MainActor
    func testMissingPayloadDoesNotClearClipboard() async {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let pasteboard = MemoryClipboard()
        pasteboard.setString("keep this", forType: .string)
        var item = fixtureItem()
        item.payloadReferences = ["rtf": "invalid-reference"]
        XCTAssertFalse(PasteService(settings: settings, pasteboard: pasteboard).write(item))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep this")
    }

    @MainActor
    func testStoppedRecognitionRestartsAndCancelledResultCannotOverwriteIt() async throws {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let store = ClipboardStore(settings: settings, repository: MemoryHistoryRepository(), maintenanceInterval: nil)
        let pasteboard = MemoryClipboard()
        let recognizer = RestartableRecognizer()
        let monitor = ClipboardMonitor(
            store: store, settings: settings, pasteboard: pasteboard,
            source: { ClipboardSource(bundleIdentifier: "test.source", name: "Test") }, recognizer: recognizer)
        defer { monitor.stop() }
        pasteboard.setData(fixtureImage(), forType: .png)
        monitor.poll()
        let id = try XCTUnwrap(store.items.first?.id)
        for _ in 0..<200 where await recognizer.startedCount < 1 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let firstCount = await recognizer.startedCount
        XCTAssertEqual(firstCount, 1)

        monitor.stop()
        monitor.start()
        for _ in 0..<200 where await recognizer.startedCount < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let restartedCount = await recognizer.startedCount
        XCTAssertEqual(restartedCount, 2)
        await recognizer.finish(0, with: "stale result")
        XCTAssertNil(store.items.first?.text)
        await recognizer.finish(1, with: "resumed result")
        try await waitUntil { store.items.first?.text == "resumed result" }
        XCTAssertEqual(store.items.first?.id, id)
        XCTAssertEqual(store.items.first?.recognitionCompleted, true)
    }

    @MainActor
    func testStartupResumesOnlyIncompleteImageRecognition() async throws {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let pending = fixtureItem(image: fixtureImage())
        var completed = fixtureItem(image: Data([1, 2, 3]))
        completed.recognitionCompleted = true
        let restored = try JSONDecoder().decode(
            [ClipboardItem].self, from: JSONEncoder().encode([pending, completed]))
        let repository = MemoryHistoryRepository(items: restored)
        let store = ClipboardStore(settings: settings, repository: repository, maintenanceInterval: nil)
        let recognizer = RestartableRecognizer()
        let monitor = ClipboardMonitor(
            store: store, settings: settings, pasteboard: MemoryClipboard(), recognizer: recognizer)
        defer { monitor.stop() }
        monitor.start()
        for _ in 0..<200 where await recognizer.startedCount < 1 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let initialCount = await recognizer.startedCount
        XCTAssertEqual(initialCount, 1)
        await recognizer.finish(0, with: nil)
        try await waitUntil { store.items.first(where: { $0.id == pending.id })?.recognitionCompleted == true }
        XCTAssertNil(store.items.first(where: { $0.id == pending.id })?.text)
        monitor.stop()
        monitor.start()
        let finalCount = await recognizer.startedCount
        XCTAssertEqual(finalCount, 1)
    }
}
