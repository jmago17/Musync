import Foundation
import MusicKit

/// Service for interacting with MusicKit API
@MainActor
final class MusicKitService: ObservableObject {
    static let shared = MusicKitService()

    @Published private(set) var authorizationStatus: MusicAuthorization.Status = .notDetermined
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var hasSubscription: Bool = false

    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    /// Requests MusicKit authorization from the user
    func requestAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()
        authorizationStatus = status
        isAuthorized = status == .authorized

        if isAuthorized {
            await checkSubscriptionStatus()
        }

        return isAuthorized
    }

    /// Checks the current authorization status
    func checkAuthorizationStatus() async {
        authorizationStatus = MusicAuthorization.currentStatus
        isAuthorized = authorizationStatus == .authorized

        if isAuthorized {
            await checkSubscriptionStatus()
        }
    }

    /// Checks if the user has an Apple Music subscription
    private func checkSubscriptionStatus() async {
        do {
            let subscription = try await MusicSubscription.current
            hasSubscription = subscription.canPlayCatalogContent
        } catch {
            hasSubscription = false
        }
    }

    // MARK: - Playlist Fetching

    /// Fetches a playlist from a specific storefront
    func fetchPlaylist(
        id: String,
        storefront: String = "es"
    ) async throws -> Playlist {
        guard isAuthorized else {
            throw MusicKitError.notAuthorized
        }

        var request = MusicCatalogResourceRequest<Playlist>(
            matching: \.id,
            equalTo: MusicItemID(id)
        )
        request.properties = [.tracks]

        // Set the storefront for the request
        let response = try await request.response()

        guard let playlist = response.items.first else {
            throw MusicKitError.playlistNotFound
        }

        return playlist
    }

    /// Fetches songs from a playlist with full details
    func fetchPlaylistSongs(
        playlistID: String,
        storefront: String = "es"
    ) async throws -> [Song] {
        let playlist = try await fetchPlaylist(id: playlistID, storefront: storefront)

        guard let tracks = playlist.tracks else {
            throw MusicKitError.noTracksInPlaylist
        }

        // Convert MusicItemCollection<Track> to [Song]
        var songs: [Song] = []
        for track in tracks {
            if case .song(let song) = track {
                songs.append(song)
            }
        }

        return songs
    }

    // MARK: - Song Search

    /// Searches for a song by ISRC in a specific storefront
    func searchSongByISRC(
        isrc: String,
        storefront: String = "us"
    ) async throws -> Song? {
        guard isAuthorized else {
            throw MusicKitError.notAuthorized
        }

        // Use the ISRC to search
        var request = MusicCatalogSearchRequest(
            term: isrc,
            types: [Song.self]
        )
        request.limit = 25

        let response = try await request.response()

        // Find the song with matching ISRC
        for song in response.songs {
            if song.isrc == isrc {
                return song
            }
        }

        return nil
    }

    /// Searches for a song by title and artist
    func searchSongByTitleArtist(
        title: String,
        artist: String,
        storefront: String = "us"
    ) async throws -> Song? {
        guard isAuthorized else {
            throw MusicKitError.notAuthorized
        }

        // Combine title and artist for search
        let searchTerm = "\(title) \(artist)"

        var request = MusicCatalogSearchRequest(
            term: searchTerm,
            types: [Song.self]
        )
        request.limit = 10

        let response = try await request.response()

        // Try to find a close match
        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespaces)
        let normalizedArtist = artist.lowercased().trimmingCharacters(in: .whitespaces)

        for song in response.songs {
            let songTitle = song.title.lowercased().trimmingCharacters(in: .whitespaces)
            let songArtist = song.artistName.lowercased().trimmingCharacters(in: .whitespaces)

            // Check for reasonable match
            if songTitle.contains(normalizedTitle) || normalizedTitle.contains(songTitle) {
                if songArtist.contains(normalizedArtist) || normalizedArtist.contains(songArtist) {
                    return song
                }
            }
        }

        // Return first result as fallback if available
        return response.songs.first
    }

    // MARK: - User Library

    /// Gets the user's library playlists
    func fetchUserPlaylists() async throws -> [Playlist] {
        guard isAuthorized else {
            throw MusicKitError.notAuthorized
        }

        let request = MusicLibraryRequest<Playlist>()
        let response = try await request.response()

        return Array(response.items)
    }

    /// Creates a new playlist in the user's library
    func createPlaylist(name: String, description: String? = nil) async throws -> Playlist {
        guard isAuthorized, hasSubscription else {
            throw MusicKitError.noSubscription
        }

        let library = MusicLibrary.shared

        let playlist = try await library.createPlaylist(
            name: name,
            description: description
        )

        return playlist
    }

    /// Adds songs to a playlist
    func addSongsToPlaylist(
        _ songs: [Song],
        playlist: Playlist
    ) async throws {
        guard isAuthorized, hasSubscription else {
            throw MusicKitError.noSubscription
        }

        let library = MusicLibrary.shared

        try await library.add(songs, to: playlist)
    }

    /// Adds songs to the user's library
    func addSongsToLibrary(_ songs: [Song]) async throws {
        guard isAuthorized, hasSubscription else {
            throw MusicKitError.noSubscription
        }

        let library = MusicLibrary.shared

        try await library.add(songs)
    }

    // MARK: - Error Types

    enum MusicKitError: LocalizedError {
        case notAuthorized
        case noSubscription
        case playlistNotFound
        case noTracksInPlaylist
        case songNotFound
        case rateLimited
        case networkError(Error)
        case unknown(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Se requiere autorización de Apple Music"
            case .noSubscription:
                return "Se requiere una suscripción a Apple Music"
            case .playlistNotFound:
                return "No se encontró la playlist"
            case .noTracksInPlaylist:
                return "La playlist no contiene canciones"
            case .songNotFound:
                return "No se encontró la canción"
            case .rateLimited:
                return "Demasiadas solicitudes. Intenta de nuevo en unos segundos"
            case .networkError(let error):
                return "Error de red: \(error.localizedDescription)"
            case .unknown(let error):
                return "Error desconocido: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Playlist Info

extension MusicKitService {
    struct PlaylistInfo {
        let id: String
        let name: String
        let curatorName: String?
        let artworkURL: URL?
        let songCount: Int
        let description: String?

        init(from playlist: Playlist) {
            self.id = playlist.id.rawValue
            self.name = playlist.name
            self.curatorName = playlist.curatorName
            self.artworkURL = playlist.artwork?.url(width: 300, height: 300)
            self.songCount = playlist.tracks?.count ?? 0
            self.description = playlist.standardDescription
        }
    }

    /// Gets basic info about a playlist without fetching all tracks
    func getPlaylistInfo(
        id: String,
        storefront: String = "es"
    ) async throws -> PlaylistInfo {
        let playlist = try await fetchPlaylist(id: id, storefront: storefront)
        return PlaylistInfo(from: playlist)
    }
}
