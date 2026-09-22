import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ClipboardNative

final class HistoryRenderingTests: XCTestCase {
    func testImageThumbnailIsDownsampledAndReusedAfterPayloadLeavesDisk() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cliplet-thumbnail-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try largeImage()
        let name = ClipboardItem.hash(parts: [data]) + ".payload"
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        var item = fixtureItem(image: data)
        item.imageData = nil
        item.payloadReferences = ["image": name]
        item.payloadDirectory = directory
        let cache = ClipboardImageCache()
        let result = await cache.image(for: item, pixels: 44)
        let thumbnail = try XCTUnwrap(result)
        XCTAssertEqual(thumbnail.width, 44)
        XCTAssertEqual(thumbnail.height, 33)
        XCTAssertLessThan(thumbnail.bytesPerRow * thumbnail.height, 16_384)
        let previewResult = await cache.image(for: item, pixels: 1_200)
        let preview = try XCTUnwrap(previewResult)
        XCTAssertEqual(preview.width, 1_200)
        XCTAssertEqual(preview.height, 900)
        try FileManager.default.removeItem(at: url)
        let cached = await cache.image(for: item, pixels: 44)
        XCTAssertTrue(cached === thumbnail, "A second row must reuse the decoded thumbnail without reading the file")
        let cachedPreview = await cache.image(for: item, pixels: 1_200)
        XCTAssertTrue(cachedPreview === preview, "A preview and a list thumbnail must not replace one another")
    }

    func testMissingAndInvalidImagePayloadsAreSafe() async {
        let cache = ClipboardImageCache()
        var item = fixtureItem(image: Data([0, 1, 2]))
        let invalid = await cache.image(for: item, pixels: 44)
        XCTAssertNil(invalid)
        item.imageData = nil
        item.payloadReferences = ["image": "../outside.png"]
        item.payloadDirectory = FileManager.default.temporaryDirectory
        let traversal = await cache.image(for: item, pixels: 44)
        XCTAssertNil(traversal)
    }

    func testGroupingPreservesPinsOrderAndCalendarBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        // The day after a daylight saving transition, so yesterday is not a fixed 24-hour window.
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12)))
        let today = calendar.startOfDay(for: now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let pinned = fixtureItem("pin", date: yesterday.addingTimeInterval(-100), pinned: true)
        let recent = fixtureItem("today", date: today)
        let previous = fixtureItem("yesterday", date: yesterday)
        let old = fixtureItem("old", date: yesterday.addingTimeInterval(-1))
        let rows = HistoryListRow.make([recent, previous, old, pinned], now: now, calendar: calendar)
        XCTAssertEqual(
            rows.map(\.id),
            [
                .header(.pinned), .item(pinned.id), .header(.today), .item(recent.id),
                .header(.yesterday), .item(previous.id), .header(.earlier), .item(old.id),
            ])
        XCTAssertTrue(HistoryListRow.make([], now: now, calendar: calendar).isEmpty)
    }

    @MainActor
    func testSelectionDoesNotRebuildRowsAndPinMovesKeepIdentity() {
        let (settings, cleanup) = isolatedSettings()
        defer { cleanup() }
        let items = (0..<1_000).map { fixtureItem("Entry \($0)") }
        let store = ClipboardStore(
            settings: settings, repository: MemoryHistoryRepository(items: items), maintenanceInterval: nil)
        let state = ClipboardViewState(store: store)
        var changes = 0
        let subscription = state.$listRows.dropFirst().sink { _ in changes += 1 }
        defer { subscription.cancel() }
        for _ in 0..<100 { state.select(offset: 1) }
        XCTAssertEqual(changes, 0)
        let id = state.selectedID!
        store.togglePin(id)
        XCTAssertEqual(state.selectedID, id)
        XCTAssertTrue(state.selectedItem?.isPinned == true)
        XCTAssertEqual(state.listRows.prefix(2).map(\.id), [.header(.pinned), .item(id)])
        state.query = "no matching entry"
        XCTAssertTrue(state.listRows.isEmpty)
        XCTAssertNil(state.selectedItem)
    }

    @MainActor
    func testRowTitleBoundsLongTextWithoutChangingClipboardContent() {
        let text = String(repeating: "a", count: 1_000_000)
        let item = fixtureItem(text)
        XCTAssertEqual(item.displayTitle.count, 200)
        XCTAssertEqual(item.text, text)
        XCTAssertEqual(fixtureItem("first\nsecond").displayTitle, "first")
    }

    private func largeImage() throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 4_000, height: 3_000, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4_000, height: 3_000))
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
