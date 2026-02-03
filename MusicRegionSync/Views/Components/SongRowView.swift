import SwiftUI

/// Row view for displaying a song with its sync status
struct SongRowView: View {
    let song: SyncedSong
    var showStatus: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            AsyncImage(url: song.displayArtworkURL) { phase in
                switch phase {
                case .empty:
                    artworkPlaceholder
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    artworkPlaceholder
                @unknown default:
                    artworkPlaceholder
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Song Info
            VStack(alignment: .leading, spacing: 4) {
                Text(song.displayTitle)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text(song.displayArtist)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status Icon
            if showStatus {
                statusIcon
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Subviews

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.2))
            .overlay {
                Image(systemName: "music.note")
                    .foregroundColor(.gray)
            }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch song.matchStatus {
        case .matched:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)

        case .matchedByTitle:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)

        case .notFound:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.title3)

        case .pending:
            ProgressView()
                .scaleEffect(0.8)
        }
    }
}

// MARK: - Song Row Skeleton

struct SongRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 150, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 100, height: 12)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .shimmering()
    }
}

// MARK: - Preview

#Preview("Song Row - Matched") {
    List {
        SongRowView(
            song: SyncedSong(
                originalTitle: "Bad Bunny - Monaco",
                originalArtist: "Bad Bunny",
                matchStatus: .matched
            )
        )

        SongRowView(
            song: SyncedSong(
                originalTitle: "Quevedo - Columbia",
                originalArtist: "Quevedo",
                matchStatus: .matchedByTitle
            )
        )

        SongRowView(
            song: SyncedSong(
                originalTitle: "Canción No Disponible",
                originalArtist: "Artista Español",
                matchStatus: .notFound
            )
        )

        SongRowSkeleton()
    }
}
