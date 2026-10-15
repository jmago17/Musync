import Foundation

struct SyncService: Sendable {
    struct Summary: Sendable {
        var ok = 0
        var failed = 0
        var matched = 0
        var playlists = 0
    }

    static func prepareOne(id: String) async throws -> PreparedSync? {
        let lease = try SourceStore.beginOperation()
        defer { withExtendedLifetime(lease) {} }
        guard let source = try SourceStore.loadSources().first(where: { $0.id.uuidString == id }) else { return nil }
        let prepared = try await Syncer().prepare(source: source) { _ in }
        try SourceStore.savePrepared(prepared)
        return prepared
    }

    static func applyPrepared(id: UUID) async throws -> SyncRun? {
        let lease = try SourceStore.beginOperation()
        defer { withExtendedLifetime(lease) {} }
        guard let prepared = try SourceStore.prepared(id: id),
              let source = try SourceStore.loadSources().first(where: { $0.id == prepared.sourceID }) else { return nil }
        let run = try await Syncer().apply(prepared: prepared, source: source) { _ in }
        try SourceStore.record(run, sourceID: source.id, preparedID: id)
        return run
    }

    static func syncOne(id: String, progress: @escaping @Sendable (SyncProgress) -> Void = { _ in }) async throws -> SyncRun? {
        let lease = try SourceStore.beginOperation()
        defer { withExtendedLifetime(lease) {} }
        guard let source = try SourceStore.loadSources().first(where: { $0.id.uuidString == id }) else { return nil }
        let run = await Syncer().run(source: source, progress: progress)
        try SourceStore.record(run, sourceID: source.id)
        return run
    }

    static func syncAll() async throws -> Summary {
        let sources = try SourceStore.loadSources()
        var summary = Summary(playlists: sources.count)
        for source in sources {
            try Task.checkCancellation()
            if let run = try await syncOne(id: source.id.uuidString) {
                if run.failed { summary.failed += 1 }
                else { summary.ok += 1; summary.matched += run.matched }
            } else { summary.failed += 1 }
        }
        return summary
    }
}
