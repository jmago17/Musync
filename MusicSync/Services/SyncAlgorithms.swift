import Foundation

protocol MusicSyncClient: Sendable {
    func userStorefront() async throws -> String
    func fetchSourcePlaylist(url: String) async throws -> SourcePlaylist
    func equivalents(ids: [String], storefront: String) async throws -> [String: CatalogSong]
    func match(_ track: SourceTrack, storefront: String) async throws -> CatalogSong?
    func playlistExists(_ id: String) async throws -> Bool
    func findPlaylist(named name: String) async throws -> String?
    func createPlaylist(name: String, description: String, songIDs: [String]) async throws -> String
    func editOwnPlaylist(id: String, name: String, description: String, songIDs: [String]) async throws
    func addTracks(playlistID: String, songIDs: [String]) async throws
    func existingTracks(playlistID: String) async throws -> [(catalogID: String, title: String, artist: String)]
    func ownsPlaylist(_ id: String) throws -> Bool
}

enum SyncIntegrityError: LocalizedError {
    case incompleteCatalog, incompleteSource, paginationLoop, ambiguousDestination, stalePreparation, busy, uncertainWrite, uncertainCreation, destinationUnavailable
    var errorDescription: String? {
        switch self {
        case .incompleteCatalog: return "El catálogo no devolvió todas las canciones. No se ha reemplazado la playlist."
        case .incompleteSource: return "El origen contiene canciones sin resolver. No se puede reemplazar el destino con un resultado parcial."
        case .paginationLoop: return "La paginación de Apple Music es inconsistente. Sincronización cancelada."
        case .ambiguousDestination: return "Hay varias playlists con ese nombre. Selecciona el destino por su identificador."
        case .stalePreparation: return "La configuración o región cambió desde la preparación. Vuelve a obtener las canciones."
        case .uncertainCreation: return "No se pudo confirmar la creación anterior. Comprueba la biblioteca y selecciona explícitamente el destino existente antes de volver a sincronizar."
        case .uncertainWrite: return "Una escritura anterior no está confirmada. Espera a que la biblioteca se actualice y vuelve a intentarlo; no se reenviarán canciones a ciegas."
        case .destinationUnavailable: return "El destino guardado no está disponible. Espera a que la biblioteca se actualice o selecciona otro destino; no se creará una copia automáticamente."
        case .busy: return "Hay otra operación de MusicSync en curso. Inténtalo cuando termine."
        }
    }
}

enum SyncAlgorithms {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func strictMatch(_ hits: [CatalogSong], title: String, artist: String) -> CatalogSong? {
        let title = normalized(title), artist = normalized(artist)
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        let exact = hits.filter { normalized($0.title) == title && normalized($0.artist) == artist }
        // Several releases of the same recording are fine only with a common ISRC.
        guard let first = exact.first else { return nil }
        if exact.count == 1 { return first }
        guard let isrc = first.isrc, !isrc.isEmpty,
              exact.allSatisfy({ $0.isrc == isrc }) else { return nil }
        return first
    }

    static func ordered<T>(_ ids: [String], resources: [T], id: (T) -> String) throws -> [T] {
        var byID: [String: T] = [:]
        for item in resources { byID[id(item)] = item }
        return try ids.map {
            guard let item = byID[$0] else { throw SyncIntegrityError.incompleteCatalog }
            return item
        }
    }

    static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    static func fresh(_ ids: [String], existing: Set<String>) -> [String] {
        unique(ids).filter { !existing.contains($0) }
    }
}

/// Apple's documented filter[equivalents] response preserves source IDs in meta,
/// not in data order. Never pair arrays by index.
struct EquivalentSongsResponse: Decodable {
    struct Resource: Decodable {
        let id: String
        let attributes: Attributes?
    }
    struct Attributes: Decodable {
        let name: String
        let artistName: String
        let isrc: String?
    }
    struct Reference: Decodable { let id: String }
    struct Meta: Decodable {
        struct Filters: Decodable { let equivalents: [String: [Reference]]? }
        let filters: Filters?
    }
    let data: [Resource]
    let meta: Meta?
    let next: String?

