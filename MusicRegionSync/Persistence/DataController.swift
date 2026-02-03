import Foundation
import SwiftData
import SwiftUI

/// Manages SwiftData persistence for the app
@MainActor
final class DataController {
    static let shared = DataController()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            FavoritePlaylist.self,
            SyncHistory.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// Creates a preview container for SwiftUI previews
    static func previewContainer() -> ModelContainer {
        let schema = Schema([
            FavoritePlaylist.self,
            SyncHistory.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )

            // Add sample data for previews
            Task { @MainActor in
                let context = container.mainContext

                // Sample favorite playlists
                let favorites = [
                    FavoritePlaylist(
                        name: "Novedades Viernes España",
                        spanishURL: "https://music.apple.com/es/playlist/novedades-viernes-espa%C3%B1a/pl.a2b3c4d5e6f7",
                        artworkURL: nil,
                        songCount: 50,
                        lastSyncDate: Date().addingTimeInterval(-86400),
                        dateAdded: Date().addingTimeInterval(-604800)
                    ),
                    FavoritePlaylist(
                        name: "Éxitos España",
                        spanishURL: "https://music.apple.com/es/playlist/%C3%A9xitos-espa%C3%B1a/pl.z9y8x7w6v5u4",
                        artworkURL: nil,
                        songCount: 100,
                        lastSyncDate: Date().addingTimeInterval(-172800),
                        dateAdded: Date().addingTimeInterval(-1209600)
                    )
                ]

                for favorite in favorites {
                    context.insert(favorite)
                }

                // Sample sync history
                let histories = [
                    SyncHistory(
                        date: Date().addingTimeInterval(-3600),
                        sourcePlaylistName: "Novedades Viernes España",
                        sourcePlaylistURL: "https://music.apple.com/es/playlist/novedades-viernes-espa%C3%B1a/pl.a2b3c4d5e6f7",
                        destinationPlaylistName: "Mi Playlist Sync",
                        songsRequested: 50,
                        songsAdded: 47,
                        songsFailed: 3,
                        status: .partial,
                        failedSongTitles: ["Canción No Disponible 1", "Canción No Disponible 2", "Canción No Disponible 3"]
                    ),
                    SyncHistory(
                        date: Date().addingTimeInterval(-86400),
                        sourcePlaylistName: "Éxitos España",
                        sourcePlaylistURL: "https://music.apple.com/es/playlist/%C3%A9xitos-espa%C3%B1a/pl.z9y8x7w6v5u4",
                        destinationPlaylistName: "Éxitos US",
                        songsRequested: 100,
                        songsAdded: 100,
                        songsFailed: 0,
                        status: .completed
                    )
                ]

                for history in histories {
                    context.insert(history)
                }

                try? context.save()
            }

            return container
        } catch {
            fatalError("Failed to create preview ModelContainer: \(error)")
        }
    }
}

// MARK: - Favorite Playlists Operations

extension DataController {
    /// Adds a new favorite playlist
    func addFavorite(
        name: String,
        spanishURL: String,
        artworkURL: String?,
        songCount: Int
    ) throws {
        let favorite = FavoritePlaylist(
            name: name,
            spanishURL: spanishURL,
            artworkURL: artworkURL,
            songCount: songCount
        )

        container.mainContext.insert(favorite)
        try container.mainContext.save()
    }

    /// Updates the last sync date for a favorite
    func updateFavoriteLastSync(id: UUID) throws {
        let descriptor = FetchDescriptor<FavoritePlaylist>(
            predicate: #Predicate { $0.id == id }
        )

        guard let favorite = try container.mainContext.fetch(descriptor).first else {
            return
        }

        favorite.lastSyncDate = Date()
        try container.mainContext.save()
    }

    /// Deletes a favorite playlist
    func deleteFavorite(_ favorite: FavoritePlaylist) throws {
        container.mainContext.delete(favorite)
        try container.mainContext.save()
    }

    /// Checks if a URL is already saved as favorite
    func isFavorite(url: String) throws -> Bool {
        let descriptor = FetchDescriptor<FavoritePlaylist>(
            predicate: #Predicate { $0.spanishURL == url }
        )

        let count = try container.mainContext.fetchCount(descriptor)
        return count > 0
    }
}

// MARK: - Sync History Operations

extension DataController {
    /// Adds a new sync history entry
    func addSyncHistory(_ history: SyncHistory) throws {
        container.mainContext.insert(history)
        try container.mainContext.save()
    }

    /// Gets all sync history entries sorted by date
    func fetchSyncHistory() throws -> [SyncHistory] {
        let descriptor = FetchDescriptor<SyncHistory>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        return try container.mainContext.fetch(descriptor)
    }

    /// Deletes a sync history entry
    func deleteSyncHistory(_ history: SyncHistory) throws {
        container.mainContext.delete(history)
        try container.mainContext.save()
    }

    /// Clears all sync history
    func clearAllHistory() throws {
        let histories = try fetchSyncHistory()
        for history in histories {
            container.mainContext.delete(history)
        }
        try container.mainContext.save()
    }
}

// MARK: - Error Handling

extension DataController {
    enum DataError: LocalizedError {
        case saveFailed(Error)
        case fetchFailed(Error)
        case deleteFailed(Error)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let error):
                return "Error al guardar: \(error.localizedDescription)"
            case .fetchFailed(let error):
                return "Error al cargar datos: \(error.localizedDescription)"
            case .deleteFailed(let error):
                return "Error al eliminar: \(error.localizedDescription)"
            }
        }
    }
}
