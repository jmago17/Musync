import Foundation

/// Standalone file access to the same persisted state the UI (`AppStore`) uses,
/// so an App Intent can sync headlessly without the app UI being alive.
enum SourceStore {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static var sourcesURL: URL { dir.appendingPathComponent("sources.json") }
    static var historyURL: URL { dir.appendingPathComponent("history.json") }
    static var preparedURL: URL { dir.appendingPathComponent("prepared-syncs.json") }

    static func loadSources() -> [SavedSource] {
        if let data = try? Data(contentsOf: sourcesURL),
           let decoded = try? JSONDecoder().decode([SavedSource].self, from: data) {
            return decoded
        }
        return SavedSource.defaults
    }

    static func saveSources(_ sources: [SavedSource]) {
        try? JSONEncoder().encode(sources).write(to: sourcesURL)
    }

    static func loadHistory() -> [SyncRun] {
        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? JSONDecoder().decode([SyncRun].self, from: data) {
            return decoded
        }
        return []
    }

    static func loadPrepared() -> [PreparedSync] {
        guard let data = try? Data(contentsOf: preparedURL),
              let decoded = try? JSONDecoder().decode([PreparedSync].self, from: data) else {
            return []
        }
        // Prepared matches are temporary. Do not reuse stale catalog results.
        return decoded.filter { Date().timeIntervalSince($0.createdAt) < 24 * 60 * 60 }
    }

    static func savePrepared(_ prepared: PreparedSync) {
        var all = loadPrepared().filter { $0.sourceID != prepared.sourceID }
        all.insert(prepared, at: 0)
        if all.count > 20 { all = Array(all.prefix(20)) }
        try? JSONEncoder().encode(all).write(to: preparedURL)
    }

    static func prepared(id: UUID) -> PreparedSync? {
        loadPrepared().first { $0.id == id }
    }

    static func removePrepared(id: UUID) {
        let all = loadPrepared().filter { $0.id != id }
        try? JSONEncoder().encode(all).write(to: preparedURL)
    }

    static func saveHistory(_ history: [SyncRun]) {
        var h = history
        if h.count > 100 { h = Array(h.prefix(100)) }
        try? JSONEncoder().encode(h).write(to: historyURL)
    }
}
