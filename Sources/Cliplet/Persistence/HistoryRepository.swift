import Foundation

protocol HistoryPersistence: AnyObject {
    func load() throws -> [ClipboardItem]
    func save(_ items: [ClipboardItem], completion: @escaping @Sendable (Result<[ClipboardItem], Error>) -> Void)
    func flush() throws
}

enum HistoryStorageError: LocalizedError {
    case loadRequired, unsupportedVersion(Int), invalidPayload, missingPayload

    var errorDescription: String? {
        switch self {
        case .loadRequired: return "History could not be loaded. The original file has been preserved."
        case .unsupportedVersion: return "This history was created by a newer application version."
        case .invalidPayload: return "History contains an invalid payload reference."
        case .missingPayload: return "A history payload is missing or inaccessible."
        }
    }
}

/// All reads, commits, debounce state and cleanup run on one queue. Atomic replacement
/// protects a single commit; the queue also prevents older commits overtaking newer ones.
// Queue confinement is the synchronization contract for every mutable property.
// Public entry points either enqueue work or synchronously join that same queue.
final class HistoryRepository: HistoryPersistence, @unchecked Sendable {
    private struct Document: Codable {
        let version: Int
        let items: [ClipboardItem]
    }
    private struct Header: Decodable { let version: Int }
    private let directory: URL
    private var historyURL: URL { directory.appendingPathComponent("history.json") }
    private var payloadDirectory: URL { directory.appendingPathComponent("Payloads", isDirectory: true) }
    private let queue = DispatchQueue(label: "app.cliplet.history", qos: .utility)
    private let debounce: TimeInterval
    private let writeData: @Sendable (Data, URL) throws -> Void
    private var canWrite = false
    private var lastError: Error?
    private var pending: (items: [ClipboardItem], completion: @Sendable (Result<[ClipboardItem], Error>) -> Void)?
    private var generation = 0

    init(
        directory: URL, debounce: TimeInterval = 0.25,
        writeData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        self.directory = directory
        self.debounce = debounce
        self.writeData = writeData
    }

    static var defaultDirectory: URL {
        directory(
            in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            environment: .current)
    }

    static func directory(in support: URL, environment: AppEnvironment) -> URL {
        let destination = support.appendingPathComponent(environment.dataDirectoryName, isDirectory: true)
        let legacy = support.appendingPathComponent(environment.legacyDataDirectoryName, isDirectory: true)
        let files = FileManager.default
        guard files.fileExists(atPath: legacy.path) else { return destination }
        if files.fileExists(atPath: destination.path) {
            // Never overwrite either history when both locations already exist.
            return files.fileExists(atPath: destination.appendingPathComponent("history.json").path)
                ? destination : legacy
        }
        do {
            try files.moveItem(at: legacy, to: destination)
            return destination
        } catch {
            // Continue using the existing history if the move is unavailable.
            return legacy
        }
    }

    func load() throws -> [ClipboardItem] {
        try queue.sync {
            canWrite = false
            do {
                let data: Data
                do {
                    data = try Data(contentsOf: historyURL)
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                    canWrite = true
                    lastError = nil
                    return []
                }
                let decoder = JSONDecoder()
                let legacy = data.first(where: { ![9, 10, 13, 32].contains($0) }) == 91
                var items: [ClipboardItem]
                if legacy {
                    items = try decoder.decode([ClipboardItem].self, from: data)
                } else {
                    let header = try decoder.decode(Header.self, from: data)
                    guard header.version == 1 else { throw HistoryStorageError.unsupportedVersion(header.version) }
                    items = try decoder.decode(Document.self, from: data).items
                }
                for index in items.indices {
                    items[index].payloadDirectory = payloadDirectory
                    try validatePayloads(items[index])
                }
                canWrite = true
                // Migration commits payloads before replacing the legacy metadata file.
                if legacy { items = try commit(items) }
                lastError = nil
                return items
            } catch {
                canWrite = false
                lastError = error
                throw error
            }
        }
    }

    func save(_ items: [ClipboardItem], completion: @escaping @Sendable (Result<[ClipboardItem], Error>) -> Void) {
        queue.async {
            self.pending = (items, completion)
            self.generation += 1
            let generation = self.generation
            self.queue.asyncAfter(deadline: .now() + self.debounce) {
                guard generation == self.generation else { return }
                self.commitPending()
            }
        }
    }

    /// Drains previously enqueued work and commits the latest snapshot even inside
    /// the debounce interval. No callback needs the main queue for this to finish.
    func flush() throws {
        try queue.sync {
            generation += 1
            commitPending()
            if let lastError { throw lastError }
        }
    }

    private func commitPending() {
        guard let pending else { return }
        self.pending = nil
        let result = Result { () throws -> [ClipboardItem] in
            guard canWrite else { throw lastError ?? HistoryStorageError.loadRequired }
            return try commit(pending.items)
        }
        switch result {
        case .success: lastError = nil
        case .failure(let error):
            lastError = error
            // A later flush can retry a transient disk error without requiring an edit.
            self.pending = pending
        }
        pending.completion(result)
    }

    private func commit(_ items: [ClipboardItem]) throws -> [ClipboardItem] {
        let manager = FileManager.default
        try manager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try manager.createDirectory(
            at: payloadDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stored = try items.map { item -> ClipboardItem in
            var item = item
            var references = item.payloadReferences ?? [:]
            for (key, data) in [("image", item.imageData), ("rtf", item.rtfData), ("html", item.htmlData)] {
                if let data {
                    let name = ClipboardItem.hash(parts: [data]) + ".payload"
                    let url = payloadDirectory.appendingPathComponent(name)
                    if !manager.fileExists(atPath: url.path) {
                        try writeData(data, url)
                        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    }
                    references[key] = name
                }
            }
            item.imageData = nil
            item.rtfData = nil
            item.htmlData = nil
            item.payloadReferences = references.isEmpty ? nil : references
            item.payloadDirectory = payloadDirectory
            try validatePayloads(item)
            return item
        }
        let data = try JSONEncoder().encode(Document(version: 1, items: stored))
        try writeData(data, historyURL)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
        // Only collect after the metadata commit. A failed write must keep the old payloads.
        let live = Set(stored.flatMap { Array(($0.payloadReferences ?? [:]).values) })
        for url in try manager.contentsOfDirectory(at: payloadDirectory, includingPropertiesForKeys: nil) {
            if Self.isPayloadName(url.lastPathComponent), !live.contains(url.lastPathComponent) {
                try manager.removeItem(at: url)
            }
        }
        return stored
    }

    private func validatePayloads(_ item: ClipboardItem) throws {
        for (key, name) in item.payloadReferences ?? [:] {
            guard ["image", "rtf", "html"].contains(key), Self.isPayloadName(name) else {
                throw HistoryStorageError.invalidPayload
            }
            guard FileManager.default.isReadableFile(atPath: payloadDirectory.appendingPathComponent(name).path) else {
                throw HistoryStorageError.missingPayload
            }
        }
    }

    static func isPayloadName(_ name: String) -> Bool {
        name.range(of: "^[a-f0-9]{64}\\.payload$", options: .regularExpression) != nil
    }
}

final class MemoryHistoryRepository: HistoryPersistence {
    private var items: [ClipboardItem]
    init(items: [ClipboardItem] = []) { self.items = items }
    func load() throws -> [ClipboardItem] { items }
    func save(_ items: [ClipboardItem], completion: @escaping @Sendable (Result<[ClipboardItem], Error>) -> Void) {
        self.items = items
        completion(.success(items))
    }
    func flush() throws {}
}
