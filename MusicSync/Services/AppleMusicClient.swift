import Foundation
import MusicKit

/// Thin client over the Apple Music API using `MusicDataRequest`, which injects
/// the developer token and (for `/me/...` routes) the user token automatically.
///
/// Mirrors the endpoints of the original `apple-music-sync` Python CLI, but with
/// framework-managed tokens — no scraped JWT, no pasted media-user-token.
struct AppleMusicClient: Sendable {

    static let host = "https://api.music.apple.com"

    enum ClientError: LocalizedError {
        case badURL(String)
        case http(Int, String)
        case decode(String)
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .badURL(let s):     return "URL inválida: \(s)"
            case .http(let c, let m): return "Apple Music API \(c): \(m)"
            case .decode(let m):     return "Respuesta inesperada: \(m)"
            case .notAuthorized:     return "Autoriza el acceso a Apple Music primero."
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
        } catch let error as MusicDataRequest.Error {
            let msg = [error.title, error.detailText].compactMap { $0 }.joined(separator: " — ")
            throw ClientError.http(error.status, msg.isEmpty ? error.localizedDescription : msg)
        }
    }

    private func getJSON<T: Decodable>(_ type: T.Type,
                                       path: String,
                                       query: [URLQueryItem]? = nil) async throws -> T {
        let data = try await rawData(method: "GET", path: path, query: query)
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
        let r = try await getJSON(DataArray<StorefrontAttrs>.self, path: "/v1/me/storefront")
        guard let id = r.data.first?.id else { throw ClientError.decode("storefront vacío") }
        return id
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
        while let path = nextPath {
            let page = try await getJSON(TracksPage.self, path: path, query: firstQuery)
            firstQuery = nil
            for t in page.data {
                guard let a = t.attributes else { continue }
                tracks.append(SourceTrack(title: a.name ?? "",
                                          artist: a.artistName ?? "",
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
        if let song = try? await songByID(track.srcID, storefront: storefront) {
            return song
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
        let ta = artist.lowercased(), tt = title.lowercased()
        if let exact = hits.first(where: { $0.artist.lowercased() == ta && $0.title.lowercased() == tt }) {
            return exact
        }
        if let byArtist = hits.first(where: { $0.artist.lowercased() == ta }) { return byArtist }
        return hits.first
    }

    // MARK: Library playlists

    func libraryPlaylists() async throws -> [(id: String, name: String)] {
        var out: [(String, String)] = []
        var path: String? = "/v1/me/library/playlists"
        var query: [URLQueryItem]? = [URLQueryItem(name: "limit", value: "100")]
        while let p = path {
            let page = try await getJSON(DataArray<NamedAttrs>.self, path: p, query: query)
            query = nil
            out.append(contentsOf: page.data.map { ($0.id, $0.attributes?.name ?? "") })
            path = page.next
        }
        return out
    }

    func findPlaylist(named name: String) async throws -> String? {
        try await libraryPlaylists().first(where: { $0.name == name })?.id
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
        let data = try await rawData(method: "POST",
                                     path: "/v1/me/library/playlists",
                                     body: try JSONEncoder().encode(body))
        let resp = try decode(DataArray<EmptyAttrs>.self, data, context: "POST /v1/me/library/playlists")
        guard let pid = resp.data.first?.id else { throw ClientError.decode("sin id de playlist") }
        if !rest.isEmpty { try await addTracks(playlistID: pid, songIDs: rest) }
        return pid
    }

    func addTracks(playlistID: String, songIDs: [String]) async throws {
        for chunk in songIDs.chunked(50) {
            let body = TrackDataBody(data: chunk.map { .init(id: $0) })
            _ = try await rawData(method: "POST",
                                  path: "/v1/me/library/playlists/\(playlistID)/tracks",
                                  body: try JSONEncoder().encode(body))
        }
    }

    func deletePlaylist(_ id: String) async throws {
        _ = try await rawData(method: "DELETE", path: "/v1/me/library/playlists/\(id)")
    }

    /// Catalog ids already present in a library playlist, for dedupe on append.
    func existingCatalogIDs(playlistID: String) async throws -> Set<String> {
        var ids = Set<String>()
        var path: String? = "/v1/me/library/playlists/\(playlistID)/tracks"
        var query: [URLQueryItem]? = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "include", value: "catalog"),
        ]
        while let p = path {
            do {
                let page = try await getJSON(LibraryTracksPage.self, path: p, query: query)
                query = nil
                for t in page.data {
                    for c in t.relationships?.catalog?.data ?? [] { ids.insert(c.id) }
                }
                path = page.next
            } catch ClientError.http(let code, _) where code == 404 {
                return ids
            }
        }
        return ids
    }
}

// MARK: - JSON shapes

private struct DataArray<A: Decodable>: Decodable {
    let data: [Resource<A>]
    let next: String?
}
private struct Resource<A: Decodable>: Decodable {
    let id: String
    let attributes: A?
}
private struct StorefrontAttrs: Decodable {}
private struct EmptyAttrs: Decodable {}
private struct NamedAttrs: Decodable { let name: String? }

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
                           artworkURL: a.artwork?.url)
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
    struct Item: Decodable { let relationships: Rel? }
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

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
