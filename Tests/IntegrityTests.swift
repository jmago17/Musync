import XCTest
@testable import MusicSyncCore

final class IntegrityTests: XCTestCase {
    func testDuplicateIDsPreserveOrderAndMultiplicity() throws {
        XCTAssertEqual(try SyncAlgorithms.ordered(["b", "a", "b"], resources: ["a", "b"]) { $0 }, ["b", "a", "b"])
        XCTAssertThrowsError(try SyncAlgorithms.ordered(["a", "missing"], resources: ["a"]) { $0 })
    }
    func testAppendDeduplicatesIncomingAndExistingIDs() {
        XCTAssertEqual(SyncAlgorithms.fresh(["a", "b", "b", "c"], existing: ["a"]), ["b", "c"])
    }
    func testStrictSearchDoesNotAcceptSameArtistDifferentSong() {
        let hit = CatalogSong(id: "1", title: "Other", artist: "Artist")
        XCTAssertNil(SyncAlgorithms.strictMatch([hit], title: "Wanted", artist: "Artist"))
        XCTAssertNil(SyncAlgorithms.strictMatch([hit], title: "Other", artist: "Different"))
        XCTAssertEqual(SyncAlgorithms.strictMatch([hit], title: " OTHER ", artist: "artist")?.id, "1")
        XCTAssertNil(SyncAlgorithms.strictMatch([hit, CatalogSong(id: "2", title: "Other", artist: "Artist")], title: "Other", artist: "Artist"))
    }
    func testEquivalentMappingUsesMetaAndAllowsMissingResults() throws {
        let json = #"{"data":[{"id":"y","attributes":{"name":"Y","artistName":"B"}},{"id":"x","attributes":{"name":"X","artistName":"A"}}],"meta":{"filters":{"equivalents":{"a":[{"id":"x"}],"b":[{"id":"y"}],"c":[]}}}}"#
        let response = try JSONDecoder().decode(EquivalentSongsResponse.self, from: Data(json.utf8))
        let matches = try response.matches(requested: ["a", "b", "c"])
        XCTAssertEqual(matches["a"]?.id, "x")
        XCTAssertEqual(matches["b"]?.id, "y")
        XCTAssertNil(matches["c"])
        let incomplete = json.replacingOccurrences(of: #""id":"x","attributes""#, with: #""id":"z","attributes""#)
        XCTAssertThrowsError(try JSONDecoder().decode(EquivalentSongsResponse.self, from: Data(incomplete.utf8)).matches(requested: ["a"]))
    }
    func testStorageMigrationCorruptionAndOperationLock() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SyncDiskStore(directory: dir)
        let source = SavedSource(sourceURL: "fixture", targetName: "Fixture")
        try JSONEncoder().encode([source]).write(to: dir.appendingPathComponent("sources.json"))
        XCTAssertEqual(try store.read().sources, [source])
        try store.update { $0.sources[0].targetName = "Updated" }
        XCTAssertEqual(try store.read().sources[0].targetName, "Updated")
        var lease: StoreLease? = try store.beginOperation()
        XCTAssertThrowsError(try SyncDiskStore(directory: dir).beginOperation())
        withExtendedLifetime(lease) {}
        lease = nil
        XCTAssertNoThrow(try store.beginOperation())
        try Data("invalid".utf8).write(to: store.stateURL)
        XCTAssertThrowsError(try store.update { $0.sources = [] })
        XCTAssertEqual(try String(contentsOf: store.stateURL, encoding: .utf8), "invalid")
    }
    func testConcurrentTransactionsDoNotLoseUpdates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SyncDiskStore(directory: dir)
        try store.update { $0.sources = [] }
        DispatchQueue.concurrentPerform(iterations: 30) { n in
            do { try store.update { $0.sources.append(SavedSource(sourceURL: "fixture", targetName: "\(n)")) } }
            catch { XCTFail("\(error)") }
        }
        XCTAssertEqual(try store.read().sources.count, 30)
    }
}
