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
            let playlistID = try await write(mode: source.mode,
                                             existing: existing,
                                             targetName: targetName,
                                             description: description,
                                             songIDs: songIDs)

            p.phase = .done
            progress(p)

            return SyncRun(date: Date(), sourceName: targetName, sourceURL: source.sourceURL,
                           targetName: targetName, mode: source.mode, matched: songIDs.count,
                           totalTracks: total, playlistID: playlistID, misses: misses)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return SyncRun(date: Date(), sourceName: source.targetName, sourceURL: source.sourceURL,
                           targetName: source.targetName, mode: source.mode, matched: 0,
                           totalTracks: 0, playlistID: source.lastPlaylistID, misses: [],
                           failed: true, errorMessage: msg)
        }
    }

    private func resolveExistingID(_ source: SavedSource, targetName: String) async throws -> String? {
        if let cached = source.lastPlaylistID, try await client.playlistExists(cached) {
            return cached
        }
        return try await client.findPlaylist(named: targetName)
    }

    private func write(mode: SyncMode,
                       existing: String?,
                       targetName: String,
                       description: String,
                       songIDs: [String]) async throws -> String {
        switch mode {
        case .replace:
            if let existing {
                do {
                    try await client.deletePlaylist(existing)
                } catch {
                    // Delete not allowed → fall back to append + dedupe (CLI behaviour).
                    return try await appendDedupe(existing, songIDs: songIDs)
                }
            }
            return try await client.createPlaylist(name: targetName, description: description, songIDs: songIDs)

        case .append:
            if let existing {
                return try await appendDedupe(existing, songIDs: songIDs)
            }
            return try await client.createPlaylist(name: targetName, description: description, songIDs: songIDs)
        }
    }

    private func appendDedupe(_ playlistID: String, songIDs: [String]) async throws -> String {
        let already = try await client.existingCatalogIDs(playlistID: playlistID)
        let fresh = songIDs.filter { !already.contains($0) }
        if !fresh.isEmpty { try await client.addTracks(playlistID: playlistID, songIDs: fresh) }
        return playlistID
    }
}
