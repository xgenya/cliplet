import XCTest
@testable import ClipletKit

final class HistoryRepositoryTests: XCTestCase {
    private var directory: URL!
    private var historyURL: URL { directory.appendingPathComponent("history.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cliplet-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testLegacyHistoryDirectoryMovesToClipletWithoutLosingPayloads() throws {
        let legacy = directory.appendingPathComponent(AppEnvironment.production.legacyDataDirectoryName)
        let payloads = legacy.appendingPathComponent("Payloads")
        try FileManager.default.createDirectory(at: payloads, withIntermediateDirectories: true)
        let metadata = Data("existing history".utf8)
        let attachment = Data([1, 2, 3])
        try metadata.write(to: legacy.appendingPathComponent("history.json"))
        try attachment.write(to: payloads.appendingPathComponent("image.payload"))

        let migrated = HistoryRepository.directory(in: directory, environment: .production)
        XCTAssertEqual(migrated.lastPathComponent, "Cliplet")
        XCTAssertEqual(try Data(contentsOf: migrated.appendingPathComponent("history.json")), metadata)
        XCTAssertEqual(try Data(contentsOf: migrated.appendingPathComponent("Payloads/image.payload")), attachment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testExistingDestinationDoesNotOverwriteLegacyHistory() throws {
        let legacy = directory.appendingPathComponent(
            AppEnvironment.production.legacyDataDirectoryName, isDirectory: true)
        let destination = directory.appendingPathComponent(
            AppEnvironment.production.dataDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: legacy.appendingPathComponent("history.json"))

        XCTAssertEqual(HistoryRepository.directory(in: directory, environment: .production), legacy)
        try Data("new".utf8).write(to: destination.appendingPathComponent("history.json"))
        XCTAssertEqual(HistoryRepository.directory(in: directory, environment: .production), destination)
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("history.json")), Data("legacy".utf8))
    }

    func testFlushCommitsLatestSnapshotWithoutWaitingForDebounce() throws {
        let repository = HistoryRepository(directory: directory, debounce: 60)
        XCTAssertTrue(try repository.load().isEmpty)
        repository.save([fixtureItem("old")]) { _ in }
        let latest = fixtureItem("latest")
        repository.save([latest]) { _ in }
        try repository.flush()
        XCTAssertEqual(try HistoryRepository(directory: directory).load().map(\.id), [latest.id])
    }

    func testRunningWriteCannotOverwriteNewerSnapshot() throws {
        let started = expectation(description: "old commit started")
        let release = DispatchSemaphore(value: 0)
        let writes = Locked(0)
        let repository = HistoryRepository(directory: directory, debounce: 0) { data, url in
            if url.lastPathComponent == "history.json" {
                let count = writes.withValue {
                    $0 += 1; return $0
                }
                if count == 1 {
                    started.fulfill()
                    guard release.wait(timeout: .now() + 5) == .success else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
            }
            try data.write(to: url, options: .atomic)
        }
        _ = try repository.load()
        repository.save([fixtureItem("old")]) { _ in }
        wait(for: [started], timeout: 3)
        let newest = fixtureItem("newest")
        repository.save([newest]) { _ in }
        release.signal()
        try repository.flush()
        XCTAssertEqual(try HistoryRepository(directory: directory).load().map(\.id), [newest.id])
    }

    func testCorruptAndFutureFilesAreNeverOverwritten() throws {
        for contents in ["broken JSON", "{\"version\":99,\"items\":[]}"] {
            let original = Data(contents.utf8)
            try original.write(to: historyURL)
            let repository = HistoryRepository(directory: directory)
            XCTAssertThrowsError(try repository.load())
            repository.save([fixtureItem()]) { _ in }
            XCTAssertThrowsError(try repository.flush())
            XCTAssertEqual(try Data(contentsOf: historyURL), original)
        }
    }

    func testReadErrorIsNotTreatedAsFirstLaunch() throws {
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
        let repository = HistoryRepository(directory: directory)
        XCTAssertThrowsError(try repository.load())
        repository.save([fixtureItem()]) { _ in }
        XCTAssertThrowsError(try repository.flush())
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testLegacyMigrationExternalizesAndLazilyLoadsAllPayloadKinds() throws {
        var item = fixtureItem(image: Data(repeating: 42, count: 100_000))
        item.rtfData = Data("synthetic rtf".utf8)
        item.htmlData = Data("<b>synthetic html</b>".utf8)
        try JSONEncoder().encode([item]).write(to: historyURL)
        let migrated = try XCTUnwrap(HistoryRepository(directory: directory).load().first)
        XCTAssertNil(migrated.imageData)
        XCTAssertNil(migrated.rtfData)
        XCTAssertNil(migrated.htmlData)
        XCTAssertEqual(try migrated.payloadData(for: "image"), item.imageData)
        XCTAssertEqual(try migrated.payloadData(for: "rtf"), item.rtfData)
        XCTAssertEqual(try migrated.payloadData(for: "html"), item.htmlData)
        XCTAssertLessThan(try Data(contentsOf: historyURL).count, 3_000)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: historyURL)) as? [String: Any])
        XCTAssertEqual(document["version"] as? Int, 1)
        XCTAssertFalse(String(decoding: try Data(contentsOf: historyURL), as: UTF8.self).contains(directory.path))
        let permissions = try FileManager.default.attributesOfItem(atPath: historyURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testFailedMigrationPreservesLegacyFile() throws {
        let original = try JSONEncoder().encode([fixtureItem(image: Data([1, 2, 3]))])
        try original.write(to: historyURL)
        let repository = HistoryRepository(directory: directory) { data, url in
            if url.lastPathComponent == "history.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        XCTAssertThrowsError(try repository.load())
        repository.save([]) { _ in }
        XCTAssertThrowsError(try repository.flush())
        XCTAssertEqual(try Data(contentsOf: historyURL), original)
    }

    func testMetadataEditsReusePayloadAndCleanupRespectsSharedReferences() throws {
        let repository = HistoryRepository(directory: directory)
        _ = try repository.load()
        let first = fixtureItem(image: Data([10, 20, 30]))
        let second = fixtureItem(image: Data([10, 20, 30]))
        repository.save([first, second]) { _ in }
        try repository.flush()
        var stored = try repository.load()
        let name = try XCTUnwrap(stored.first?.payloadReferences?["image"])
        let payloadURL = directory.appendingPathComponent("Payloads").appendingPathComponent(name)
        let sentinel = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: sentinel], ofItemAtPath: payloadURL.path)
        stored[0].customName = "renamed"
        repository.save([stored[0]]) { _ in }
        try repository.flush()
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: payloadURL.path)[.modificationDate] as? Date, sentinel)
        XCTAssertEqual(try repository.load().first?.customName, "renamed")
        repository.save([]) { _ in }
        try repository.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
    }

    func testFailedCommitKeepsPreviousMetadataAndPayloadThenCanRetry() throws {
        let fail = Locked(false)
        let repository = HistoryRepository(directory: directory) { data, url in
            if fail.withValue({ $0 }) && url.lastPathComponent == "history.json" {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try data.write(to: url, options: .atomic)
        }
        _ = try repository.load()
        repository.save([fixtureItem(image: Data([1, 9]))]) { _ in }
        try repository.flush()
        let original = try Data(contentsOf: historyURL)
        fail.withValue { $0 = true }
        repository.save([]) { _ in }
        XCTAssertThrowsError(try repository.flush())
        XCTAssertEqual(try Data(contentsOf: historyURL), original)
        XCTAssertEqual(
            try HistoryRepository(directory: directory).load().first?.payloadData(for: "image"), Data([1, 9]))
        fail.withValue { $0 = false }
        // Retry the pending snapshot without another user edit.
        try repository.flush()
        XCTAssertTrue(try repository.load().isEmpty)
    }

    func testInvalidOrUnreadablePayloadBlocksWrites() throws {
        let unreadable = String(repeating: "a", count: 64) + ".payload"
        let payloads = directory.appendingPathComponent("Payloads", isDirectory: true)
        try FileManager.default.createDirectory(at: payloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: payloads.appendingPathComponent(unreadable), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o000])
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: payloads.appendingPathComponent(unreadable).path)
        }
        for reference in ["../outside", unreadable] {
            var item = fixtureItem()
            item.payloadReferences = ["image": reference]
            let original = try JSONEncoder().encode([item])
            try original.write(to: historyURL)
            let repository = HistoryRepository(directory: directory)
            XCTAssertThrowsError(try repository.load())
            repository.save([]) { _ in }
            XCTAssertThrowsError(try repository.flush())
            XCTAssertEqual(try Data(contentsOf: historyURL), original)
        }
    }

    func testMissingPayloadFileOnlyDropsAffectedContent() throws {
        let missing = String(repeating: "b", count: 64) + ".payload"
        var text = fixtureItem("keeps text")
        text.payloadReferences = ["rtf": missing]
        var image = fixtureItem("image", image: nil)
        image.kind = .image
        image.text = nil
        image.payloadReferences = ["image": missing]
        try JSONEncoder().encode([text, image]).write(to: historyURL)
        let repository = HistoryRepository(directory: directory)
        let loaded = try repository.load()
        XCTAssertEqual(loaded.map(\.id), [text.id])
        XCTAssertNil(loaded.first?.payloadReferences)
        repository.save(loaded) { _ in }
        XCTAssertNoThrow(try repository.flush())
    }
}
