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
