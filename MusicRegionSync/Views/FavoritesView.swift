import SwiftUI
import SwiftData

/// View for managing favorite playlists
struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = FavoritesViewModel()

    @Query(sort: \FavoritePlaylist.dateAdded, order: .reverse)
    private var favorites: [FavoritePlaylist]

    var body: some View {
        Group {
            if favorites.isEmpty {
                EmptyStateView.noFavorites
            } else {
                favoritesList
            }
        }
        .navigationTitle("Favoritos")
        .navigationDestination(isPresented: $viewModel.navigateToSync) {
            if let data = viewModel.playlistToSync {
                SyncView(playlistData: data)
            }
        }
        .refreshable {
            await viewModel.refresh(context: modelContext)
        }
        .banner(
            isPresented: $viewModel.showError,
            message: viewModel.errorMessage ?? "",
            type: .error
        )
        .onChange(of: viewModel.navigateToSync) { _, newValue in
            if !newValue {
                viewModel.resetNavigation()
            }
        }
    }

    // MARK: - Favorites List

    private var favoritesList: some View {
        List {
            ForEach(favorites) { favorite in
                FavoriteRowView(favorite: favorite) {
                    Task { await viewModel.syncFavorite(favorite) }
                }
            }
            .onDelete { offsets in
                viewModel.deleteFavorites(at: offsets, context: modelContext)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Favorite Row View

private struct FavoriteRowView: View {
    let favorite: FavoritePlaylist
    let onSync: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            AsyncImage(url: URL(string: favorite.artworkURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "music.note.list")
                                .foregroundColor(.gray)
                        }
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(favorite.name)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(favorite.songCount) canciones")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let lastSync = favorite.lastSyncDateFormatted {
                    Text("Última sync: \(lastSync)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Sync Button
            Button(action: onSync) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                // Delete handled by parent
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }
}

// MARK: - Preview

#Preview("Favorites") {
    NavigationStack {
        FavoritesView()
    }
    .modelContainer(DataController.previewContainer())
}

#Preview("Favorites Empty") {
    NavigationStack {
        FavoritesView()
    }
    .modelContainer(for: FavoritePlaylist.self, inMemory: true)
}
