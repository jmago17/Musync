import SwiftUI

/// Detail view for a sync history entry
struct SyncDetailView: View {
    let history: SyncHistory

    @State private var selectedTab: DetailTab = .all

    enum DetailTab: String, CaseIterable {
        case all = "Todas"
        case matched = "Encontradas"
        case failed = "No encontradas"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary Card
                summaryCard

                // Tabs
                Picker("Filtro", selection: $selectedTab) {
                    ForEach(DetailTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Song List
                songList
            }
            .padding(.vertical)
        }
        .navigationTitle("Detalle")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(spacing: 16) {
            // Status Icon
            Image(systemName: history.status.iconName)
                .font(.system(size: 50))
                .foregroundColor(statusColor)

            // Playlist Names
            VStack(spacing: 4) {
                Text(history.sourcePlaylistName)
                    .font(.headline)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                    Text(history.destinationPlaylistName)
                        .font(.subheadline)
                }
                .foregroundColor(.secondary)
            }

            // Stats
            HStack(spacing: 32) {
                VStack(spacing: 4) {
                    Text("\(history.songsAdded)")
                        .font(.title.bold())
                        .foregroundColor(.green)
                    Text("Añadidas")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 4) {
                    Text("\(history.songsFailed)")
                        .font(.title.bold())
                        .foregroundColor(.red)
                    Text("Fallidas")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 4) {
                    Text("\(history.songsRequested)")
                        .font(.title.bold())
                        .foregroundColor(.primary)
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Date
            Text(history.dateFormatted)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Song List

    @ViewBuilder
    private var songList: some View {
        if let songs = history.syncedSongs {
            let filteredSongs = filterSongs(songs)

            if filteredSongs.isEmpty {
                EmptyStateView(
                    icon: "music.note",
                    title: "Sin canciones",
                    message: "No hay canciones en esta categoría"
                )
                .frame(height: 200)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredSongs) { song in
                        SyncDetailSongRow(song: song)
                        Divider()
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        } else if !history.failedSongTitles.isEmpty {
            // Fallback to failed song titles if detailed data not available
            VStack(alignment: .leading, spacing: 12) {
                Text("Canciones no encontradas")
                    .font(.headline)
                    .padding(.horizontal)

                LazyVStack(spacing: 0) {
                    ForEach(history.failedSongTitles, id: \.self) { title in
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(title)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding()

                        Divider()
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        } else {
            EmptyStateView(
                icon: "doc.text",
                title: "Sin detalles",
                message: "No hay información detallada disponible para esta sincronización"
            )
            .frame(height: 200)
        }
    }

    // MARK: - Helpers

    private func filterSongs(_ songs: [SyncedSongRecord]) -> [SyncedSongRecord] {
        switch selectedTab {
        case .all:
            return songs
        case .matched:
            return songs.filter { $0.matchStatus == .matched || $0.matchStatus == .matchedByTitle }
        case .failed:
            return songs.filter { $0.matchStatus == .notFound }
        }
    }

    private var statusColor: Color {
        switch history.status {
        case .completed: return .green
        case .partial: return .orange
        case .failed: return .red
        case .inProgress: return .blue
        }
    }
}

// MARK: - Song Row for Detail View

private struct SyncDetailSongRow: View {
    let song: SyncedSongRecord

    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            statusIcon

            // Song Info
            VStack(alignment: .leading, spacing: 4) {
                Text(song.originalTitle)
                    .font(.body)
                    .lineLimit(1)

                Text(song.originalArtist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let matchedTitle = song.matchedTitle,
                   matchedTitle != song.originalTitle {
                    Text("→ \(matchedTitle)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch song.matchStatus {
        case .matched:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .matchedByTitle:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        case .notFound:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .pending:
            Image(systemName: "clock.fill")
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Preview

#Preview("Sync Detail") {
    NavigationStack {
        SyncDetailView(
            history: SyncHistory(
                sourcePlaylistName: "Novedades Viernes España",
                sourcePlaylistURL: "https://music.apple.com/es/playlist/test",
                destinationPlaylistName: "Mi Playlist Sync",
                songsRequested: 50,
                songsAdded: 47,
                songsFailed: 3,
                status: .partial,
                failedSongTitles: ["Canción 1", "Canción 2", "Canción 3"]
            )
        )
    }
}
