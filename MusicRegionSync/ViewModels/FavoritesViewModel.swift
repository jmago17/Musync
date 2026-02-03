import Foundation
import SwiftUI
import SwiftData

/// ViewModel for the Favorites screen
@MainActor
final class FavoritesViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var favorites: [FavoritePlaylist] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false

    // Navigation
    @Published var selectedFavorite: FavoritePlaylist?
    @Published var navigateToSync: Bool = false
    @Published var playlistToSync: PlaylistSyncData?

    // Services
    private let dataController: DataController
    private let musicKitService: MusicKitService

    // MARK: - Initialization

    init(
        dataController: DataController = .shared,
        musicKitService: MusicKitService = .shared
    ) {
        self.dataController = dataController
        self.musicKitService = musicKitService
    }

    // MARK: - Data Loading

    /// Loads favorites from the database
    func loadFavorites(context: ModelContext) {
        let descriptor = FetchDescriptor<FavoritePlaylist>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )

        do {
            favorites = try context.fetch(descriptor)
        } catch {
            showError(message: "Error al cargar favoritos")
        }
    }

    /// Refreshes all favorites (called on pull-to-refresh)
    func refresh(context: ModelContext) async {
        isLoading = true

        // Reload from database
        loadFavorites(context: context)

        // Optionally update playlist info from API
        for favorite in favorites {
            await updateFavoriteInfo(favorite)
        }

        isLoading = false
    }

    /// Updates favorite info from the API
    private func updateFavoriteInfo(_ favorite: FavoritePlaylist) async {
        guard let playlistID = favorite.playlistID else { return }

        do {
            let info = try await musicKitService.getPlaylistInfo(id: playlistID, storefront: "es")
            favorite.songCount = info.songCount
            if let artworkURL = info.artworkURL {
                favorite.artworkURL = artworkURL.absoluteString
            }
        } catch {
            // Non-critical, just skip updating
            print("Failed to update favorite: \(error)")
        }
    }

    // MARK: - Actions

    /// Starts sync for a favorite playlist
    func syncFavorite(_ favorite: FavoritePlaylist) async {
        guard let playlistID = favorite.playlistID else {
            showError(message: "URL de playlist inválida")
            return
        }

        isLoading = true

        do {
            let info = try await musicKitService.getPlaylistInfo(id: playlistID, storefront: "es")

            playlistToSync = PlaylistSyncData(
                playlistID: playlistID,
                name: info.name,
                artworkURL: info.artworkURL,
                songCount: info.songCount,
                sourceURL: favorite.spanishURL
            )

            navigateToSync = true
        } catch {
            showError(message: "Error al cargar la playlist")
        }

        isLoading = false
    }

    /// Deletes a favorite
    func deleteFavorite(_ favorite: FavoritePlaylist, context: ModelContext) {
        context.delete(favorite)

        do {
            try context.save()
            loadFavorites(context: context)
        } catch {
            showError(message: "Error al eliminar favorito")
        }
    }

    /// Deletes favorites at specified indices
    func deleteFavorites(at offsets: IndexSet, context: ModelContext) {
        for index in offsets {
            context.delete(favorites[index])
        }

        do {
            try context.save()
            loadFavorites(context: context)
        } catch {
            showError(message: "Error al eliminar favoritos")
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

    // MARK: - Navigation

    func resetNavigation() {
        navigateToSync = false
        playlistToSync = nil
        selectedFavorite = nil
    }
}
