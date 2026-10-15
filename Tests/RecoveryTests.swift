import XCTest
@testable import MusicSyncCore

private struct HTTPFailure: Error { let status: Int }
private actor RetryFixture {
    var attempts = 0
    let statuses: [Int]
    init(_ statuses: [Int]) { self.statuses = statuses }
    func request() throws -> Data {
        let index = attempts; attempts += 1
        if index < statuses.count { throw HTTPFailure(status: statuses[index]) }
        return Data("ok".utf8)
    }
}

@MainActor
final class RecoveryTests: XCTestCase {
    func testReadRetriesTransientErrorsButNotAuthorization() async throws {
        let transient = RetryFixture([429, 503])
        let data = try await ReadRetry.data(request: { try await transient.request() }, status: { ($0 as? HTTPFailure)?.status }, sleep: { _ in })
        XCTAssertEqual(data, Data("ok".utf8))
        let attempts = await transient.attempts
        XCTAssertEqual(attempts, 3)
        let denied = RetryFixture([403])
        do {
            _ = try await ReadRetry.data(request: { try await denied.request() }, status: { ($0 as? HTTPFailure)?.status }, sleep: { _ in })
            XCTFail("Expected authorization failure")
        } catch {}
        let deniedAttempts = await denied.attempts
        XCTAssertEqual(deniedAttempts, 1)
    }
    func testReadRetryLimit() async {
        let fixture = RetryFixture([500, 500, 500, 500])
        do {
            _ = try await ReadRetry.data(request: { try await fixture.request() }, status: { ($0 as? HTTPFailure)?.status }, sleep: { _ in })
            XCTFail("Expected retry exhaustion")
        } catch {}
        let attempts = await fixture.attempts
        XCTAssertEqual(attempts, 3)
    }
    func testCreationLostResponseDoesNotCreateAgain() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let creator = PlaylistCreator(store: SyncDiskStore(directory: dir))
        do {
            _ = try await creator.create(name: "Fixture", description: "Fixture", request: { throw URLError(.networkConnectionLost) }, wasRejected: { _ in false })
            XCTFail("Expected failure")
        } catch {}
        do {
            _ = try await creator.create(name: "Fixture", description: "Fixture", request: { XCTFail("Must not issue duplicate POST"); return "id" }, wasRejected: { _ in false })
            XCTFail("Expected uncertain creation")
        } catch { XCTAssertTrue(error is SyncIntegrityError) }
    }
    func testDefinitiveCreationRejectionCanRetryAndPersistsOwnership() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let creator = PlaylistCreator(store: SyncDiskStore(directory: dir))
        do {
            _ = try await creator.create(name: "Fixture", description: "Fixture", request: { throw HTTPFailure(status: 403) }, wasRejected: { _ in true })
        } catch {}
        let id = try await creator.create(name: "Fixture", description: "Fixture", request: { "new-id" }, wasRejected: { _ in false })
        XCTAssertEqual(id, "new-id")
        XCTAssertEqual(try creator.store.read().createdPlaylistIDs, ["new-id"])
        XCTAssertTrue(try creator.store.read().pendingCreations.isEmpty)
    }
    func testCreatedReceiptSurvivesRestartUntilAtomicCheckpoint() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SyncDiskStore(directory: dir)
        let source = SavedSource(sourceURL: "fixture", targetName: "Fixture")
        try store.update { $0.sources = [source] }
        _ = try await PlaylistCreator(store: store).create(name: "Fixture", description: "Fixture", request: { "created-id" }, wasRejected: { _ in false })
        let restarted = SyncDiskStore(directory: dir)
        let recovered = try await PlaylistCreator(store: restarted).create(name: "Fixture", description: "Fixture", request: {
            XCTFail("Must reuse the durable receipt after a crash"); return "duplicate"
        }, wasRejected: { _ in false })
        XCTAssertEqual(recovered, "created-id")
        try restarted.checkpoint(source: source, playlistID: recovered)
        XCTAssertEqual(try restarted.read().sources.first?.lastPlaylistID, recovered)
        XCTAssertTrue(try restarted.read().completedCreations.isEmpty)
    }
    func testStaleEditorCannotOverwriteShortcutCheckpoint() throws {
        let original = SavedSource(sourceURL: "fixture", targetName: "Fixture")
        var draft = original; draft.mode = .append
        var current = original; current.lastPlaylistID = "created-by-shortcut"
        var state = SyncDiskStore.State(sources: [current])
        XCTAssertThrowsError(try SyncDiskStore.replaceSource(draft, expected: original, in: &state))
        XCTAssertEqual(state.sources, [current])
        var freshDraft = current; freshDraft.mode = .append
        try SyncDiskStore.replaceSource(freshDraft, expected: current, in: &state)
        XCTAssertEqual(state.sources[0].lastPlaylistID, "created-by-shortcut")
        XCTAssertEqual(state.sources[0].mode, .append)
    }
    func testCheckpointDoesNotReviveStalePreparation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SyncDiskStore(directory: dir)
        let old = SavedSource(sourceURL: "old", targetName: "Fixture")
        var current = old; current.sourceURL = "new"
        let stale = PreparedSync(sourceID: old.id, sourceURL: old.sourceURL, targetName: old.targetName, mode: .replace, songIDs: ["a"], totalTracks: 1, misses: [], storefront: "us", sourceSnapshot: old)
        var fresh = stale; fresh.id = UUID(); fresh.sourceSnapshot = current
        try store.update { $0.sources = [current]; $0.prepared = [stale, fresh] }
        try store.checkpoint(source: current, playlistID: "new-playlist")
        let state = try store.read()
        XCTAssertEqual(state.prepared[0].sourceSnapshot, old)
        XCTAssertNotEqual(state.prepared[0].sourceSnapshot, state.sources[0])
        XCTAssertEqual(state.prepared[1].sourceSnapshot, state.sources[0])
    }
    func testCheckpointSurvivesInterruptedPopulation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SyncDiskStore(directory: dir)
        let source = SavedSource(sourceURL: "fixture", targetName: "Fixture")
        try store.update { $0.sources = [source] }
        try store.checkpoint(source: source, playlistID: "created-before-failure")
        XCTAssertEqual(try SyncDiskStore(directory: dir).read().sources[0].lastPlaylistID, "created-before-failure")
    }
}
