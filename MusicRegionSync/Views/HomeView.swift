import SwiftUI
import SwiftData

/// Main home screen with URL input and quick access to favorites/history
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var networkMonitor = NetworkMonitor.shared

    @Query(sort: \FavoritePlaylist.dateAdded, order: .reverse)
    private var favorites: [FavoritePlaylist]

    @Query(sort: \SyncHistory.date, order: .reverse)
    private var recentHistory: [SyncHistory]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // URL Input Section
                    urlInputSection

                    // Network Status Warning
                    if !networkMonitor.isConnected {
                        networkWarning
                    }

                    // Quick Access Sections
                    if !favorites.isEmpty {
                        favoritesSection
                    }

                    if !recentHistory.isEmpty {
                        historySection
                    }

                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("MusicRegionSync")
            .navigationDestination(isPresented: $viewModel.navigateToSync) {
                if let data = viewModel.playlistToSync {
                    SyncView(playlistData: data)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
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

    // MARK: - URL Input Section

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pega la URL de una playlist española")
                .font(.headline)

            HStack(spacing: 12) {
                TextField("https://music.apple.com/es/playlist/...", text: $viewModel.playlistURL)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: viewModel.playlistURL) { _, _ in
                        viewModel.validateURL()
                    }

                // Paste button
                Button(action: viewModel.pasteFromClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
            }

            // Validation feedback
            if let message = viewModel.validationState.message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Search button
            Button(action: {
                Task { await viewModel.fetchPlaylist() }
            }) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text("Buscar canciones")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(viewModel.validationState.isValid ? Color.accentColor : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!viewModel.validationState.isValid || viewModel.isLoading)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Network Warning

    private var networkWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
            Text("Sin conexión a internet")
            Spacer()
        }
        .font(.subheadline)
        .foregroundColor(.white)
        .padding()
        .background(Color.orange)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Favorites Section

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Favoritos")
                    .font(.headline)
                Spacer()
                NavigationLink("Ver todos") {
                    FavoritesView()
                }
                .font(.subheadline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(favorites.prefix(5)) { favorite in
                        FavoriteCard(favorite: favorite) {
                            viewModel.loadFavorite(favorite)
                        }
                    }
                }
            }
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recientes")
                    .font(.headline)
                Spacer()
                NavigationLink("Ver historial") {
                    HistoryView()
                }
                .font(.subheadline)
            }

            VStack(spacing: 8) {
                ForEach(recentHistory.prefix(3)) { entry in
                    HistoryCard(entry: entry)
                }
            }
        }
    }
}

// MARK: - Favorite Card

private struct FavoriteCard: View {
    let favorite: FavoritePlaylist
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
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
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(favorite.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    Text("\(favorite.songCount) canciones")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 120)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History Card

private struct HistoryCard: View {
    let entry: SyncHistory

    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            Image(systemName: entry.status.iconName)
                .font(.title2)
                .foregroundColor(statusColor)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.sourcePlaylistName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(entry.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Date
            Text(entry.relativeDateFormatted)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var statusColor: Color {
        switch entry.status {
        case .completed: return .green
        case .partial: return .orange
        case .failed: return .red
        case .inProgress: return .blue
        }
    }
}

// MARK: - Settings View (Placeholder)

struct SettingsView: View {
    @StateObject private var musicKitService = MusicKitService.shared

    var body: some View {
        List {
            Section("Cuenta") {
                HStack {
                    Text("Apple Music")
                    Spacer()
                    Text(musicKitService.isAuthorized ? "Conectado" : "No conectado")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Suscripción")
                    Spacer()
                    Text(musicKitService.hasSubscription ? "Activa" : "No activa")
                        .foregroundColor(.secondary)
                }
            }

            Section("Información") {
                HStack {
                    Text("Versión")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Ajustes")
    }
}

// MARK: - Preview

#Preview("Home") {
    HomeView()
        .modelContainer(DataController.previewContainer())
}
