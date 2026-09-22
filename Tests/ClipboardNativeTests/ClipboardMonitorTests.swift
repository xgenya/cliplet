import AppKit
import Combine
import XCTest
@testable import ClipboardNative

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
    func testExcludedPrivateAndPausedContentNeverEntersHistory() {
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
    func testOwnRichTextWritesAreIgnoredUsingFinalChangeCount() throws {
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
    }

    @MainActor
    func testMissingPayloadDoesNotClearClipboard() {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let pasteboard = MemoryClipboard()
        pasteboard.setString("keep this", forType: .string)
        var item = fixtureItem()
        item.payloadReferences = ["rtf": "invalid-reference"]
        XCTAssertFalse(PasteService(settings: settings, pasteboard: pasteboard).write(item))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep this")
    }
}
