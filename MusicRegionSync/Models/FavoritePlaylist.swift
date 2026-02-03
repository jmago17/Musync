import Foundation
import SwiftData

/// SwiftData model for storing favorite playlists
@Model
final class FavoritePlaylist {
    @Attribute(.unique) var id: UUID
    var name: String
    var spanishURL: String
    var artworkURL: String?
    var songCount: Int
    var lastSyncDate: Date?
    var dateAdded: Date

    init(
        id: UUID = UUID(),
        name: String,
        spanishURL: String,
        artworkURL: String? = nil,
        songCount: Int = 0,
        lastSyncDate: Date? = nil,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.spanishURL = spanishURL
        self.artworkURL = artworkURL
        self.songCount = songCount
        self.lastSyncDate = lastSyncDate
        self.dateAdded = dateAdded
    }
}

extension FavoritePlaylist {
    /// Returns a formatted string for the last sync date
    var lastSyncDateFormatted: String? {
        guard let lastSyncDate else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.localizedString(for: lastSyncDate, relativeTo: Date())
    }

    /// Returns the playlist ID extracted from the URL
    var playlistID: String? {
        PlaylistURLParser.extractPlaylistID(from: spanishURL)
    }
}

/// Simple parser for extracting playlist ID from URL
/// Note: Full implementation is in PlaylistParser service
private enum PlaylistURLParser {
    static func extractPlaylistID(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host,
              host.contains("music.apple.com") else {
            return nil
        }

        let pathComponents = url.pathComponents
        guard let playlistIndex = pathComponents.firstIndex(of: "playlist"),
              playlistIndex + 2 < pathComponents.count else {
            return nil
        }

        let idComponent = pathComponents[playlistIndex + 2]
        if idComponent.hasPrefix("pl.") {
            return idComponent
        }

        return nil
    }
}
