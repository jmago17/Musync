import Foundation

/// Local provenance is migrated with the rest of the state and committed
/// atomically. Apple still determines whether a playlist is actually editable.
enum CreatedPlaylists {
    static var ids: Set<String> { get throws { try SourceStore.store.read().createdPlaylistIDs } }
    static func remember(_ id: String) throws {
        try SourceStore.store.update { $0.createdPlaylistIDs.insert(id) }
    }
    static func contains(_ id: String) throws -> Bool { try ids.contains(id) }
}
