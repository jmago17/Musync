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
/// Reuses the exact replace/append/dedupe semantics of the original CLI.
struct Syncer: Sendable {
    let client = AppleMusicClient()

    func run(source: SavedSource,
             progress: @escaping @Sendable (SyncProgress) -> Void) async -> SyncRun {
        var p = SyncProgress()
        progress(p)

        do {
            let storefront = try await client.userStorefront()
            let src = try await client.fetchSourcePlaylist(url: source.sourceURL)
            let targetName = source.targetName.isEmpty ? src.title : source.targetName

            // Match every track in the user's storefront.
            var songIDs: [String] = []
            var misses: [MissTrack] = []
            let total = src.tracks.count
            for (i, t) in src.tracks.enumerated() {
                if let song = try await client.match(t, storefront: storefront) {
                    songIDs.append(song.id)
                } else {
                    misses.append(MissTrack(title: t.title, artist: t.artist, isrc: t.isrc, srcID: t.srcID))
                }
                p.phase = .matching(done: i + 1, total: total)
                p.matched = songIDs.count
                progress(p)
            }

            guard !songIDs.isEmpty else {
                return SyncRun(date: Date(), sourceName: targetName, sourceURL: source.sourceURL,
                               targetName: targetName, mode: source.mode, matched: 0,
                               totalTracks: total, playlistID: source.lastPlaylistID,
                               misses: misses, failed: true,
                               errorMessage: "Ninguna canción encontrada en tu catálogo.")
            }

            p.phase = .writing
            progress(p)

            let description = "Mirror de \(source.sourceURL) · MusicSync"
            let existing = try await resolveExistingID(source, targetName: targetName)
            let result = try await write(mode: source.mode,
                                         existing: existing,
                                         targetName: targetName,
                                         description: description,
                                         songIDs: songIDs)

            p.phase = .done
            progress(p)

            return SyncRun(date: Date(), sourceName: targetName, sourceURL: source.sourceURL,
                           targetName: targetName, mode: source.mode, matched: songIDs.count,
                           totalTracks: total, playlistID: result.playlistID, misses: misses,
                           surplus: result.surplus.isEmpty ? nil : result.surplus)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return SyncRun(date: Date(), sourceName: source.targetName, sourceURL: source.sourceURL,
                           targetName: source.targetName, mode: source.mode, matched: 0,
                           totalTracks: 0, playlistID: source.lastPlaylistID, misses: [],
                           failed: true, errorMessage: msg)
        }
    }

    private func resolveExistingID(_ source: SavedSource, targetName: String) async throws -> String? {
        // 1) Id cacheado del último sync: es la referencia fuerte y sobrevive a
        //    un cambio de nombre del destino.
        if let cached = source.lastPlaylistID, try await client.playlistExists(cached) {
            return cached
        }
        // 2) Nombre actual (comparación tolerante a mayúsculas/acentos).
        if let byName = try await client.findPlaylist(named: targetName) {
            return byName
        }
        // 3) Nombre que tenía el destino en el último sync: cubre el caso de
        //    renombrar en la app cuando el id cacheado se ha perdido.
        if let previous = source.lastPlaylistName, previous != targetName,
           let byPrevious = try await client.findPlaylist(named: previous) {
            return byPrevious
        }
        return nil
    }

    private func write(mode: SyncMode,
                       existing: String?,
                       targetName: String,
                       description: String,
                       songIDs: [String]) async throws -> (playlistID: String, surplus: [SurplusTrack]) {
        // Sin destino conocido: crear es la única opción legítima.
        guard let existing else {
            let id = try await client.createPlaylist(name: targetName,
                                                     description: description,
                                                     songIDs: songIDs)
            return (id, [])
        }

        switch mode {
        case .replace:
            if CreatedPlaylists.contains(existing) {
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
        let fresh = songIDs.filter { !already.contains($0) }
        if !fresh.isEmpty { try await client.addTracks(playlistID: playlistID, songIDs: fresh) }

        let wanted = Set(songIDs)
        return existing
            .filter { !wanted.contains($0.catalogID) }
            .map { SurplusTrack(title: $0.title, artist: $0.artist) }
    }
}
