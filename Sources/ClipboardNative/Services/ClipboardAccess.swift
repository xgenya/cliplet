import AppKit

/// The system clipboard boundary. Unit tests use an in-memory implementation and
/// never connect to the user's pasteboard server.
protocol ClipboardAccess {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType]? { get }
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
    func fileURLs() -> [URL]
    func clear()
    func writeText(_ text: String, rtf: Data?, html: Data?) -> Bool
    func writeImage(_ image: NSImage) -> Bool
    func writeFiles(_ urls: [URL]) -> Bool
}

struct SystemClipboard: ClipboardAccess {
    let pasteboard: NSPasteboard
    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    var changeCount: Int { pasteboard.changeCount }
    var types: [NSPasteboard.PasteboardType]? { pasteboard.types }
    func string(forType type: NSPasteboard.PasteboardType) -> String? { pasteboard.string(forType: type) }
    func data(forType type: NSPasteboard.PasteboardType) -> Data? { pasteboard.data(forType: type) }
    func fileURLs() -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    func clear() { pasteboard.clearContents() }
    func writeText(_ text: String, rtf: Data?, html: Data?) -> Bool {
        var types: [NSPasteboard.PasteboardType] = [.string]
        if rtf != nil { types.append(.rtf) }
        if html != nil { types.append(.html) }
        pasteboard.declareTypes(types, owner: nil)
        let result = pasteboard.setString(text, forType: .string)
        if let rtf { pasteboard.setData(rtf, forType: .rtf) }
        if let html { pasteboard.setData(html, forType: .html) }
        return result
    }
    func writeImage(_ image: NSImage) -> Bool { pasteboard.writeObjects([image]) }
    func writeFiles(_ urls: [URL]) -> Bool { pasteboard.writeObjects(urls as [NSURL]) }
}
