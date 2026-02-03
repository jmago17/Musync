import Foundation

/// Service for parsing and validating Apple Music playlist URLs
final class PlaylistParser {

    // MARK: - URL Parsing

    /// Extracts the playlist ID from an Apple Music URL
    /// Expected format: https://music.apple.com/{storefront}/playlist/{name}/{id}
    /// Example: https://music.apple.com/es/playlist/novedades-viernes-españa/pl.abc123def456
    static func extractPlaylistID(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: trimmed) else {
            return nil
        }

        // Validate it's an Apple Music URL
        guard let host = url.host,
              host.contains("music.apple.com") else {
            return nil
        }

        let pathComponents = url.pathComponents

        // Find the "playlist" component and get the ID after it
        guard let playlistIndex = pathComponents.firstIndex(of: "playlist"),
              playlistIndex + 2 < pathComponents.count else {
            return nil
        }

        let idComponent = pathComponents[playlistIndex + 2]

        // Apple Music playlist IDs start with "pl."
        if idComponent.hasPrefix("pl.") {
            return idComponent
        }

        // Handle case where the ID might be URL-encoded or have query parameters
        if let cleanID = idComponent.components(separatedBy: "?").first,
           cleanID.hasPrefix("pl.") {
            return cleanID
        }

        return nil
    }

    /// Extracts the storefront code from an Apple Music URL
    /// Example: "es" from https://music.apple.com/es/playlist/...
    static func extractStorefront(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: trimmed),
              let host = url.host,
              host.contains("music.apple.com") else {
            return nil
        }

        let pathComponents = url.pathComponents

        // The storefront is typically the first path component after the host
        // pathComponents[0] is "/"
        guard pathComponents.count >= 2 else {
            return nil
        }

        let storefront = pathComponents[1]

        // Validate it looks like a storefront code (2 lowercase letters)
        if storefront.count == 2, storefront.allSatisfy({ $0.isLowercase && $0.isLetter }) {
            return storefront
        }

        return nil
    }

    // MARK: - Validation

    /// Validates if a string is a valid Apple Music playlist URL
    static func isValidPlaylistURL(_ urlString: String) -> Bool {
        return extractPlaylistID(from: urlString) != nil
    }

    /// Validates if the URL is from the Spanish storefront
    static func isSpanishPlaylistURL(_ urlString: String) -> Bool {
        return extractStorefront(from: urlString) == "es"
    }

    /// Returns validation result with detailed error if invalid
    static func validate(_ urlString: String) -> ValidationResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if empty
        guard !trimmed.isEmpty else {
            return .invalid(reason: .empty)
        }

        // Check if it's a valid URL
        guard let url = URL(string: trimmed) else {
            return .invalid(reason: .malformedURL)
        }

        // Check if it's an Apple Music URL
        guard let host = url.host, host.contains("music.apple.com") else {
            return .invalid(reason: .notAppleMusic)
        }

        // Check for playlist in path
        guard url.pathComponents.contains("playlist") else {
            return .invalid(reason: .notPlaylist)
        }

        // Check if we can extract a valid ID
        guard let playlistID = extractPlaylistID(from: trimmed) else {
            return .invalid(reason: .missingPlaylistID)
        }

        // Check storefront
        let storefront = extractStorefront(from: trimmed)
        let isSpanish = storefront == "es"

        return .valid(
            playlistID: playlistID,
            storefront: storefront ?? "unknown",
            isSpanishStorefront: isSpanish
        )
    }

    // MARK: - Types

    enum ValidationResult {
        case valid(playlistID: String, storefront: String, isSpanishStorefront: Bool)
        case invalid(reason: InvalidReason)

        var isValid: Bool {
            switch self {
            case .valid: return true
            case .invalid: return false
            }
        }

        var playlistID: String? {
            switch self {
            case .valid(let id, _, _): return id
            case .invalid: return nil
            }
        }
    }

    enum InvalidReason: String {
        case empty = "Pega una URL de playlist"
        case malformedURL = "La URL no es válida"
        case notAppleMusic = "La URL debe ser de Apple Music"
        case notPlaylist = "La URL debe ser de una playlist"
        case missingPlaylistID = "No se pudo extraer el ID de la playlist"

        var message: String { rawValue }
    }
}

// MARK: - URL Building

extension PlaylistParser {
    /// Builds an Apple Music playlist URL for a given storefront
    static func buildPlaylistURL(playlistID: String, storefront: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "music.apple.com"
        components.path = "/\(storefront)/playlist/\(playlistID)"
        return components.url
    }
}
