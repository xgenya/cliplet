import XCTest
@testable import ClipboardNative

/// Opt-in, release-mode measurements. CI archives the report rather than imposing
/// a machine-dependent wall-clock threshold on developer laptops.
final class PerformanceTests: XCTestCase {
    func testSearchTenThousandEntries() {
        let items = (0..<10_000).map { fixtureItem("synthetic clipboard entry \($0)") }
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for query in ["entry 99", "not found", "synthetic"] {
                _ = HistoryPolicy.matching(items, query: query, kind: nil)
            }
        }
    }

    func testLoadImageHeavyHistoryWithoutLoadingPayloads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cliplet-performance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HistoryRepository(directory: directory)
        _ = try repository.load()
        let items = (0..<200).map { fixtureItem(image: Data(repeating: UInt8($0), count: 256 * 1_024)) }
        repository.save(items) { _ in }
        try repository.flush()
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do {
                let loaded = try HistoryRepository(directory: directory).load()
                XCTAssertEqual(loaded.count, 200)
                XCTAssertTrue(loaded.allSatisfy { $0.imageData == nil && $0.payloadReferences?["image"] != nil })
            } catch { XCTFail("Metadata load failed: \(error)") }
        }
    }
}