    func matches(requested: [String]) throws -> [String: CatalogSong] {
        guard next == nil else { throw SyncIntegrityError.incompleteCatalog }
        var resources: [String: CatalogSong] = [:]
        for resource in data {
            guard let a = resource.attributes else { throw SyncIntegrityError.incompleteCatalog }
            resources[resource.id] = CatalogSong(id: resource.id, title: a.name, artist: a.artistName, artworkURL: nil, isrc: a.isrc)
        }
        guard let mappings = meta?.filters?.equivalents else {
            if data.isEmpty { return [:] }
            throw SyncIntegrityError.incompleteCatalog
        }
        var matches: [String: CatalogSong] = [:]
        for source in requested {
            guard let refs = mappings[source], let first = refs.first else { continue }
            guard let song = resources[first.id] else { throw SyncIntegrityError.incompleteCatalog }
            matches[source] = song
        }
        return matches
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// Persist the intent before sending a non-idempotent POST. An ambiguous failure
/// may be retried only after a complete read confirms every pending track.
struct PlaylistAppender {
    let store: SyncDiskStore
    func append(playlistID: String, ids: [String],
                existingIDs: @Sendable () async throws -> Set<String>,
                write: @Sendable ([String]) async throws -> Void,
                wasRejected: @Sendable (Error) -> Bool = { _ in false }) async throws {
        try Task.checkCancellation()
        let existing = try await existingIDs()
        if let pending = try store.read().pendingAppends[playlistID] {
            guard Set(pending).isSubset(of: existing) else { throw SyncIntegrityError.uncertainWrite }
            try store.update { $0.pendingAppends.removeValue(forKey: playlistID) }
        }
        var outstanding: [String] = []
        for chunk in SyncAlgorithms.fresh(ids, existing: existing).chunked(50) {
            try Task.checkCancellation()
            let previous = outstanding
            outstanding.append(contentsOf: chunk)
            try store.update { $0.pendingAppends[playlistID] = outstanding }
            do { try Task.checkCancellation() }
            catch {
                try restorePending(previous, playlistID: playlistID)
                throw error
            }
            do { try await write(chunk) }
            catch {
                if wasRejected(error) { try restorePending(previous, playlistID: playlistID) }
                throw error
            }
            // Keep acknowledged writes until a later library read confirms visibility.
        }
    }
    private func restorePending(_ ids: [String], playlistID: String) throws {
        try store.update { state in
            if ids.isEmpty { state.pendingAppends.removeValue(forKey: playlistID) }
            else { state.pendingAppends[playlistID] = ids }
        }
    }
}

struct PageCursor {
    private var visited = Set<String>()
    mutating func visit(_ path: String) throws {
        guard visited.insert(path).inserted else { throw SyncIntegrityError.paginationLoop }
    }
}

struct PlaylistCreator {
    let store: SyncDiskStore
    func create(name: String, description: String,
                request: @Sendable () async throws -> String,
                wasRejected: @Sendable (Error) -> Bool) async throws -> String {
        try Task.checkCancellation()
        let key = name + "\n" + description
        let completed: String? = try store.update { state in
            if let id = state.completedCreations[key] { return id }
            guard !state.pendingCreations.contains(key) else { throw SyncIntegrityError.uncertainCreation }
            state.pendingCreations.insert(key)
            return nil
        }
        if let completed { return completed }
        let id: String
        do { id = try await request() }
        catch {
            // A definitive client rejection can be retried. A lost response or
            // server error cannot: the playlist might already exist.
            if wasRejected(error) { try store.update { $0.pendingCreations.remove(key) } }
            throw error
        }
        try store.update {
            $0.createdPlaylistIDs.insert(id)
            $0.completedCreations[key] = id
            $0.pendingCreations.remove(key)
        }
        return id
    }
}

enum ReadRetry {
    static func data(request: @Sendable () async throws -> Data,
                     status: @Sendable (Error) -> Int?,
                     sleep: @Sendable (Int) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) async throws -> Data {
        for attempt in 0...2 {
            try Task.checkCancellation()
            do { return try await request() }
            catch {
                guard let code = status(error), attempt < 2, code == 429 || (500...599).contains(code) else { throw error }
                try await sleep(1 << attempt)
            }
        }
        preconditionFailure("Unreachable retry state")
    }
}
