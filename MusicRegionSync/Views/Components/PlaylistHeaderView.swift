import SwiftUI

/// Header view for displaying playlist information
struct PlaylistHeaderView: View {
    let name: String
    let artworkURL: URL?
    let songCount: Int
    var curatorName: String?
    var showFavoriteButton: Bool = true
    var isFavorite: Bool = false
    var onFavoriteToggle: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            // Artwork
            AsyncImage(url: artworkURL) { phase in
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
            .frame(width: 180, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            // Info
            VStack(spacing: 8) {
                Text(name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let curatorName {
                    Text(curatorName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text("\(songCount) canciones")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Favorite Button
            if showFavoriteButton {
                Button(action: {
                    onFavoriteToggle?()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                        Text(isFavorite ? "Guardada" : "Guardar")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(isFavorite ? .red : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(isFavorite ? Color.red.opacity(0.15) : Color.gray.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [.purple.opacity(0.3), .pink.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "music.note.list")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.7))
            }
    }
}

// MARK: - Compact Header

struct PlaylistHeaderCompact: View {
    let name: String
    let artworkURL: URL?
    let songCount: Int

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: artworkURL) { phase in
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

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(songCount) canciones")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview("Playlist Header") {
    VStack(spacing: 20) {
        PlaylistHeaderView(
            name: "Novedades Viernes España",
            artworkURL: nil,
            songCount: 50,
            curatorName: "Apple Music España",
            isFavorite: false
        )

        PlaylistHeaderCompact(
            name: "Éxitos España",
            artworkURL: nil,
            songCount: 100
        )
        .padding(.horizontal)
    }
}
