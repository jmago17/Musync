import Foundation
import SwiftUI
import SwiftData
import MusicKit

/// ViewModel for the Home screen
@MainActor
final class HomeViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var playlistURL: String = ""
    @Published var validationState: URLValidationState = .empty
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false

    // Navigation
    @Published var navigateToSync: Bool = false
    @Published var playlistToSync: PlaylistSyncData?

    // Services
    private let musicKitService: MusicKitService
    private let networkMonitor: NetworkMonitor

    // MARK: - Initialization

    init(
        musicKitService: MusicKitService = .shared,
        networkMonitor: NetworkMonitor = .shared
    ) {
        self.musicKitService = musicKitService
        self.networkMonitor = networkMonitor
    }

    // MARK: - URL Validation State

    enum URLValidationState: Equatable {
        case empty
        case validating
        case valid(playlistID: String)
        case invalid(message: String)

        var isValid: Bool {
            switch self {
            case .valid: return true
            default: return false
            }
        }

        var message: String? {
            switch self {
            case .invalid(let message): return message
            default: return nil
            }
        }
    }

    // MARK: - URL Validation

    /// Validates the playlist URL as the user types
    func validateURL() {
        let trimmed = playlistURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            validationState = .empty
            return
        }

        validationState = .validating

        let result = PlaylistParser.validate(trimmed)

        switch result {
        case .valid(let playlistID, _, _):
            validationState = .valid(playlistID: playlistID)
        case .invalid(let reason):
            validationState = .invalid(message: reason.message)
        }
    }

    // MARK: - Fetch Playlist

    /// Fetches the playlist and prepares data for sync
    func fetchPlaylist() async {
        guard case .valid(let playlistID) = validationState else { return }

        // Check network connectivity
        guard networkMonitor.isConnected else {
            showError(message: "Sin conexión a internet")
            return
        }

        // Check MusicKit authorization
        guard musicKitService.isAuthorized else {
            showError(message: "Se requiere autorización de Apple Music")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let info = try await musicKitService.getPlaylistInfo(id: playlistID, storefront: "es")

            playlistToSync = PlaylistSyncData(
                playlistID: playlistID,
                name: info.name,
                artworkURL: info.artworkURL,
                songCount: info.songCount,
                sourceURL: playlistURL
            )

            navigateToSync = true
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    // MARK: - Error Handling

    private func showError(message: String) {
        errorMessage = message
        showError = true

        // Auto-dismiss after 5 seconds
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
            showError(message: "Error al cargar la playlist: \(error.localizedDescription)")
        }
    }

    // MARK: - Actions

    /// Clears the URL field
    func clearURL() {
        playlistURL = ""
        validationState = .empty
    }

    /// Pastes URL from clipboard
    func pasteFromClipboard() {
        if let clipboardString = UIPasteboard.general.string {
            playlistURL = clipboardString
            validateURL()
        }
    }

    /// Resets navigation state
    func resetNavigation() {
        navigateToSync = false
        playlistToSync = nil
    }
}

// MARK: - Playlist Sync Data

struct PlaylistSyncData: Identifiable, Equatable {
    let id = UUID()
    let playlistID: String
    let name: String
    let artworkURL: URL?
    let songCount: Int
    let sourceURL: String
}

// MARK: - Quick Actions

extension HomeViewModel {
    /// Loads a favorite playlist for syncing
    func loadFavorite(_ favorite: FavoritePlaylist) {
        playlistURL = favorite.spanishURL
        validateURL()

        if validationState.isValid {
            Task {
                await fetchPlaylist()
            }
        }
    }
}
