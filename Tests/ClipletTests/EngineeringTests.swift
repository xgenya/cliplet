import Darwin
import AppKit
import Foundation
import XCTest
@testable import ClipletKit

final class EngineeringTests: XCTestCase {
    func testInstanceLockPreventsDuplicatesAndReleasesOnExit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Cliplet-lock-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let first = try XCTUnwrap(AppInstanceLock.acquire(at: url))
            try withExtendedLifetime(first) {
                XCTAssertNil(try AppInstanceLock.acquire(at: url))
            }
        }
        let next = try XCTUnwrap(AppInstanceLock.acquire(at: url))
        withExtendedLifetime(next) {}
    }

    @MainActor
    func testMenuBarIconIsAnAlwaysAvailableTemplateImage() {
        XCTAssertEqual(AppBrand.menuBarIcon.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(AppBrand.menuBarIcon.isTemplate)
        XCTAssertNotNil(AppBrand.menuBarIcon.tiffRepresentation)
    }

    @MainActor
    func testReopenRequestArrivingDuringLaunchIsDeliveredWhenReady() async {
        let requests = AppReopenRequests()
        var delivered = 0
        requests.receive()
        requests.onRequest = { delivered += 1 }
        XCTAssertEqual(delivered, 1)
        requests.receive()
        XCTAssertEqual(delivered, 2)
    }

    func testInstanceOwnerCannotBeOverwrittenByCompetingLaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Cliplet-owner-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let lock = try XCTUnwrap(AppInstanceLock.acquire(at: url, build: "first"))
            try withExtendedLifetime(lock) {
                XCTAssertEqual(AppInstanceLock.owner(at: url)?.build, "first")
                XCTAssertNil(try AppInstanceLock.acquire(at: url, build: "second"))
                XCTAssertEqual(AppInstanceLock.owner(at: url)?.build, "first")
            }
        }
        let replacement = try XCTUnwrap(AppInstanceLock.acquire(at: url, build: "second"))
        withExtendedLifetime(replacement) {
            XCTAssertEqual(AppInstanceLock.owner(at: url)?.build, "second")
        }
    }

    @MainActor
    func testReplacementDuringLaunchWaitsForQuitHandler() async {
        let requests = AppReopenRequests()
        var quits = 0
        requests.receiveReplacement()
        XCTAssertEqual(quits, 0)
        requests.onReplacement = { quits += 1 }
        XCTAssertEqual(quits, 1)
    }

    func testDevelopmentAndProductionIdentitiesAreDistinct() {
        XCTAssertNotEqual(AppEnvironment.development.bundleIdentifier, AppEnvironment.production.bundleIdentifier)
        XCTAssertNotEqual(AppEnvironment.development.dataDirectoryName, AppEnvironment.production.dataDirectoryName)
        XCTAssertEqual(AppEnvironment.production.bundleIdentifier, "com.clipboardnative.macos")
        XCTAssertEqual(AppEnvironment.production.dataDirectoryName, "Cliplet")
        XCTAssertEqual(AppEnvironment.production.legacyDataDirectoryName, "ClipboardNative")
        #if DEBUG
            XCTAssertEqual(AppEnvironment.current, .development)
        #else
            XCTAssertEqual(AppEnvironment.current, .production)
        #endif
    }

    func testFrozenHistoricalDocumentsRemainReadable() throws {
        for version in ["v0", "v1"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cliplet-fixture-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let fixture = try XCTUnwrap(
                Bundle.module.url(forResource: "history-\(version)", withExtension: "json", subdirectory: "Fixtures"))
            try FileManager.default.copyItem(at: fixture, to: directory.appendingPathComponent("history.json"))
            if version == "v1" {
                let payloads = directory.appendingPathComponent("Payloads")
                try FileManager.default.createDirectory(at: payloads, withIntermediateDirectories: true)
                try Data().write(to: payloads.appendingPathComponent(ClipboardItem.hash(parts: [Data()]) + ".payload"))
            }
            let item = try XCTUnwrap(HistoryRepository(directory: directory).load().first)
            XCTAssertTrue(item.isPinned)
            if version == "v0" {
                XCTAssertEqual(item.id.uuidString, "11111111-1111-4111-8111-111111111111")
                XCTAssertEqual(item.text, "Synthetic historical fixture")
                XCTAssertNil(item.customName)
                XCTAssertEqual(try item.payloadData(for: "rtf"), Data("{\\rtf1 test}".utf8))
                XCTAssertEqual(try item.payloadData(for: "html"), Data("<b>test</b>".utf8))
            } else {
                XCTAssertEqual(item.customName, "Historical image")
                XCTAssertEqual(try item.payloadData(for: "image"), Data())
                XCTAssertNil(item.sourceBundleIdentifier)
            }
        }
    }

    func testProcessInterruptionBeforeAndAfterMetadataCommit() throws {
        for phase in ["before", "after"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "Cliplet-crash-test-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            let repository = HistoryRepository(directory: directory)
            _ = try repository.load()
            repository.save([fixtureItem("previous", image: Data([1]))]) { _ in }
            try repository.flush()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "xctest", "-XCTest", "ClipletTests.EngineeringTests/testCrashWriterChild",
                Bundle(for: Self.self).bundlePath,
            ]
            var environment = ProcessInfo.processInfo.environment
            environment["CLIPLET_CRASH_TEST_DIRECTORY"] = directory.path
            environment["CLIPLET_CRASH_TEST_PHASE"] = phase
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(15)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { process.terminate(); XCTFail("Crash helper timed out"); return }
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 86)
            let reloaded = try XCTUnwrap(HistoryRepository(directory: directory).load().first)
            XCTAssertEqual(try reloaded.payloadData(for: "image"), phase == "before" ? Data([1]) : Data([2]))
        }
    }

    /// Invoked in a child xctest process by the interruption test above.
    func testCrashWriterChild() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["CLIPLET_CRASH_TEST_DIRECTORY"],
            let phase = environment["CLIPLET_CRASH_TEST_PHASE"]
        else { return }
        let directory = URL(fileURLWithPath: path)
        guard directory.lastPathComponent.hasPrefix("Cliplet-crash-test-"), ["before", "after"].contains(phase) else {
            XCTFail("Invalid crash fixture directory"); return
        }
        let repository = HistoryRepository(directory: directory) { data, url in
            if url.lastPathComponent == "history.json", phase == "before" { _exit(86) }
            try data.write(to: url, options: .atomic)
            if url.lastPathComponent == "history.json", phase == "after" { _exit(86) }
        }
        _ = try repository.load()
        repository.save([fixtureItem("next", image: Data([2]))]) { _ in }
        try repository.flush()
        XCTFail("Expected process interruption")
    }
}
