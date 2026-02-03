import Foundation
import SwiftUI
import MusicKit

/// ViewModel for the Sync screen
@MainActor
final class SyncViewModel: ObservableObject {
    // MARK: - Published Properties

    // Playlist Info
    @Published var playlistName: String = ""
    @Published var playlistArtworkURL: URL?
    @Published var totalSongCount: Int = 0
    @Published var sourceURL: String = ""

    // Sync State
    @Published var syncState: SyncState = .idle
    @Published var progress: Double = 0
    @Published var currentSong: String?
    @Published var songs: [SyncedSong] = []

    // User Playlists
    @Published var userPlaylists: [Playlist] = []
    @Published var selectedPlaylist: Playlist?
    @Published var newPlaylistName: String = ""
    @Published var createNewPlaylist: Bool = true

    // Error Handling
    @Published var errorMessage: String?
    @Published var showError: Bool = false

    // Statistics
    @Published var statistics: ISRCMatcher.MatchingStatistics?

    // Services
    private let musicKitService: MusicKitService
    private let isrcMatcher: ISRCMatcher
    private let dataController: DataController

    // Data
    private var playlistID: String = ""

    // MARK: - Sync State

    enum SyncState: Equatable {
        case idle
        case loading
        case scanning
        case ready
        case adding
        case completed
        case error

        var isInProgress: Bool {
            switch self {
            case .loading, .scanning, .adding:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Initialization

    init(
        musicKitService: MusicKitService = .shared,
        isrcMatcher: ISRCMatcher? = nil,
        dataController: DataController = .shared
    ) {
        self.musicKitService = musicKitService
        self.isrcMatcher = isrcMatcher ?? ISRCMatcher(musicKitService: musicKitService)
        self.dataController = dataController
    }

    /// Configures the view model with playlist data
    func configure(with data: PlaylistSyncData) {
        self.playlistID = data.playlistID
        self.playlistName = data.name
        self.playlistArtworkURL = data.artworkURL
        self.totalSongCount = data.songCount
        self.sourceURL = data.sourceURL
    }

    // MARK: - Scanning

    /// Starts the playlist scanning process
    func startScanning() async {
        guard !syncState.isInProgress else { return }

        syncState = .loading
        progress = 0
        songs = []
        errorMessage = nil

        do {
            // Fetch songs from the Spanish playlist
            let sourceSongs = try await musicKitService.fetchPlaylistSongs(
                playlistID: playlistID,
                storefront: "es"
            )

            totalSongCount = sourceSongs.count
            syncState = .scanning

            // Match songs to US storefront
            let matchedSongs = try await isrcMatcher.matchSongs(
                sourceSongs,
                fromStorefront: "es",
                toStorefront: "us"
            ) { [weak self] progress, currentSong in
                Task { @MainActor [weak self] in
                    self?.progress = progress
                    self?.currentSong = currentSong
                }
            }

            songs = matchedSongs
            statistics = ISRCMatcher.calculateStatistics(from: matchedSongs)
            syncState = .ready

            // Fetch user playlists for destination selection
            await fetchUserPlaylists()

        } catch {
            handleError(error)
            syncState = .error
        }
    }

    /// Fetches user's playlists for destination selection
    private func fetchUserPlaylists() async {
        do {
            userPlaylists = try await musicKitService.fetchUserPlaylists()
        } catch {
            // Non-critical error, user can still create a new playlist
            print("Failed to fetch user playlists: \(error)")
        }
    }

    // MARK: - Adding Songs

    /// Adds matched songs to the selected or new playlist
    func addSongsToPlaylist() async {
        guard syncState == .ready else { return }

        let matchedSongs = songs.filter { $0.isMatched }
        guard !matchedSongs.isEmpty else {
            showError(message: "No hay canciones disponibles para añadir")
            return
        }

        syncState = .adding
        progress = 0

        do {
            // Get or create destination playlist
            let destinationPlaylist: Playlist
            let destinationName: String

            if createNewPlaylist || selectedPlaylist == nil {
                let name = newPlaylistName.isEmpty ? "\(playlistName) (US)" : newPlaylistName
                destinationPlaylist = try await musicKitService.createPlaylist(
                    name: name,
                    description: "Sincronizado desde: \(playlistName)"
                )
                destinationName = name
            } else {
                destinationPlaylist = selectedPlaylist!
                destinationName = selectedPlaylist!.name
            }

            // Get MusicKit Song objects for matched songs
            var songsToAdd: [Song] = []

            for (index, syncedSong) in matchedSongs.enumerated() {
                if let songID = syncedSong.matchedSongID {
                    // Fetch the actual Song object
                    var request = MusicCatalogResourceRequest<Song>(
                        matching: \.id,
                        equalTo: songID
                    )
                    let response = try await request.response()

                    if let song = response.items.first {
                        songsToAdd.append(song)
                    }
                }

                progress = Double(index + 1) / Double(matchedSongs.count)
            }

            // Add songs to the playlist
            try await musicKitService.addSongsToPlaylist(songsToAdd, playlist: destinationPlaylist)

            // Save to history
            saveSyncHistory(destinationPlaylistName: destinationName)

            syncState = .completed

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

        } catch {
            handleError(error)
            syncState = .error
        }
    }

    // MARK: - History

    private func saveSyncHistory(destinationPlaylistName: String) {
        let history = SyncHistory.from(
            sourcePlaylistName: playlistName,
            sourcePlaylistURL: sourceURL,
            destinationPlaylistName: destinationPlaylistName,
            songs: songs
        )

        do {
            try dataController.addSyncHistory(history)
        } catch {
            print("Failed to save sync history: \(error)")
        }
    }

    // MARK: - Favorites

    /// Saves the current playlist as a favorite
    func saveAsFavorite() {
        do {
            try dataController.addFavorite(
                name: playlistName,
                spanishURL: sourceURL,
                artworkURL: playlistArtworkURL?.absoluteString,
                songCount: totalSongCount
            )

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } catch {
            showError(message: "No se pudo guardar como favorito")
        }
    }

    /// Checks if this playlist is already a favorite
    func isFavorite() -> Bool {
        do {
            return try dataController.isFavorite(url: sourceURL)
        } catch {
            return false
        }
    }

    // MARK: - Error Handling

    private func showError(message: String) {
        errorMessage = message
        showError = true

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if self.errorMessage == message {
                self.showError = false
            }
        }
    }

    private func handleError(_ error: Error) {
        if let musicKitError = error as? MusicKitService.MusicKitError {
            showError(message: musicKitError.localizedDescription)
        } else {
            showError(message: error.localizedDescription)
        }
    }

    // MARK: - Computed Properties

    /// Number of songs that were successfully matched
    var matchedCount: Int {
        songs.filter { $0.isMatched }.count
    }

    /// Songs that were not found in the US storefront
    var unmatchedSongs: [SyncedSong] {
        songs.filter { $0.matchStatus == .notFound }
    }

    /// Summary text for display
    var summaryText: String {
        "\(matchedCount)/\(songs.count) canciones disponibles"
    }

    /// Whether the add button should be enabled
    var canAddSongs: Bool {
        syncState == .ready && matchedCount > 0
    }
}
