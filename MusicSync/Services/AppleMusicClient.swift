import Foundation
import MusicKit

/// Thin client over the Apple Music API using `MusicDataRequest`, which injects
/// the developer token and (for `/me/...` routes) the user token automatically.
///
/// Mirrors the endpoints of the original `apple-music-sync` Python CLI, but with
/// framework-managed tokens — no scraped JWT, no pasted media-user-token.
struct AppleMusicClient: MusicSyncClient {

    static let host = "https://api.music.apple.com"

    enum ClientError: LocalizedError {
        case badURL(String)
        case http(Int, String)
        case decode(String)
        case notAuthorized
        case notEditable(String)

        var errorDescription: String? {
            switch self {
            case .badURL(let s):     return "URL inválida: \(s)"
            case .http(let c, let m): return "Apple Music API \(c): \(m)"
            case .decode(let m):     return "Respuesta inesperada: \(m)"
            case .notAuthorized:     return "Autoriza el acceso a Apple Music primero."
            case .notEditable(let m): return m
            }
        }
    }

    // MARK: Authorization

    static var authStatus: MusicAuthorization.Status { MusicAuthorization.currentStatus }

    @discardableResult
    static func requestAuthorization() async -> MusicAuthorization.Status {
        await MusicAuthorization.request()
    }

    // MARK: Low-level request

    private func rawData(method: String,
                         path: String,
                         query: [URLQueryItem]? = nil,
                         body: Data? = nil) async throws -> Data {
        try Task.checkCancellation()
        guard path.hasPrefix("/v1/") else { throw ClientError.badURL(path) }
        guard var comps = URLComponents(string: Self.host + path) else {
            throw ClientError.badURL(path)
        }
        // Preserva la query que ya venga en `path` (p.ej. el `next` de paginación)
        // y añade los items extra, en vez de sobrescribirla.
        if let query { comps.queryItems = (comps.queryItems ?? []) + query }
        guard let url = comps.url else { throw ClientError.badURL(path) }

        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let dataRequest = MusicDataRequest(urlRequest: req)
        do {
            let response = try await dataRequest.response()
            return response.data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MusicDataRequest.Error {
            let msg = [error.title, error.detailText].compactMap { $0 }.joined(separator: " — ")
            throw ClientError.http(error.status, "\(method) \(path): \(msg.isEmpty ? error.localizedDescription : msg)")
        } catch {
            throw ClientError.decode(Self.diagnostic(error, context: "\(method) \(path)"))
        }
    }

    private static func diagnostic(_ error: Error, context: String) -> String {
        let ns = error as NSError
        var text = "\(context): \(ns.localizedDescription) [\(ns.domain), código \(ns.code)]"
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " — \(underlying.localizedDescription) [\(underlying.domain), código \(underlying.code)]"
        }
        return text
    }

