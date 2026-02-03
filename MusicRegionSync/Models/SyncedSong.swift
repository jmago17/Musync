import Foundation
import MusicKit

/// Represents a song with its synchronization status between storefronts
struct SyncedSong: Identifiable, Equatable {
    let id: UUID
    let originalTitle: String
    let originalArtist: String
    let originalISRC: String?
    let originalArtworkURL: URL?
    let originalSongID: MusicItemID?

    var matchedSongID: MusicItemID?
    var matchedTitle: String?
    var matchedArtist: String?
    var matchedArtworkURL: URL?

    var matchStatus: SongMatchStatus
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        originalTitle: String,
        originalArtist: String,
        originalISRC: String? = nil,
        originalArtworkURL: URL? = nil,
        originalSongID: MusicItemID? = nil,
        matchedSongID: MusicItemID? = nil,
        matchedTitle: String? = nil,
        matchedArtist: String? = nil,
        matchedArtworkURL: URL? = nil,
        matchStatus: SongMatchStatus = .pending,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.originalTitle = originalTitle
        self.originalArtist = originalArtist
        self.originalISRC = originalISRC
        self.originalArtworkURL = originalArtworkURL
        self.originalSongID = originalSongID
        self.matchedSongID = matchedSongID
        self.matchedTitle = matchedTitle
        self.matchedArtist = matchedArtist
        self.matchedArtworkURL = matchedArtworkURL
        self.matchStatus = matchStatus
        self.errorMessage = errorMessage
    }

    /// Creates a SyncedSong from a MusicKit Song
    static func from(song: Song) -> SyncedSong {
        let artworkURL = song.artwork?.url(width: 100, height: 100)

        return SyncedSong(
            originalTitle: song.title,
            originalArtist: song.artistName,
            originalISRC: song.isrc,
            originalArtworkURL: artworkURL,
            originalSongID: song.id
        )
    }

    /// The title to display (matched if available, otherwise original)
    var displayTitle: String {
        matchedTitle ?? originalTitle
    }

    /// The artist to display (matched if available, otherwise original)
    var displayArtist: String {
        matchedArtist ?? originalArtist
    }

    /// The artwork URL to display (matched if available, otherwise original)
    var displayArtworkURL: URL? {
        matchedArtworkURL ?? originalArtworkURL
    }

    /// Whether this song was successfully matched in the target storefront
    var isMatched: Bool {
        matchStatus == .matched || matchStatus == .matchedByTitle
    }

    static func == (lhs: SyncedSong, rhs: SyncedSong) -> Bool {
        lhs.id == rhs.id
    }
}

/// A simplified version of SyncedSong for persistence
struct SyncedSongRecord: Codable, Identifiable {
    let id: UUID
    let originalTitle: String
    let originalArtist: String
    let matchStatus: SongMatchStatus
    let matchedTitle: String?
    let matchedArtist: String?

    init(from syncedSong: SyncedSong) {
        self.id = syncedSong.id
        self.originalTitle = syncedSong.originalTitle
        self.originalArtist = syncedSong.originalArtist
        self.matchStatus = syncedSong.matchStatus
        self.matchedTitle = syncedSong.matchedTitle
        self.matchedArtist = syncedSong.matchedArtist
    }
}
