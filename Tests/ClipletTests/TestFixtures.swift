import AppKit
import Foundation
import XCTest
@testable import Cliplet

func fixtureItem(
    _ text: String = "synthetic test", date: Date = Date(), pinned: Bool = false,
    image: Data? = nil
) -> ClipboardItem {
    ClipboardItem(
        id: UUID(), createdAt: date, lastUsedAt: date, kind: image == nil ? .text : .image,
        text: image == nil ? text : nil, rtfData: nil, htmlData: nil, imageData: image,
        fileURLs: [], sourceBundleIdentifier: "test.source", sourceApplicationName: "Test",
        isPinned: pinned, useCount: 0,
        contentHash: ClipboardItem.hash(parts: [image ?? Data(text.normalizedForClipboard.utf8)]), customName: nil)
}

func fixtureImage() -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 8, bitsPerPixel: 32)!
    for x in 0..<2 {
        for y in 0..<2 { bitmap.setColor(NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) }
    }
    return bitmap.representation(using: .png, properties: [:])!
}

@MainActor
func isolatedSettings() -> (AppSettings, () -> Void) {
    let name = "Cliplet.Tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    let settings = AppSettings(defaults: defaults)
    return (settings, { defaults.removePersistentDomain(forName: name) })
}

final class MemoryClipboard: ClipboardAccess {
    private var values: [NSPasteboard.PasteboardType: Data] = [:]
    private(set) var changeCount = 0
    var types: [NSPasteboard.PasteboardType]? { Array(values.keys) }
    func data(forType type: NSPasteboard.PasteboardType) -> Data? { values[type] }
    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        values[type].flatMap { String(data: $0, encoding: .utf8) }
    }
    func fileURLs() -> [URL] { [] }
    func clear() { values.removeAll(); changeCount += 1 }
    func clearContents() { clear() }
    func setData(_ data: Data, forType type: NSPasteboard.PasteboardType) {
        values[type] = data
        changeCount += 1
    }
    func setString(_ text: String, forType type: NSPasteboard.PasteboardType) {
        setData(Data(text.utf8), forType: type)
    }
    func writeText(_ text: String, rtf: Data?, html: Data?) -> Bool {
        clear()
        setString(text, forType: .string)
        if let rtf { setData(rtf, forType: .rtf) }
        if let html { setData(html, forType: .html) }
        return true
    }
    func writeImage(_ image: NSImage) -> Bool {
        guard let data = image.tiffRepresentation else { return false }
        setData(data, forType: .tiff)
        return true
    }
    func writeFiles(_ urls: [URL]) -> Bool { !urls.isEmpty }
}

@MainActor
func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
    let deadline = Date().addingTimeInterval(2)
    while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
    XCTAssertTrue(condition(), "Timed out waiting for state change", file: file, line: line)
}

/// Test coordination across the repository queue and the test thread.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
