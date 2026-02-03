import SwiftUI
import MusicKit

/// View for displaying sync progress and results
struct SyncView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SyncViewModel()

    let playlistData: PlaylistSyncData

    @State private var showPlaylistPicker = false
    @State private var isFavorite = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                PlaylistHeaderView(
                    name: viewModel.playlistName,
                    artworkURL: viewModel.playlistArtworkURL,
                    songCount: viewModel.totalSongCount,
                    isFavorite: isFavorite,
                    onFavoriteToggle: toggleFavorite
                )

                // Content based on state
                switch viewModel.syncState {
                case .idle, .loading:
                    loadingView

                case .scanning:
                    scanningView

                case .ready:
                    resultsView

                case .adding:
                    addingView

                case .completed:
                    completedView

                case .error:
                    errorView
                }
            }
            .padding(.bottom, 100)
        }
        .navigationTitle("Sincronizar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.syncState == .ready {
                    Menu {
                        Button(action: toggleFavorite) {
                            Label(
                                isFavorite ? "Quitar de favoritos" : "Guardar en favoritos",
                                systemImage: isFavorite ? "heart.slash" : "heart"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .banner(
            isPresented: $viewModel.showError,
            message: viewModel.errorMessage ?? "",
            type: .error
        )
        .onAppear {
            viewModel.configure(with: playlistData)
            isFavorite = viewModel.isFavorite()
            Task {
                await viewModel.startScanning()
            }
        }
        .sheet(isPresented: $showPlaylistPicker) {
            PlaylistPickerSheet(
                viewModel: viewModel,
                isPresented: $showPlaylistPicker
            )
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Cargando playlist...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: 20) {
            ScanningProgressView(
                progress: viewModel.progress,
                currentSong: viewModel.currentSong,
                totalSongs: viewModel.totalSongCount,
                processedSongs: Int(viewModel.progress * Double(viewModel.totalSongCount))
            )

            Text("Buscando canciones en el catálogo US...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Results View

    private var resultsView: some View {
        VStack(spacing: 16) {
            // Statistics
            if let stats = viewModel.statistics {
                statisticsCard(stats)
            }

            // Destination Picker
            destinationSection

            // Add Button
            addButton

            // Song List
            songList
        }
        .padding(.horizontal)
    }

    private func statisticsCard(_ stats: ISRCMatcher.MatchingStatistics) -> some View {
        HStack(spacing: 20) {
            StatBox(
                value: "\(stats.matchedByISRC)",
                label: "Por ISRC",
                color: .green
            )

            StatBox(
                value: "\(stats.matchedByTitle)",
                label: "Por título",
                color: .orange
            )

            StatBox(
                value: "\(stats.notFound)",
                label: "No encontradas",
                color: .red
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Añadir a")
                .font(.headline)

            Button(action: { showPlaylistPicker = true }) {
                HStack {
                    Image(systemName: viewModel.createNewPlaylist ? "plus.circle.fill" : "music.note.list")
                        .foregroundColor(.accentColor)

                    Text(viewModel.createNewPlaylist
                        ? "Nueva playlist"
                        : (viewModel.selectedPlaylist?.name ?? "Seleccionar playlist"))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private var addButton: some View {
        Button(action: {
            Task { await viewModel.addSongsToPlaylist() }
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Añadir \(viewModel.matchedCount) canciones")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(viewModel.canAddSongs ? Color.accentColor : Color.gray)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!viewModel.canAddSongs)
    }

    private var songList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Canciones (\(viewModel.summaryText))")
                .font(.headline)

            LazyVStack(spacing: 0) {
                ForEach(viewModel.songs) { song in
                    SongRowView(song: song)
                    Divider()
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Adding View

    private var addingView: some View {
        VStack(spacing: 20) {
            CircularProgressView(progress: viewModel.progress, size: 80)

            VStack(spacing: 8) {
                Text("Añadiendo canciones...")
                    .font(.headline)

                Text("\(Int(viewModel.progress * Double(viewModel.matchedCount))) de \(viewModel.matchedCount)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 60)
    }

    // MARK: - Completed View

    private var completedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text("Sincronización completada")
                    .font(.title2.bold())

                Text("\(viewModel.matchedCount) canciones añadidas")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button("Volver al inicio") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 60)
    }

    // MARK: - Error View

    private var errorView: some View {
        EmptyStateView.error(message: viewModel.errorMessage ?? "Error desconocido") {
            Task { await viewModel.startScanning() }
        }
    }

    // MARK: - Actions

    private func toggleFavorite() {
        if isFavorite {
            // TODO: Remove from favorites
        } else {
            viewModel.saveAsFavorite()
        }
        isFavorite.toggle()
    }
}

// MARK: - Stat Box

private struct StatBox: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(color)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Playlist Picker Sheet

private struct PlaylistPickerSheet: View {
    @ObservedObject var viewModel: SyncViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                // Create New Option
                Section {
                    Button(action: {
                        viewModel.createNewPlaylist = true
                        viewModel.selectedPlaylist = nil
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("Crear nueva playlist")

                            Spacer()

                            if viewModel.createNewPlaylist {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if viewModel.createNewPlaylist {
                        TextField("Nombre de la playlist", text: $viewModel.newPlaylistName)
                    }
                }

                // Existing Playlists
                if !viewModel.userPlaylists.isEmpty {
                    Section("Mis playlists") {
                        ForEach(viewModel.userPlaylists, id: \.id) { playlist in
                            Button(action: {
                                viewModel.createNewPlaylist = false
                                viewModel.selectedPlaylist = playlist
                                isPresented = false
                            }) {
                                HStack {
                                    Image(systemName: "music.note.list")
                                    Text(playlist.name)

                                    Spacer()

                                    if !viewModel.createNewPlaylist && viewModel.selectedPlaylist?.id == playlist.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Destino")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Preview

#Preview("Sync View") {
    NavigationStack {
        SyncView(
            playlistData: PlaylistSyncData(
                playlistID: "pl.test123",
                name: "Novedades Viernes España",
                artworkURL: nil,
                songCount: 50,
                sourceURL: "https://music.apple.com/es/playlist/test/pl.test123"
            )
        )
    }
}
