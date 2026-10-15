import Foundation

/// Live progress of a single sync, surfaced to the UI.
struct SyncProgress: Sendable, Equatable {
    enum Phase: Sendable, Equatable {
        case fetching
        case matching(done: Int, total: Int)
        case writing
        case done
    }
    var phase: Phase = .fetching
    var matched: Int = 0

    var text: String {
        switch phase {
        case .fetching:                 return "Leyendo la playlist origen…"
        case .matching(let d, let t):   return "Buscando en tu catálogo… \(d)/\(t)"
        case .writing:                  return "Escribiendo en tu biblioteca…"
        case .done:                     return "Listo."
        }
    }
}

/// Runs the mirror for one configured source and returns a history entry.
/// Validates complete replacement and deduplicated append before mutation.
struct Syncer: Sendable {
    let client: any MusicSyncClient
    var checkpoint: @Sendable (SavedSource, String) throws -> Void = { _, _ in }

    /// Expensive half of a sync: fetch the source and match every track.
    /// The result can cross an App Intent boundary without repeating the work.
    func prepare(source: SavedSource,
                 progress: @escaping @Sendable (SyncProgress) -> Void) async throws -> PreparedSync {
        var p = SyncProgress()
        progress(p)
        let storefront = try await client.userStorefront()
        let src = try await client.fetchSourcePlaylist(url: source.sourceURL)
        let targetName = source.targetName.isEmpty ? src.title : source.targetName
        var songIDs: [String] = []
        var misses: [MissTrack] = []
        var fallbackMatches: [SourceTrack: CatalogSong] = [:]
        var fallbackMisses = Set<SourceTrack>()
        let equivalents = try await client.equivalents(ids: SyncAlgorithms.unique(src.tracks.map(\.srcID)), storefront: storefront)
        for (i, track) in src.tracks.enumerated() {
            try Task.checkCancellation()
            let song: CatalogSong?
            if let equivalent = equivalents[track.srcID] { song = equivalent }
            else if let cached = fallbackMatches[track] { song = cached }
            else if fallbackMisses.contains(track) { song = nil }
            else {
                song = try await client.match(track, storefront: storefront)
                if let song { fallbackMatches[track] = song } else { fallbackMisses.insert(track) }
            }
            if let song {
                songIDs.append(song.id)
            } else {
                misses.append(MissTrack(title: track.title, artist: track.artist,
                                        isrc: track.isrc, srcID: track.srcID))
            }
            p.phase = .matching(done: i + 1, total: src.tracks.count)
            p.matched = songIDs.count
            progress(p)
        }
        guard !songIDs.isEmpty else {
            throw SyncSplitError.noSongsMatched
        }
        return PreparedSync(sourceID: source.id, sourceURL: source.sourceURL,
                            targetName: targetName, mode: source.mode,
                            songIDs: songIDs, totalTracks: src.tracks.count,
                            misses: misses, storefront: storefront, sourceSnapshot: source)
    }

    /// Lightweight half: resolve the destination and write a prepared batch.
    func apply(prepared: PreparedSync, source: SavedSource,
               progress: @escaping @Sendable (SyncProgress) -> Void) async throws -> SyncRun {
        guard let snapshot = prepared.sourceSnapshot, snapshot == source,
              let storefront = prepared.storefront,
              storefront == (try await client.userStorefront()) else {
            throw SyncIntegrityError.stalePreparation
        }
        if prepared.mode == .replace && !prepared.misses.isEmpty {
            throw SyncIntegrityError.incompleteSource
        }
        try Task.checkCancellation()
        var p = SyncProgress(phase: .writing, matched: prepared.songIDs.count)
        progress(p)
        let description = "Mirror de \(prepared.sourceURL) · MusicSync"
        let existing = try await resolveExistingID(source, targetName: prepared.targetName)
        let result = try await write(mode: prepared.mode, existing: existing,
                                     targetName: prepared.targetName,
                                     description: description, songIDs: prepared.songIDs, source: source)
        p.phase = .done
        progress(p)
        return SyncRun(date: Date(), sourceName: prepared.targetName,
                       sourceURL: prepared.sourceURL, targetName: prepared.targetName,
                       mode: prepared.mode, matched: prepared.songIDs.count,
                       totalTracks: prepared.totalTracks, playlistID: result.playlistID,
                       misses: prepared.misses,
                       surplus: result.surplus.isEmpty ? nil : result.surplus)
    }

