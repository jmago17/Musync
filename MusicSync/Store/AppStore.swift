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
    var persistenceError: String?

    var isAuthorized: Bool { authStatus == .authorized }

    private let client = AppleMusicClient()

    // MARK: Persistence

    init() { load() }

    private func load() {
        do {
            let state = try SourceStore.store.read()
            sources = state.sources
            history = state.history
        } catch { persistenceError = error.localizedDescription }
    }

    private func mutate(_ change: (inout SyncDiskStore.State) throws -> Void) -> Bool {
        do {
            let lease = try SourceStore.beginOperation()
            defer { withExtendedLifetime(lease) {} }
            try SourceStore.store.update(change)
            load()
            return true
        } catch { persistenceError = error.localizedDescription; return false }
    }

    // MARK: Auth

    func requestAuthorization() async {
        authStatus = await AppleMusicClient.requestAuthorization()
    }

    func refreshAuthStatus() {
        authStatus = AppleMusicClient.authStatus
        load()
    }

    // MARK: Source CRUD

    @discardableResult
    func addSource(_ source: SavedSource) -> Bool {
        mutate { $0.sources.append(source) }
    }

    @discardableResult
    func updateSource(_ source: SavedSource, expected: SavedSource) -> Bool {
        let saved = mutate { state in
            try SyncDiskStore.replaceSource(source, expected: expected, in: &state)
        }
        if !saved { load() }
        return saved
    }

    func deleteSources(at offsets: IndexSet) {
        let ids = Set(offsets.map { sources[$0].id })
        _ = mutate { state in
            state.sources.removeAll { ids.contains($0.id) }
            state.prepared.removeAll { ids.contains($0.sourceID) }
        }
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
            let subscription = try await MusicSubscription.current
            guard subscription.hasCloudLibraryEnabled else {
                libraryError = "La biblioteca musical en la nube está desactivada. Activa Sincronizar biblioteca en Ajustes → Apps → Música."
                isLoadingLibrary = false
                return
            }
            libraryPlaylists = try await client.libraryPlaylistsDetailed()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            libraryError = "No se pudo leer la biblioteca (\(String(describing: type(of: error)))): \(message)"
        }
        isLoadingLibrary = false
    }

    /// "Adopta" el destino de una fuente: crea una playlist NUEVA gestionada por
    /// MusicSync con el contenido actual del destino, y apunta la fuente a ella.
    /// La playlist original NO se toca (borrarla queda en manos del usuario).
    /// A partir de ahí el modo Reemplazar funciona al 100%.
    func adoptTarget(for sourceID: UUID) async -> String? {
        do {
            let lease = try SourceStore.beginOperation()
            defer { withExtendedLifetime(lease) {} }
            guard var s = try SourceStore.loadSources().first(where: { $0.id == sourceID }) else { return nil }
            let key = sourceID.uuidString
            let pending: SyncDiskStore.PendingAdoption
            if let saved = try SourceStore.store.read().pendingAdoptions[key] {
                guard saved.source == s else { throw SyncIntegrityError.stalePreparation }
                pending = saved
            } else {
                guard let existing = s.lastPlaylistID else { return nil }
                let songIDs = try await client.existingTracks(playlistID: existing).map(\.catalogID)
                let name = (s.targetName.isEmpty ? "Playlist" : s.targetName) + " · Sync"
                let id = try await client.createPlaylist(name: name, description: "Gestionada por MusicSync", songIDs: [])
                pending = SyncDiskStore.PendingAdoption(source: s, playlistID: id, name: name, songIDs: songIDs)
                try SourceStore.store.update {
                    $0.pendingAdoptions[key] = pending
                    $0.completedCreations = $0.completedCreations.filter { $0.value != id }
                }
            }
            try await client.editOwnPlaylist(id: pending.playlistID, name: pending.name,
                                             description: "Gestionada por MusicSync", songIDs: pending.songIDs)
            s.lastPlaylistID = pending.playlistID
            s.targetName = pending.name
            s.lastPlaylistName = pending.name
            s.managed = true
            try SourceStore.store.update { state in
                guard let i = state.sources.firstIndex(where: { $0.id == sourceID }) else { throw SyncIntegrityError.stalePreparation }
                state.sources[i] = s
                state.pendingAdoptions.removeValue(forKey: key)
            }
            load()
            await loadLibraryPlaylists(force: true)
            return pending.playlistID
        } catch {
            libraryError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// Crea una playlist vacía en la biblioteca. **No** se usa desde el selector
    /// (allí la creación se difiere al primer sync para no dejar playlists
    /// vacías); se mantiene por si hace falta creación explícita.
    func createLibraryPlaylist(named name: String) async -> LibraryPlaylist? {
        do {
            let lease = try SourceStore.beginOperation()
            defer { withExtendedLifetime(lease) {} }
            let id = try await client.createPlaylist(name: name,
                                                     description: "Creada desde MusicSync",
                                                     songIDs: [])
            try SourceStore.store.update { $0.completedCreations = $0.completedCreations.filter { $0.value != id } }
            let pl = LibraryPlaylist(id: id, name: name, trackCount: 0, isReplaceable: true)
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
        defer { progress[source.id] = nil; load() }
        do {
            guard let run = try await SyncService.syncOne(id: source.id.uuidString, progress: { [weak self] p in
                Task { @MainActor in self?.progress[source.id] = p }
            }) else { throw SyncIntegrityError.stalePreparation }
            return run
        } catch {
            libraryError = error.localizedDescription
            return SyncRun(date: Date(), sourceName: source.targetName, sourceURL: source.sourceURL,
                           targetName: source.targetName, mode: source.mode, matched: 0, totalTracks: 0,
                           playlistID: source.lastPlaylistID, misses: [], failed: true, errorMessage: error.localizedDescription)
        }
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

    // MARK: Miss resolution

    func searchForMiss(_ miss: MissTrack) async -> [CatalogSong] {
        guard let storefront = try? await client.userStorefront() else { return [] }
        let term = "\(miss.title) \(miss.artist)".trimmingCharacters(in: .whitespaces)
        return (try? await client.searchSongs(term: term, storefront: storefront, limit: 15)) ?? []
    }

    /// Add a manually-chosen song to the run's playlist and mark the miss resolved.
    func resolveMiss(_ miss: MissTrack, with song: CatalogSong, in run: SyncRun) async -> Bool {
        guard !run.failed, let playlistID = run.playlistID else { return false }
        do {
            let lease = try SourceStore.beginOperation()
            defer { withExtendedLifetime(lease) {} }
            let latest = try SourceStore.loadHistory()
            guard let savedRun = latest.first(where: { $0.id == run.id }),
                  let savedMiss = savedRun.misses.first(where: { $0.id == miss.id }) else { return false }
            if savedMiss.resolvedSongID != nil { load(); return true }
            let existing = try await client.existingCatalogIDs(playlistID: playlistID)
            if !existing.contains(song.id) {
                try await client.addTracks(playlistID: playlistID, songIDs: [song.id])
            }
            try SourceStore.store.update { state in
                guard let ri = state.history.firstIndex(where: { $0.id == run.id }),
                      let mi = state.history[ri].misses.firstIndex(where: { $0.id == miss.id }) else { return }
                state.history[ri].misses[mi].resolvedSongID = song.id
                state.history[ri].misses[mi].resolvedTitle = "\(song.title) — \(song.artist)"
                state.history[ri].matched += 1
            }
            load()
            return true
        } catch {
            libraryError = error.localizedDescription
            return false
        }
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
