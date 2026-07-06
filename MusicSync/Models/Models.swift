import Foundation

// MARK: - Sync mode

enum SyncMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case replace
    case append

    var id: String { rawValue }

    var label: String {
        switch self {
        case .replace: return "Reemplazar"
        case .append:  return "Añadir"
        }
    }

    var help: String {
        switch self {
        case .replace: return "Borra la playlist destino y la recrea con el contenido actual del origen."
        case .append:  return "Añade solo las canciones nuevas, sin tocar las que ya están."
        }
    }
}

// MARK: - Configured source (persisted)

/// A public source playlist the user wants mirrored into their library.
struct SavedSource: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var sourceURL: String
    var targetName: String
    var mode: SyncMode = .replace
    /// Library playlist id from the last successful sync (dodges indexing latency).
    var lastPlaylistID: String? = nil
    var lastSyncedAt: Date? = nil
    var lastMatched: Int? = nil
    var lastMissed: Int? = nil
}

// MARK: - Source parsing results

struct SourceTrack: Codable, Hashable, Sendable {
    var title: String
    var artist: String
    var isrc: String?
    var srcID: String        // catalog song id in the source storefront
}

struct SourcePlaylist: Sendable {
    var title: String
    var storefront: String
    var tracks: [SourceTrack]
}

// MARK: - Catalog match

struct CatalogSong: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var artist: String
    var artworkURL: String?
}

// MARK: - Sync run history (persisted)

struct MissTrack: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var title: String
    var artist: String
    var isrc: String?
    var srcID: String
    /// Set once the user manually resolves this miss to a US-catalog song.
    var resolvedSongID: String? = nil
    var resolvedTitle: String? = nil
}

struct SyncRun: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var date: Date
    var sourceName: String
    var sourceURL: String
    var targetName: String
    var mode: SyncMode
    var matched: Int
    var totalTracks: Int
    var playlistID: String?
    var misses: [MissTrack]
    var failed: Bool = false
    var errorMessage: String? = nil
}
