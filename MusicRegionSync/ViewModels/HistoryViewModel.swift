import Foundation
import SwiftUI
import SwiftData

/// ViewModel for the History screen
@MainActor
final class HistoryViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var history: [SyncHistory] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var showClearConfirmation: Bool = false

    // Navigation
    @Published var selectedHistory: SyncHistory?
    @Published var navigateToDetail: Bool = false
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

    /// Loads history from the database
    func loadHistory(context: ModelContext) {
        let descriptor = FetchDescriptor<SyncHistory>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        do {
            history = try context.fetch(descriptor)
        } catch {
            showError(message: "Error al cargar el historial")
        }
    }

    /// Refreshes history (called on pull-to-refresh)
    func refresh(context: ModelContext) async {
        isLoading = true
        loadHistory(context: context)
        isLoading = false
    }

    // MARK: - Actions

    /// Views detail of a history entry
    func viewDetail(_ entry: SyncHistory) {
        selectedHistory = entry
        navigateToDetail = true
    }

    /// Repeats a sync from history
    func repeatSync(_ entry: SyncHistory) async {
        guard let playlistID = PlaylistParser.extractPlaylistID(from: entry.sourcePlaylistURL) else {
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
                sourceURL: entry.sourcePlaylistURL
            )

            navigateToSync = true
        } catch {
            showError(message: "Error al cargar la playlist")
        }

        isLoading = false
    }

    /// Deletes a history entry
    func deleteEntry(_ entry: SyncHistory, context: ModelContext) {
        context.delete(entry)

        do {
            try context.save()
            loadHistory(context: context)
        } catch {
            showError(message: "Error al eliminar entrada")
        }
    }

    /// Deletes entries at specified indices
    func deleteEntries(at offsets: IndexSet, context: ModelContext) {
        for index in offsets {
            context.delete(history[index])
        }

        do {
            try context.save()
            loadHistory(context: context)
        } catch {
            showError(message: "Error al eliminar entradas")
        }
    }

    /// Clears all history
    func clearAllHistory(context: ModelContext) {
        for entry in history {
            context.delete(entry)
        }

        do {
            try context.save()
            history = []
        } catch {
            showError(message: "Error al limpiar historial")
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
        navigateToDetail = false
        navigateToSync = false
        selectedHistory = nil
        playlistToSync = nil
    }

    // MARK: - Computed Properties

    /// Groups history by date for section headers
    var groupedHistory: [Date: [SyncHistory]] {
        Dictionary(grouping: history) { entry in
            Calendar.current.startOfDay(for: entry.date)
        }
    }

    /// Sorted date keys for sections
    var sortedDates: [Date] {
        groupedHistory.keys.sorted(by: >)
    }

    /// Formats a date for section headers
    func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Hoy"
        } else if calendar.isDateInYesterday(date) {
            return "Ayer"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.locale = Locale(identifier: "es_ES")
            return formatter.string(from: date)
        }
    }
}
