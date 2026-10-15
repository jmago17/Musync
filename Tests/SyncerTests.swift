import XCTest
@testable import MusicSyncCore

private actor FakeClient: MusicSyncClient {
    var tracks: [SourceTrack]
    var mapping: [String: CatalogSong]
    var fallbackCalls = 0
    var edits: [[String]] = []
    var additions: [[String]] = []
    var existing: [String] = []
    var creationCount = 0
    var failRead = false
    var destinationVisible = true
    var incompleteEdit = false
    init(ids: [String], matching: [String]) {
        tracks = ids.map { SourceTrack(title: $0, artist: "Artist", srcID: $0) }
        mapping = Dictionary(uniqueKeysWithValues: matching.map { ($0, CatalogSong(id: "dest-" + $0, title: $0, artist: "Artist")) })
    }
    func userStorefront() async throws -> String { "us" }
    func fetchSourcePlaylist(url: String) async throws -> SourcePlaylist { SourcePlaylist(title: "Fixture", storefront: "es", tracks: tracks) }
    func equivalents(ids: [String], storefront: String) async throws -> [String: CatalogSong] { mapping }
    func match(_ track: SourceTrack, storefront: String) async throws -> CatalogSong? { fallbackCalls += 1; return nil }
    func playlistExists(_ id: String) async throws -> Bool { destinationVisible }
    func findPlaylist(named name: String) async throws -> String? { nil }
    func createPlaylist(name: String, description: String, songIDs: [String]) async throws -> String { creationCount += 1; return "created" }
    func editOwnPlaylist(id: String, name: String, description: String, songIDs: [String]) async throws {
        if incompleteEdit { throw SyncIntegrityError.incompleteCatalog }
        edits.append(songIDs)
    }
    func addTracks(playlistID: String, songIDs: [String]) async throws { additions.append(songIDs); existing += songIDs }
    func existingTracks(playlistID: String) async throws -> [(catalogID: String, title: String, artist: String)] {
        if failRead { throw SyncIntegrityError.incompleteCatalog }
        return existing.map { ($0, $0, "Artist") }
    }
    nonisolated func ownsPlaylist(_ id: String) throws -> Bool { true }
    func hideDestination() { destinationVisible = false }
    func setReadFailure() { failRead = true }
    func setIncompleteEdit() { incompleteEdit = true }
}

@MainActor
final class SyncerTests: XCTestCase {
    private func source(mode: SyncMode = .replace) -> SavedSource {
        SavedSource(sourceURL: "fixture", targetName: "Fixture", mode: mode, lastPlaylistID: "destination")
    }
    func testEquivalentFirstPreservesDuplicateOrder() async throws {
        let client = FakeClient(ids: ["b", "a", "b"], matching: ["a", "b"])
        let run = await Syncer(client: client).run(source: source()) { _ in }
        XCTAssertFalse(run.failed)
        let edits = await client.edits
        let fallbackCalls = await client.fallbackCalls
        XCTAssertEqual(edits, [["dest-b", "dest-a", "dest-b"]])
        XCTAssertEqual(fallbackCalls, 0)
    }
    func testMissingTrackBlocksReplacementAndPreservesDiagnostics() async throws {
        let client = FakeClient(ids: ["a", "missing", "missing"], matching: ["a"])
        let run = await Syncer(client: client).run(source: source()) { _ in }
        XCTAssertTrue(run.failed)
        XCTAssertEqual(run.totalTracks, 3)
        XCTAssertEqual(run.misses.count, 2)
        let edits = await client.edits
        let fallbackCalls = await client.fallbackCalls
        XCTAssertTrue(edits.isEmpty)
        XCTAssertEqual(fallbackCalls, 1)
    }
    func testPartialDestinationReadBlocksAppend() async {
        let client = FakeClient(ids: ["a"], matching: ["a"])
        await client.setReadFailure()
        let run = await Syncer(client: client).run(source: source(mode: .append)) { _ in }
        XCTAssertTrue(run.failed)
        let additions = await client.additions
        XCTAssertTrue(additions.isEmpty)
    }
    func testAppendRetryDoesNotDuplicateVisibleTracks() async {
        let client = FakeClient(ids: ["a", "a", "b"], matching: ["a", "b"])
        let syncer = Syncer(client: client)
        let first = await syncer.run(source: source(mode: .append)) { _ in }
        let second = await syncer.run(source: source(mode: .append)) { _ in }
        XCTAssertFalse(first.failed)
        XCTAssertFalse(second.failed)
        let additions = await client.additions
        XCTAssertEqual(additions, [["dest-a", "dest-b"]])
    }
    func testStalePreparedConfigurationCannotWrite() async throws {
        let client = FakeClient(ids: ["a"], matching: ["a"])
        let syncer = Syncer(client: client)
        let prepared = try await syncer.prepare(source: source()) { _ in }
        var changed = source(); changed.targetName = "Changed"
        do { _ = try await syncer.apply(prepared: prepared, source: changed) { _ in }; XCTFail("Expected stale preparation") }
        catch { XCTAssertTrue(error is SyncIntegrityError) }
        let edits = await client.edits
        XCTAssertTrue(edits.isEmpty)
    }
    func testTemporarilyMissingCheckpointDoesNotCreateDuplicate() async {
        let client = FakeClient(ids: ["a"], matching: ["a"])
        await client.hideDestination()
        let run = await Syncer(client: client).run(source: source()) { _ in }
        XCTAssertTrue(run.failed)
        let creations = await client.creationCount
        let edits = await client.edits
        XCTAssertEqual(creations, 0)
        XCTAssertTrue(edits.isEmpty)
    }
    func testPartialCatalogCannotReportReplacementSuccess() async {
        let client = FakeClient(ids: ["a", "b"], matching: ["a", "b"])
        await client.setIncompleteEdit()
        let run = await Syncer(client: client).run(source: source()) { _ in }
        XCTAssertTrue(run.failed)
        let edits = await client.edits
        XCTAssertTrue(edits.isEmpty)
    }
}
