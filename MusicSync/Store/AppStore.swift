import Foundation
import Observation
import MusicKit
import UserNotifications

@MainActor
@Observable
final class AppStore {

    // MARK: State
    var authStatus: MusicAuthorization.Status = AppleMusicClient.authStatus
    var sources: [SavedSource] = []
    var history: [SyncRun] = []

    /// Live progress keyed by source id while a sync is running.
    var progress: [UUID: SyncProgress] = [:]
    var isSyncingAll = false

    /// Playlists existentes en la biblioteca, para elegir destino.
    var libraryPlaylists: [LibraryPlaylist] = []
    var isLoadingLibrary = false
    var libraryError: String?

    var isAuthorized: Bool { authStatus == .authorized }

    private let syncer = Syncer()
    private let client = AppleMusicClient()

    // MARK: Persistence

    private static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private var sourcesURL: URL { Self.supportDir.appendingPathComponent("sources.json") }
    private var historyURL: URL { Self.supportDir.appendingPathComponent("history.json") }

    init() {
        load()
    }

    private func load() {
        if let data = try? Data(contentsOf: sourcesURL),
           let decoded = try? JSONDecoder().decode([SavedSource].self, from: data) {
            sources = decoded
        } else {
            sources = SavedSource.defaults
            persistSources()
        }
        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? JSONDecoder().decode([SyncRun].self, from: data) {
            history = decoded
        }
    }

    private func persistSources() {
        try? JSONEncoder().encode(sources).write(to: sourcesURL)
    }
    private func persistHistory() {
        // Keep the last 100 runs.
        if history.count > 100 { history = Array(history.prefix(100)) }
        try? JSONEncoder().encode(history).write(to: historyURL)
    }

    // MARK: Auth

    func requestAuthorization() async {
        authStatus = await AppleMusicClient.requestAuthorization()
    }

    func refreshAuthStatus() {
        authStatus = AppleMusicClient.authStatus
    }

    // MARK: Source CRUD

    func addSource(_ s: SavedSource) {
        sources.append(s)
        persistSources()
    }

    func updateSource(_ s: SavedSource) {
        guard let i = sources.firstIndex(where: { $0.id == s.id }) else { return }
        sources[i] = s
        persistSources()
    }

    func deleteSources(at offsets: IndexSet) {
        sources.remove(atOffsets: offsets)
        persistSources()
    }

    func binding(for id: UUID) -> SavedSource? { sources.first(where: { $0.id == id }) }

    /// Fetch the source title without syncing — used by the add sheet.
    func peekTitle(url: String) async -> String? {
        try? await client.fetchSourcePlaylist(url: url).title
    }

    // MARK: Library playlists (destino)

    /// Carga las playlists de la biblioteca para el selector de destino.
    /// `force` ignora la caché en memoria (pull-to-refresh).
    func loadLibraryPlaylists(force: Bool = false) async {
        guard isAuthorized else { return }
        if !force && !libraryPlaylists.isEmpty { return }
        guard !isLoadingLibrary else { return }
        isLoadingLibrary = true
        libraryError = nil
        do {
            libraryPlaylists = try await client.libraryPlaylistsDetailed()
        } catch {
            libraryError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoadingLibrary = false
    }

    /// Crea una playlist vacía en la biblioteca y la deja seleccionable al vuelo.
    func createLibraryPlaylist(named name: String) async -> LibraryPlaylist? {
        do {
            let id = try await client.createPlaylist(name: name,
                                                     description: "Creada desde MusicSync",
                                                     songIDs: [])
            let pl = LibraryPlaylist(id: id, name: name, trackCount: 0)
            libraryPlaylists.append(pl)
            libraryPlaylists.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return pl
        } catch {
            libraryError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    // MARK: Syncing

    @discardableResult
    func sync(_ source: SavedSource) async -> SyncRun {
        progress[source.id] = SyncProgress()
        let run = await syncer.run(source: source) { [weak self] p in
            Task { @MainActor in self?.progress[source.id] = p }
        }
        progress[source.id] = nil
        record(run, for: source)
        return run
    }

    func syncAll() async {
        guard !isSyncingAll else { return }
        isSyncingAll = true
        defer { isSyncingAll = false }
        var ok = 0, fail = 0
        for source in sources {
            let run = await sync(source)
            if run.failed { fail += 1 } else { ok += 1 }
        }
        notify(title: "MusicSync",
               body: fail == 0 ? "\(ok) playlists sincronizadas." : "\(ok) OK, \(fail) con error.")
    }

    private func record(_ run: SyncRun, for source: SavedSource) {
        history.insert(run, at: 0)
        persistHistory()
        if !run.failed, var s = sources.first(where: { $0.id == source.id }) {
            s.lastPlaylistID = run.playlistID
            s.lastPlaylistName = run.targetName
            s.lastSyncedAt = run.date
            s.lastMatched = run.matched
            s.lastMissed = run.misses.count
            updateSource(s)
        }
    }

    // MARK: Miss resolution

    func searchForMiss(_ miss: MissTrack) async -> [CatalogSong] {
        guard let storefront = try? await client.userStorefront() else { return [] }
        let term = "\(miss.title) \(miss.artist)".trimmingCharacters(in: .whitespaces)
        return (try? await client.searchSongs(term: term, storefront: storefront, limit: 15)) ?? []
    }

    /// Add a manually-chosen song to the run's playlist and mark the miss resolved.
    func resolveMiss(_ miss: MissTrack, with song: CatalogSong, in run: SyncRun) async -> Bool {
        guard let playlistID = run.playlistID else { return false }
        do {
            try await client.addTracks(playlistID: playlistID, songIDs: [song.id])
        } catch {
            return false
        }
        guard let ri = history.firstIndex(where: { $0.id == run.id }),
              let mi = history[ri].misses.firstIndex(where: { $0.id == miss.id }) else { return true }
        history[ri].misses[mi].resolvedSongID = song.id
        history[ri].misses[mi].resolvedTitle = "\(song.title) — \(song.artist)"
        history[ri].matched += 1
        persistHistory()
        return true
    }

    // MARK: Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
