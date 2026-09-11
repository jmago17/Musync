import Foundation

/// Headless sync of all configured sources, sharing the same on-disk state and
/// the same `Syncer` semantics as the UI. Used by the Shortcuts App Intent so a
/// time-based automation can replace the Mac's weekly LaunchAgent.
struct SyncService: Sendable {
    struct Summary: Sendable {
        var ok: Int = 0
        var failed: Int = 0
        var matched: Int = 0
        var playlists: Int = 0
    }

    static func prepareOne(id: String) async throws -> PreparedSync? {
        guard let source = SourceStore.loadSources().first(where: { $0.id.uuidString == id }) else {
            return nil
        }
        let prepared = try await Syncer().prepare(source: source) { _ in }
        SourceStore.savePrepared(prepared)
        return prepared
    }

    static func applyPrepared(id: UUID) async throws -> SyncRun? {
        guard let prepared = SourceStore.prepared(id: id) else { return nil }
        var sources = SourceStore.loadSources()
        guard let idx = sources.firstIndex(where: { $0.id == prepared.sourceID }) else { return nil }
        let run = try await Syncer().apply(prepared: prepared, source: sources[idx]) { _ in }
        var history = SourceStore.loadHistory()
        history.insert(run, at: 0)
        sources[idx].lastPlaylistID = run.playlistID
        sources[idx].lastPlaylistName = run.targetName
        sources[idx].lastSyncedAt = run.date
        sources[idx].lastMatched = run.matched
        sources[idx].lastMissed = run.misses.count
        SourceStore.saveSources(sources)
        SourceStore.saveHistory(history)
        SourceStore.removePrepared(id: id)
        return run
    }

    /// Sync a single configured source by id. Returns nil if not found.
    static func syncOne(id: String) async -> SyncRun? {
        var sources = SourceStore.loadSources()
        guard let idx = sources.firstIndex(where: { $0.id.uuidString == id }) else { return nil }
        var history = SourceStore.loadHistory()
        let run = await Syncer().run(source: sources[idx]) { _ in }
        history.insert(run, at: 0)
        if !run.failed {
            sources[idx].lastPlaylistID = run.playlistID
            sources[idx].lastPlaylistName = run.targetName
            sources[idx].lastSyncedAt = run.date
            sources[idx].lastMatched = run.matched
            sources[idx].lastMissed = run.misses.count
            SourceStore.saveSources(sources)
        }
        SourceStore.saveHistory(history)
        return run
    }

    static func syncAll() async -> Summary {
        var sources = SourceStore.loadSources()
        var history = SourceStore.loadHistory()
        let syncer = Syncer()
        var summary = Summary(playlists: sources.count)

        for i in sources.indices {
            let run = await syncer.run(source: sources[i]) { _ in }
            history.insert(run, at: 0)
            if run.failed {
                summary.failed += 1
            } else {
                summary.ok += 1
                summary.matched += run.matched
                sources[i].lastPlaylistID = run.playlistID
                sources[i].lastPlaylistName = run.targetName
                sources[i].lastSyncedAt = run.date
                sources[i].lastMatched = run.matched
                sources[i].lastMissed = run.misses.count
            }
        }

        SourceStore.saveSources(sources)
        SourceStore.saveHistory(history)
        return summary
    }
}
