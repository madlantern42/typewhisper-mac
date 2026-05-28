import XCTest
@testable import TypeWhisper

final class DictionarySyncMergeTests: XCTestCase {

    private func entry(
        _ id: UUID = UUID(),
        original: String,
        replacement: String? = nil,
        modifiedAt: Date
    ) -> SyncEntry {
        SyncEntry(
            id: id,
            type: replacement == nil ? "term" : "correction",
            original: original,
            replacement: replacement,
            caseSensitive: false,
            isEnabled: true,
            modifiedAt: modifiedAt
        )
    }

    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    func testRemoteAddsNewEntry() {
        let local = [entry(original: "Supabase", modifiedAt: t0)]
        let remoteOnly = entry(original: "Kubernetes", modifiedAt: t0)
        let result = DictionarySyncMerge.merge(local: local, remote: [remoteOnly])

        XCTAssertEqual(result.toApplyLocally, [remoteOnly])
        XCTAssertEqual(result.mergedDocument.count, 2)
    }

    func testNewerRemoteWins() {
        let id = UUID()
        let local = [entry(id, original: "supabase", replacement: "Supabase", modifiedAt: t0)]
        let remote = [entry(id, original: "supabase", replacement: "SupaBase", modifiedAt: t1)]
        let result = DictionarySyncMerge.merge(local: local, remote: remote)

        XCTAssertEqual(result.toApplyLocally.count, 1)
        XCTAssertEqual(result.toApplyLocally.first?.replacement, "SupaBase")
        XCTAssertEqual(result.mergedDocument.first?.replacement, "SupaBase")
    }

    func testOlderRemoteIgnored() {
        let id = UUID()
        let local = [entry(id, original: "supabase", replacement: "Supabase", modifiedAt: t1)]
        let remote = [entry(id, original: "supabase", replacement: "OLD", modifiedAt: t0)]
        let result = DictionarySyncMerge.merge(local: local, remote: remote)

        XCTAssertTrue(result.toApplyLocally.isEmpty)
        XCTAssertEqual(result.mergedDocument.first?.replacement, "Supabase")
    }

    func testTieKeepsLocal() {
        let id = UUID()
        let local = [entry(id, original: "supabase", replacement: "LOCAL", modifiedAt: t0)]
        let remote = [entry(id, original: "supabase", replacement: "REMOTE", modifiedAt: t0)]
        let result = DictionarySyncMerge.merge(local: local, remote: remote)

        XCTAssertTrue(result.toApplyLocally.isEmpty)
        XCTAssertEqual(result.mergedDocument.first?.replacement, "LOCAL")
    }

    func testUnionPropagatesBothSides() {
        let a = entry(original: "Apple", modifiedAt: t0)
        let b = entry(original: "Banana", modifiedAt: t0)
        let result = DictionarySyncMerge.merge(local: [a], remote: [b])
        XCTAssertEqual(result.mergedDocument.count, 2)
        XCTAssertEqual(result.toApplyLocally, [b])
    }

    func testEmptyRemoteNoOp() {
        let local = [entry(original: "Supabase", modifiedAt: t0)]
        let result = DictionarySyncMerge.merge(local: local, remote: [])
        XCTAssertTrue(result.toApplyLocally.isEmpty)
        XCTAssertEqual(result.mergedDocument.count, 1)
    }
}
