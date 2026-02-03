import Foundation
import MusicKit

// MARK: - Song ISRC Extension

extension Song {
    /// Returns the ISRC code if available
    /// ISRC (International Standard Recording Code) is a unique identifier for audio recordings
    var isrc: String? {
        // MusicKit provides ISRC through the song's properties
        // This is available as a standard property on Song
        return self.isrc
    }

    /// Checks if the song has a valid ISRC code
    var hasISRC: Bool {
        guard let isrc = self.isrc else { return false }
        return isISRCValid(isrc)
    }

    /// Validates an ISRC code format
    /// Format: CC-XXX-YY-NNNNN (12 characters without hyphens)
    private func isISRCValid(_ code: String) -> Bool {
        // Remove any hyphens or spaces
        let cleanCode = code.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        // ISRC should be exactly 12 characters
        guard cleanCode.count == 12 else { return false }

        // First 2 characters should be letters (country code)
        let countryCode = String(cleanCode.prefix(2))
        guard countryCode.allSatisfy({ $0.isLetter }) else { return false }

        // Next 3 characters are the registrant code (alphanumeric)
        let registrantCode = String(cleanCode.dropFirst(2).prefix(3))
        guard registrantCode.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }

        // Next 2 characters are the year (numeric)
        let year = String(cleanCode.dropFirst(5).prefix(2))
        guard year.allSatisfy({ $0.isNumber }) else { return false }

        // Last 5 characters are the designation code (numeric)
        let designation = String(cleanCode.suffix(5))
        guard designation.allSatisfy({ $0.isNumber }) else { return false }

        return true
    }
}

// MARK: - Song Display Helpers

extension Song {
    /// Returns a formatted duration string (e.g., "3:45")
    var formattedDuration: String? {
        guard let duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Returns artwork URL at a specified size
    func artworkURL(size: Int) -> URL? {
        return artwork?.url(width: size, height: size)
    }

    /// Returns a search-friendly string combining title and artist
    var searchableText: String {
        "\(title) \(artistName)"
    }
}

// MARK: - Collection Extensions

extension Collection where Element == Song {
    /// Returns songs that have valid ISRC codes
    var songsWithISRC: [Song] {
        self.filter { $0.hasISRC }
    }

    /// Returns songs without ISRC codes
    var songsWithoutISRC: [Song] {
        self.filter { !$0.hasISRC }
    }

    /// Counts songs with valid ISRC codes
    var isrcCount: Int {
        songsWithISRC.count
    }
}

// MARK: - Track Extension

extension Track {
    /// Extracts the Song from a Track if it's a song type
    var asSong: Song? {
        if case .song(let song) = self {
            return song
        }
        return nil
    }
}
