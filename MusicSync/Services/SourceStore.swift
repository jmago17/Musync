import Foundation
import Darwin

/// Cross-process lock: UI and Shortcuts can run in different processes. The
/// operation lease spans awaits; the short state lock protects atomic commits.
final class StoreLease: @unchecked Sendable {
    private let descriptor: Int32
    init(url: URL, nonblocking: Bool) throws {
        descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        if flock(descriptor, LOCK_EX | (nonblocking ? LOCK_NB : 0)) != 0 {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK { throw SyncIntegrityError.busy }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

struct SyncDiskStore: Sendable {
    struct PendingAdoption: Codable {
        var source: SavedSource
        var playlistID: String
        var name: String
        var songIDs: [String]
    }
    struct State: Codable {
        var sources: [SavedSource]
        var history: [SyncRun] = []
        var prepared: [PreparedSync] = []
        var createdPlaylistIDs: Set<String> = []
        var pendingCreations: Set<String> = []
        var completedCreations: [String: String] = [:]
        var pendingAppends: [String: [String]] = [:]
        var pendingAdoptions: [String: PendingAdoption] = [:]
    }
    let directory: URL
    var stateURL: URL { directory.appendingPathComponent("state-v1.json") }

    private func makeDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func beginOperation() throws -> StoreLease {
        try makeDirectory()
        return try StoreLease(url: directory.appendingPathComponent("operation.lock"), nonblocking: true)
    }

    private func readState() throws -> State {
        if FileManager.default.fileExists(atPath: stateURL.path) {
            return try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))
        }
        // Only absence permits defaults. Corrupt/unreadable legacy files must
        // never be silently replaced with defaults.
        func legacy<T: Decodable>(_ file: String, fallback: T) throws -> T {
            let url = directory.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        }
        return try State(sources: legacy("sources.json", fallback: SavedSource.defaults),
                         history: legacy("history.json", fallback: [SyncRun]()),
                         prepared: legacy("prepared-syncs.json", fallback: [PreparedSync]()),
                         createdPlaylistIDs: Set(UserDefaults.standard.stringArray(forKey: "MusicSync.createdPlaylistIDs") ?? []))
    }

    func read() throws -> State {
        try makeDirectory()
        let lease = try StoreLease(url: directory.appendingPathComponent("state.lock"), nonblocking: false)
        defer { withExtendedLifetime(lease) {} }
        return try readState()
    }

    @discardableResult
    func update<T>(_ change: (inout State) throws -> T) throws -> T {
        try makeDirectory()
        let lease = try StoreLease(url: directory.appendingPathComponent("state.lock"), nonblocking: false)
        defer { withExtendedLifetime(lease) {} }
        var state = try readState()
        let result = try change(&state)
        state.history = Array(state.history.prefix(100))
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        return result
    }
    static func replaceSource(_ source: SavedSource, expected: SavedSource, in state: inout State) throws {
        guard source.id == expected.id,
              let i = state.sources.firstIndex(where: { $0.id == expected.id }),
              state.sources[i] == expected else { throw SyncIntegrityError.stalePreparation }
        state.sources[i] = source
    }

    func checkpoint(source: SavedSource, playlistID: String) throws {
        try update { state in
            guard let i = state.sources.firstIndex(where: { $0.id == source.id }), state.sources[i] == source else { throw SyncIntegrityError.stalePreparation }
            state.completedCreations = state.completedCreations.filter { $0.value != playlistID }
            state.sources[i].lastPlaylistID = playlistID
            state.sources[i].lastPlaylistName = source.targetName
            // Keep prepared destination snapshots aligned with a newly created
            // playlist so a failed append can be safely retried.
            for p in state.prepared.indices where state.prepared[p].sourceSnapshot == source {
                state.prepared[p].sourceSnapshot = state.sources[i]
            }
        }
    }

}

enum SourceStore {
    static let store = SyncDiskStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MusicSync", isDirectory: true))
    static func beginOperation() throws -> StoreLease { try store.beginOperation() }
    static func loadSources() throws -> [SavedSource] { try store.read().sources }
    static func loadHistory() throws -> [SyncRun] { try store.read().history }
    static func loadPrepared() throws -> [PreparedSync] {
        try store.read().prepared.filter { Date().timeIntervalSince($0.createdAt) < 24 * 60 * 60 }
    }
    static func savePrepared(_ prepared: PreparedSync) throws {
        try store.update {
            $0.prepared.removeAll { $0.sourceID == prepared.sourceID }
            $0.prepared.insert(prepared, at: 0)
            $0.prepared = Array($0.prepared.prefix(20))
        }
    }
    static func prepared(id: UUID) throws -> PreparedSync? {
        try loadPrepared().first { $0.id == id }
    }
    static func checkpoint(source: SavedSource, playlistID: String) throws {
        try store.checkpoint(source: source, playlistID: playlistID)
    }
    static func record(_ run: SyncRun, sourceID: UUID, preparedID: UUID? = nil) throws {
        try store.update { state in
            state.history.insert(run, at: 0)
            if !run.failed, let i = state.sources.firstIndex(where: { $0.id == sourceID }) {
                state.sources[i].lastPlaylistID = run.playlistID
                state.sources[i].lastPlaylistName = run.targetName
                state.sources[i].lastSyncedAt = run.date
                state.sources[i].lastMatched = run.matched
                state.sources[i].lastMissed = run.misses.count
            }
            if let preparedID { state.prepared.removeAll { $0.id == preparedID } }
        }
    }
}
