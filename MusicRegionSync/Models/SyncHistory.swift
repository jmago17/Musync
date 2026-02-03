import Foundation
import SwiftData

/// SwiftData model for storing synchronization history
@Model
final class SyncHistory {
    @Attribute(.unique) var id: UUID
    var date: Date
    var sourcePlaylistName: String
    var sourcePlaylistURL: String
    var destinationPlaylistName: String
    var songsRequested: Int
    var songsAdded: Int
    var songsFailed: Int
    var status: SyncStatus
    var failedSongTitles: [String]
    var syncedSongsData: Data?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        sourcePlaylistName: String,
        sourcePlaylistURL: String,
        destinationPlaylistName: String,
        songsRequested: Int,
        songsAdded: Int,
        songsFailed: Int,
        status: SyncStatus,
        failedSongTitles: [String] = [],
        syncedSongs: [SyncedSongRecord]? = nil
    ) {
        self.id = id
        self.date = date
        self.sourcePlaylistName = sourcePlaylistName
        self.sourcePlaylistURL = sourcePlaylistURL
        self.destinationPlaylistName = destinationPlaylistName
        self.songsRequested = songsRequested
        self.songsAdded = songsAdded
        self.songsFailed = songsFailed
        self.status = status
        self.failedSongTitles = failedSongTitles

        if let syncedSongs {
            self.syncedSongsData = try? JSONEncoder().encode(syncedSongs)
        }
    }

    /// Decodes the synced songs from stored data
    var syncedSongs: [SyncedSongRecord]? {
        guard let data = syncedSongsData else { return nil }
        return try? JSONDecoder().decode([SyncedSongRecord].self, from: data)
    }

    /// Updates the synced songs data
    func setSyncedSongs(_ songs: [SyncedSongRecord]) {
        self.syncedSongsData = try? JSONEncoder().encode(songs)
    }
}

extension SyncHistory {
    /// Formatted date string
    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.string(from: date)
    }

    /// Relative date string
    var relativeDateFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Summary string for the sync result
    var summary: String {
        "\(songsAdded) de \(songsRequested) canciones"
    }

    /// Success rate as a percentage
    var successRate: Double {
        guard songsRequested > 0 else { return 0 }
        return Double(songsAdded) / Double(songsRequested) * 100
    }
}

/// Convenience initializer for creating history from a sync operation
extension SyncHistory {
    static func from(
        sourcePlaylistName: String,
        sourcePlaylistURL: String,
        destinationPlaylistName: String,
        songs: [SyncedSong]
    ) -> SyncHistory {
        let matchedSongs = songs.filter { $0.isMatched }
        let failedSongs = songs.filter { !$0.isMatched }

        let status: SyncStatus
        if failedSongs.isEmpty {
            status = .completed
        } else if matchedSongs.isEmpty {
            status = .failed
        } else {
            status = .partial
        }

        let records = songs.map { SyncedSongRecord(from: $0) }

        return SyncHistory(
            sourcePlaylistName: sourcePlaylistName,
            sourcePlaylistURL: sourcePlaylistURL,
            destinationPlaylistName: destinationPlaylistName,
            songsRequested: songs.count,
            songsAdded: matchedSongs.count,
            songsFailed: failedSongs.count,
            status: status,
            failedSongTitles: failedSongs.map { $0.originalTitle },
            syncedSongs: records
        )
    }
}