    func run(source: SavedSource,
             progress: @escaping @Sendable (SyncProgress) -> Void) async -> SyncRun {
        var prepared: PreparedSync?
        do {
            let batch = try await prepare(source: source, progress: progress)
            prepared = batch
            return try await apply(prepared: batch, source: source, progress: progress)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return SyncRun(date: Date(), sourceName: source.targetName, sourceURL: source.sourceURL,
                           targetName: source.targetName, mode: source.mode, matched: 0,
                           totalTracks: prepared?.totalTracks ?? 0, playlistID: source.lastPlaylistID, misses: prepared?.misses ?? [],
                           failed: true, errorMessage: msg)
        }
    }

    private func resolveExistingID(_ source: SavedSource, targetName: String) async throws -> String? {
        // 1) Id cacheado del último sync: es la referencia fuerte y sobrevive a
        //    un cambio de nombre del destino.
        if let cached = source.lastPlaylistID {
            // A recent creation may not yet be visible. Never replace a durable
            // destination receipt with another POST based on a transient 404.
            guard try await client.playlistExists(cached) else { throw SyncIntegrityError.destinationUnavailable }
            return cached
        }
        // 2) Nombre actual (comparación tolerante a mayúsculas/acentos).
        if let byName = try await client.findPlaylist(named: targetName),
           try (source.managed != true || client.ownsPlaylist(byName)) {
            return byName
        }
        // 3) Nombre que tenía el destino en el último sync: cubre el caso de
        //    renombrar en la app cuando el id cacheado se ha perdido.
        if let previous = source.lastPlaylistName, previous != targetName,
           let byPrevious = try await client.findPlaylist(named: previous),
           try (source.managed != true || client.ownsPlaylist(byPrevious)) {
            return byPrevious
        }
        return nil
    }

    private func write(mode: SyncMode,
                       existing: String?,
                       targetName: String,
                       description: String,
                       songIDs: [String], source: SavedSource) async throws -> (playlistID: String, surplus: [SurplusTrack]) {
        // Sin destino conocido: crear es la única opción legítima.
        guard let existing else {
            let id = try await client.createPlaylist(name: targetName,
                                                     description: description,
                                                     songIDs: [])
            try checkpoint(source, id)
            // Replacement preserves order and duplicates, including on retry.
            if mode == .replace {
                try await client.editOwnPlaylist(id: id, name: targetName, description: description, songIDs: songIDs)
            } else {
                _ = try await appendAndDiff(id, songIDs: songIDs)
            }
            return (id, [])
        }

        switch mode {
        case .replace:
            if try client.ownsPlaylist(existing) {
                // Playlist gestionada por MusicSync → reemplazo real vía MusicKit.
                try await client.editOwnPlaylist(id: existing,
                                                 name: targetName,
                                                 description: description,
                                                 songIDs: songIDs)
                return (existing, [])
            }
            // Playlist NO creada por la app: Apple no permite reemplazar su
            // contenido. Hacemos lo máximo posible sin destruir nada:
            //   1. añadir lo que falte (dedupe),
            //   2. reportar las canciones sobrantes para limpieza manual.
            let surplus = try await appendAndDiff(existing, songIDs: songIDs)
            return (existing, surplus)

        case .append:
            let surplus = try await appendAndDiff(existing, songIDs: songIDs)
            return (existing, surplus)
        }
    }

    /// Añade lo que falta (con dedupe) y devuelve las canciones del destino que
    /// ya no están en el origen — la parte del "reemplazo" que la API no permite
    /// hacer y que el usuario puede completar a mano.
    private func appendAndDiff(_ playlistID: String, songIDs: [String]) async throws -> [SurplusTrack] {
        let existing = try await client.existingTracks(playlistID: playlistID)
        let already = Set(existing.map(\.catalogID))
        let fresh = SyncAlgorithms.fresh(songIDs, existing: already)
        if !fresh.isEmpty { try await client.addTracks(playlistID: playlistID, songIDs: fresh) }

        let wanted = Set(songIDs)
        return existing
            .filter { !wanted.contains($0.catalogID) }
            .map { SurplusTrack(title: $0.title, artist: $0.artist) }
    }
}


enum SyncSplitError: LocalizedError {
    case noSongsMatched
    var errorDescription: String? {
        "Ninguna canción encontrada en tu catálogo."
    }
}
