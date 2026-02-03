import Foundation
import MusicKit

/// Service for matching songs between storefronts using ISRC codes
@MainActor
final class ISRCMatcher: ObservableObject {
    private let musicKitService: MusicKitService

    @Published private(set) var matchProgress: Double = 0
    @Published private(set) var currentlyMatching: String?
    @Published private(set) var isMatching: Bool = false

    // Cache for ISRC lookups to avoid repeated API calls
    private var isrcCache: [String: Song] = [:]

    // Rate limiting
    private let requestDelay: TimeInterval = 0.1 // 100ms between requests
    private let batchSize = 10
    private let batchDelay: TimeInterval = 1.0 // 1 second between batches

    init(musicKitService: MusicKitService = .shared) {
        self.musicKitService = musicKitService
    }

    // MARK: - Matching

    /// Matches a list of songs from the source storefront to the target storefront
    func matchSongs(
        _ songs: [Song],
        fromStorefront: String = "es",
        toStorefront: String = "us",
        progressCallback: ((Double, String?) -> Void)? = nil
    ) async throws -> [SyncedSong] {
        isMatching = true
        matchProgress = 0
        currentlyMatching = nil

        defer {
            isMatching = false
            currentlyMatching = nil
        }

        var syncedSongs: [SyncedSong] = []
        let total = songs.count

        // Process in batches to respect rate limits
        for (index, song) in songs.enumerated() {
            // Update progress
            let progress = Double(index) / Double(total)
            matchProgress = progress
            currentlyMatching = song.title
            progressCallback?(progress, song.title)

            // Create initial SyncedSong
            var syncedSong = SyncedSong.from(song: song)

            // Try to match by ISRC first
            if let isrc = song.isrc {
                if let cachedSong = isrcCache[isrc] {
                    // Use cached result
                    syncedSong = updateSyncedSong(syncedSong, with: cachedSong, matchType: .matched)
                } else if let matchedSong = try await matchByISRC(isrc, storefront: toStorefront) {
                    // Cache the result
                    isrcCache[isrc] = matchedSong
                    syncedSong = updateSyncedSong(syncedSong, with: matchedSong, matchType: .matched)
                } else {
                    // ISRC not found, try fallback
                    if let fallbackSong = try await matchByTitleArtist(
                        title: song.title,
                        artist: song.artistName,
                        storefront: toStorefront
                    ) {
                        syncedSong = updateSyncedSong(syncedSong, with: fallbackSong, matchType: .matchedByTitle)
                    } else {
                        syncedSong.matchStatus = .notFound
                    }
                }
            } else {
                // No ISRC, use title+artist search
                if let matchedSong = try await matchByTitleArtist(
                    title: song.title,
                    artist: song.artistName,
                    storefront: toStorefront
                ) {
                    syncedSong = updateSyncedSong(syncedSong, with: matchedSong, matchType: .matchedByTitle)
                } else {
                    syncedSong.matchStatus = .notFound
                }
            }

            syncedSongs.append(syncedSong)

            // Rate limiting - add delay between requests
            if index < total - 1 {
                await addDelay(index: index)
            }
        }

        matchProgress = 1.0
        return syncedSongs
    }

    /// Updates a SyncedSong with matched song data
    private func updateSyncedSong(
        _ original: SyncedSong,
        with matchedSong: Song,
        matchType: SongMatchStatus
    ) -> SyncedSong {
        var updated = original
        updated.matchedSongID = matchedSong.id
        updated.matchedTitle = matchedSong.title
        updated.matchedArtist = matchedSong.artistName
        updated.matchedArtworkURL = matchedSong.artwork?.url(width: 100, height: 100)
        updated.matchStatus = matchType
        return updated
    }

    // MARK: - ISRC Matching

    /// Matches a song by ISRC code
    private func matchByISRC(
        _ isrc: String,
        storefront: String
    ) async throws -> Song? {
        return try await NetworkMonitor.withRetry(maxAttempts: 3) {
            try await self.musicKitService.searchSongByISRC(isrc: isrc, storefront: storefront)
        }
    }

    // MARK: - Title/Artist Matching

    /// Matches a song by title and artist name
    private func matchByTitleArtist(
        title: String,
        artist: String,
        storefront: String
    ) async throws -> Song? {
        return try await NetworkMonitor.withRetry(maxAttempts: 3) {
            try await self.musicKitService.searchSongByTitleArtist(
                title: title,
                artist: artist,
                storefront: storefront
            )
        }
    }

    // MARK: - Rate Limiting

    private func addDelay(index: Int) async {
        // Standard delay between each request
        try? await Task.sleep(nanoseconds: UInt64(requestDelay * 1_000_000_000))

        // Extra delay every batch
        if (index + 1) % batchSize == 0 {
            try? await Task.sleep(nanoseconds: UInt64(batchDelay * 1_000_000_000))
        }
    }

    // MARK: - Cache Management

    /// Clears the ISRC cache
    func clearCache() {
        isrcCache.removeAll()
    }

    /// Gets the current cache size
    var cacheSize: Int {
        isrcCache.count
    }
}

// MARK: - Matching Statistics

extension ISRCMatcher {
    struct MatchingStatistics {
        let total: Int
        let matchedByISRC: Int
        let matchedByTitle: Int
        let notFound: Int

        var matchRate: Double {
            guard total > 0 else { return 0 }
            return Double(matchedByISRC + matchedByTitle) / Double(total) * 100
        }

        var summary: String {
            "\(matchedByISRC + matchedByTitle)/\(total) canciones disponibles"
        }
    }

    /// Calculates statistics from matched songs
    static func calculateStatistics(from songs: [SyncedSong]) -> MatchingStatistics {
        let matchedByISRC = songs.filter { $0.matchStatus == .matched }.count
        let matchedByTitle = songs.filter { $0.matchStatus == .matchedByTitle }.count
        let notFound = songs.filter { $0.matchStatus == .notFound }.count

        return MatchingStatistics(
            total: songs.count,
            matchedByISRC: matchedByISRC,
            matchedByTitle: matchedByTitle,
            notFound: notFound
        )
    }
}