    private func getJSON<T: Decodable>(_ type: T.Type,
                                       path: String,
                                       query: [URLQueryItem]? = nil) async throws -> T {
        let data = try await ReadRetry.data(request: { try await rawData(method: "GET", path: path, query: query) }, status: { error in
            if case ClientError.http(let status, _) = error { return status }
            return nil
        })
        return try decode(type, data, context: path)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data, context: String = "") throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binario>"
            throw ClientError.decode("\(context) → \(preview)")
        }
    }

    // MARK: Storefront

    func userStorefront() async throws -> String {
        do {
            return try await MusicDataRequest.currentCountryCode.lowercased()
        } catch {
            throw ClientError.decode(Self.diagnostic(error, context: "Región de la cuenta Apple Music"))
        }
    }

    // MARK: Source playlist (any storefront)

    /// Parse `music.apple.com/<sf>/playlist/<slug>/<pl.id>` → storefront + id.
    static func parseSourceURL(_ url: String) -> (storefront: String, id: String)? {
        guard let comps = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let parts = comps.path.split(separator: "/").map(String.init)
        // e.g. ["es", "playlist", "rock-espanol", "pl.1075929..."]
        guard let plIdx = parts.firstIndex(of: "playlist"),
              plIdx + 1 < parts.count else { return nil }
        let storefront = plIdx > 0 ? parts[plIdx - 1] : "us"
        let id = parts.last ?? ""
        guard id.hasPrefix("pl.") else { return nil }
        return (storefront, id)
    }

    func fetchSourcePlaylist(url: String) async throws -> SourcePlaylist {
        guard let (sf, id) = Self.parseSourceURL(url) else {
            throw ClientError.badURL("no es una URL de playlist de Apple Music")
        }
        // Header (name)
        let header = try await getJSON(DataArray<NamedAttrs>.self,
                                       path: "/v1/catalog/\(sf)/playlists/\(id)")
        let title = header.data.first?.attributes?.name ?? "Playlist"

        // Tracks (paginated)
        var tracks: [SourceTrack] = []
        var nextPath: String? = "/v1/catalog/\(sf)/playlists/\(id)/tracks"
        var firstQuery: [URLQueryItem]? = [URLQueryItem(name: "limit", value: "100")]
        var cursor = PageCursor()
        while let path = nextPath {
            try cursor.visit(path)
            let page = try await getJSON(TracksPage.self, path: path, query: firstQuery)
            firstQuery = nil
            for t in page.data {
                guard t.type == "songs", let a = t.attributes, let name = a.name, let artist = a.artistName else { throw SyncIntegrityError.incompleteSource }
                tracks.append(SourceTrack(title: name,
                                          artist: artist,
                                          isrc: a.isrc,
                                          srcID: t.id))
            }
            nextPath = page.next
        }
        return SourcePlaylist(title: title, storefront: sf, tracks: tracks)
    }

    // MARK: Catalog matching in the user's storefront

    /// Best-effort match of a source track into `storefront`. Prefers ISRC.
    func match(_ track: SourceTrack, storefront: String) async throws -> CatalogSong? {
        // 1) ISRC — the robust cross-storefront key.
        if let isrc = track.isrc, !isrc.isEmpty {
            if let song = try await songsByISRC(isrc, storefront: storefront).first {
                return song
            }
        }
        // 2) Direct id lookup (Apple often shares ids across storefronts).
        do {
            if let song = try await songByID(track.srcID, storefront: storefront) { return song }
        } catch ClientError.http(let code, _) where code == 404 {
            // Only a missing resource permits a search fallback.
        }
        // 3) Search fallback, ranked by artist/title.
        let term = "\(track.title) \(track.artist)".trimmingCharacters(in: .whitespaces)
        let hits = try await searchSongs(term: term, storefront: storefront, limit: 10)
        return rank(hits, title: track.title, artist: track.artist)
    }

    func songsByISRC(_ isrc: String, storefront: String) async throws -> [CatalogSong] {
        let r = try await getJSON(DataArray<SongAttrs>.self,
                                  path: "/v1/catalog/\(storefront)/songs",
                                  query: [URLQueryItem(name: "filter[isrc]", value: isrc)])
        return r.data.compactMap(\.asCatalogSong)
    }

    func songByID(_ id: String, storefront: String) async throws -> CatalogSong? {
        let r = try await getJSON(DataArray<SongAttrs>.self,
                                  path: "/v1/catalog/\(storefront)/songs/\(id)")
        return r.data.first?.asCatalogSong
    }

    func searchSongs(term: String, storefront: String, limit: Int = 10) async throws -> [CatalogSong] {
        let r = try await getJSON(SearchResponse.self,
                                  path: "/v1/catalog/\(storefront)/search",
                                  query: [
                                    URLQueryItem(name: "term", value: term),
                                    URLQueryItem(name: "types", value: "songs"),
                                    URLQueryItem(name: "limit", value: String(limit)),
                                  ])
        return (r.results.songs?.data ?? []).compactMap(\.asCatalogSong)
    }

    private func rank(_ hits: [CatalogSong], title: String, artist: String) -> CatalogSong? {
        SyncAlgorithms.strictMatch(hits, title: title, artist: artist)
    }

    func equivalents(ids: [String], storefront: String) async throws -> [String: CatalogSong] {
        var matches: [String: CatalogSong] = [:]
        if #available(iOS 27, *) {
            for chunk in ids.chunked(100) {
                try Task.checkCancellation()
                var request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: chunk.map { MusicItemID($0) })
                request.options = [.findEquivalents]
                request.limit = chunk.count
                let response = try await request.response()
                guard !response.items.hasNextBatch else { throw SyncIntegrityError.incompleteCatalog }
                for id in chunk {
                    if let song = response.item(for: MusicItemID(id)) { matches[id] = Self.catalogSong(song) }
                }
            }
        } else {
            for chunk in ids.chunked(100) {
                let response = try await getJSON(EquivalentSongsResponse.self,
                    path: "/v1/catalog/\(storefront)/songs",
                    query: [URLQueryItem(name: "filter[equivalents]", value: chunk.joined(separator: ","))])
                matches.merge(try response.matches(requested: chunk)) { _, new in new }
            }
        }
        return matches
    }

    private static func catalogSong(_ song: Song) -> CatalogSong {
        CatalogSong(id: song.id.rawValue, title: song.title, artist: song.artistName, artworkURL: nil, isrc: song.isrc)
    }

    func ownsPlaylist(_ id: String) throws -> Bool { try CreatedPlaylists.contains(id) }

    // MARK: Library playlists

    func libraryPlaylists() async throws -> [(id: String, name: String)] {
        try await libraryPlaylistsDetailed().map { ($0.id, $0.name) }
    }

    /// Library listing uses native MusicKit; local provenance is only an edit
    /// eligibility hint, and the framework remains authoritative on mutation.
    func libraryPlaylistsDetailed() async throws -> [LibraryPlaylist] {
        // Use MusicKit's native library API. Unlike a hand-built `/v1/me/...`
        // MusicDataRequest, this is the documented path for the library granted
        // by MusicAuthorization and gives us a meaningful framework error.
        var request = MusicLibraryRequest<Playlist>()
        request.limit = 100
        var batch = try await request.response().items
        var playlists = Array(batch)
        while batch.hasNextBatch {
            guard let next = try await batch.nextBatch(limit: 100) else { throw SyncIntegrityError.incompleteCatalog }
            playlists.append(contentsOf: next)
            batch = next
        }

        let owned = try CreatedPlaylists.ids
        return playlists.map {
            LibraryPlaylist(id: $0.id.rawValue,
                            name: $0.name,
                            trackCount: $0.tracks?.count,
                            canEdit: true,
                            isReplaceable: owned.contains($0.id.rawValue))
        }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Normaliza para comparar nombres: sin mayúsculas, sin acentos y con
    /// espacios colapsados. Evita crear duplicados por diferencias cosméticas.
    static func normalizedName(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                  locale: Locale(identifier: "es_ES"))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func findPlaylist(named name: String) async throws -> String? {
        let all = try await libraryPlaylists()
        let target = Self.normalizedName(name)
        guard !target.isEmpty else { return nil }
        let candidates = all.filter { Self.normalizedName($0.name) == target }
        guard candidates.count <= 1 else { throw SyncIntegrityError.ambiguousDestination }
        return candidates.first?.id
    }

    func playlistExists(_ id: String) async throws -> Bool {
        do {
            _ = try await rawData(method: "GET", path: "/v1/me/library/playlists/\(id)")
            return true
        } catch ClientError.http(let code, _) where code == 404 {
            return false
        }
    }

    func createPlaylist(name: String, description: String, songIDs: [String]) async throws -> String {
        let initial = Array(songIDs.prefix(100))
        let rest = Array(songIDs.dropFirst(100))
        let body = CreatePlaylistBody(
            attributes: .init(name: name, description: description),
            relationships: .init(tracks: .init(data: initial.map { .init(id: $0) })))
        let pid = try await PlaylistCreator(store: SourceStore.store).create(name: name, description: description, request: {
            let data = try await rawData(method: "POST", path: "/v1/me/library/playlists", body: try JSONEncoder().encode(body))
            let response = try decode(DataArray<EmptyAttrs>.self, data, context: "POST /v1/me/library/playlists")
            guard let id = response.data.first?.id else { throw ClientError.decode("sin id de playlist") }
            return id
        }, wasRejected: { Self.wasRejected($0) })
        if !rest.isEmpty { try await addTracks(playlistID: pid, songIDs: rest) }
        return pid
    }

    /// Renombra y/o reconstruye el contenido de una playlist **creada por esta
    /// app**, conservando su id. Usa MusicKit (`MusicLibrary.edit`) porque la
    /// Apple Music API REST **no tiene** endpoint de edición: solo POST para
    /// crear y POST /tracks para añadir al final.
    ///
    /// Lanza si la playlist la creó otra app (p. ej. la app Música): en ese caso
    /// Apple no permite editarla desde aquí por ninguna API pública.
    func editOwnPlaylist(id: String, name: String, description: String, songIDs: [String]) async throws {
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(id))
        guard let playlist = try await request.response().items.first else {
            throw ClientError.notEditable("La playlist todavía no está disponible en la biblioteca. Reintenta cuando termine de sincronizarse.")
        }
        var songs: [Song] = []
        for chunk in SyncAlgorithms.unique(songIDs).chunked(25) {
            let request = MusicCatalogResourceRequest<Song>(matching: \.id,
                                                           memberOf: chunk.map { MusicItemID($0) })
            var batch = try await request.response().items
            songs.append(contentsOf: batch)
            while batch.hasNextBatch {
                guard let next = try await batch.nextBatch(limit: 25) else { throw SyncIntegrityError.incompleteCatalog }
                songs.append(contentsOf: next)
                batch = next
            }
        }
        let ordered = try SyncAlgorithms.ordered(songIDs, resources: songs) { $0.id.rawValue }
        try Task.checkCancellation()
        _ = try await MusicLibrary.shared.edit(playlist, name: name, description: description, items: ordered)
        try SourceStore.store.update { $0.pendingAppends.removeValue(forKey: id) }
    }

    func addTracks(playlistID: String, songIDs: [String]) async throws {
        try await PlaylistAppender(store: SourceStore.store).append(playlistID: playlistID, ids: songIDs,
            existingIDs: { try await existingCatalogIDs(playlistID: playlistID) },
            write: { chunk in
                let body = TrackDataBody(data: chunk.map { SongRef(id: $0) })
                _ = try await rawData(method: "POST", path: "/v1/me/library/playlists/\(playlistID)/tracks",
                                      body: try JSONEncoder().encode(body))
            }, wasRejected: { Self.wasRejected($0) })
    }

    private static func wasRejected(_ error: Error) -> Bool {
        if case ClientError.http(let status, _) = error { return [400, 401, 403, 404, 405, 409, 422, 429].contains(status) }
        return false
    }

    /// Catalog ids already present in a library playlist, for dedupe on append.
    func existingCatalogIDs(playlistID: String) async throws -> Set<String> {
        Set(try await existingTracks(playlistID: playlistID).map(\.catalogID))
    }

    /// Pistas de una playlist de biblioteca con su id de catálogo y metadatos.
    /// Sirve para dedupe y para calcular sobrantes (canciones que ya no están
    /// en el origen) de forma legible para el usuario.
    func existingTracks(playlistID: String) async throws -> [(catalogID: String, title: String, artist: String)] {
        var out: [(String, String, String)] = []
        var path: String? = "/v1/me/library/playlists/\(playlistID)/tracks"
        var query: [URLQueryItem]? = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "include", value: "catalog"),
        ]
        var cursor = PageCursor()
        while let p = path {
            try cursor.visit(p)
            let page = try await getJSON(LibraryTracksPage.self, path: p, query: query)
            query = nil
            for t in page.data {
                guard let c = t.relationships?.catalog?.data.first else { throw SyncIntegrityError.incompleteCatalog }
                out.append((c.id, t.attributes?.name ?? "", t.attributes?.artistName ?? ""))
            }
            path = page.next
        }
        return out
    }
}

// MARK: - JSON shapes

private struct DataArray<A: Decodable>: Decodable {
    let data: [Resource<A>]
    let next: String?
}
private struct Resource<A: Decodable>: Decodable {
    let id: String
    let type: String?
    let attributes: A?
}
private struct StorefrontAttrs: Decodable {}
private struct EmptyAttrs: Decodable {}
private struct NamedAttrs: Decodable { let name: String? }
private struct PlaylistAttrs: Decodable {
    let name: String?
    let canEdit: Bool?
}

private struct SongAttrs: Decodable {
    let name: String?
    let artistName: String?
    let isrc: String?
    let artwork: Artwork?
    struct Artwork: Decodable { let url: String? }
}

private extension Resource where A == SongAttrs {
    var asCatalogSong: CatalogSong? {
        guard let a = attributes else { return nil }
        return CatalogSong(id: id,
                           title: a.name ?? "",
                           artist: a.artistName ?? "",
                           artworkURL: a.artwork?.url, isrc: a.isrc)
    }
}

private struct TracksPage: Decodable {
    let data: [Resource<SongAttrs>]
    let next: String?
}

private struct SearchResponse: Decodable {
    let results: Results
    struct Results: Decodable { let songs: SongList? }
    struct SongList: Decodable { let data: [Resource<SongAttrs>] }
}

private struct LibraryTracksPage: Decodable {
    let data: [Item]
    let next: String?
    struct Item: Decodable {
        let attributes: Attrs?
        let relationships: Rel?
    }
    struct Attrs: Decodable {
        let name: String?
        let artistName: String?
    }
    struct Rel: Decodable { let catalog: CatalogRel? }
    struct CatalogRel: Decodable { let data: [IDOnly] }
    struct IDOnly: Decodable { let id: String }
}

// Request bodies
private struct CreatePlaylistBody: Encodable {
    let attributes: Attrs
    let relationships: Rel
    struct Attrs: Encodable { let name: String; let description: String }
    struct Rel: Encodable { let tracks: TrackData }
    struct TrackData: Encodable { let data: [SongRef] }
}
private struct TrackDataBody: Encodable { let data: [SongRef] }
private struct SongRef: Encodable {
    let id: String
    let type = "songs"
    init(id: String) { self.id = id }
}

extension Syncer {
    init() {
        self.init(client: AppleMusicClient(), checkpoint: { source, id in
            try SourceStore.checkpoint(source: source, playlistID: id)
        })
    }
}
