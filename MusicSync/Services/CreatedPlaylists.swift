import Foundation

/// Registro de las playlists que ha creado MusicSync.
///
/// Hace falta porque Apple **no expone** quién creó una playlist: ni la API REST
/// (`LibraryPlaylists.Attributes` solo trae `canEdit`, que se refiere a poder
/// añadir pistas) ni MusicKit (`Playlist` no tiene `isEditable`, y `Playlist.Kind`
/// solo distingue editorial/personalMix/replay/userShared/external).
///
/// Sin embargo `MusicLibrary.edit` **solo** funciona sobre playlists creadas por
/// esta app. Así que guardamos nosotros los ids al crearlas, y ese registro es lo
/// que determina si el modo "Reemplazar" está disponible para un destino.
enum CreatedPlaylists {
    private static let key = "MusicSync.createdPlaylistIDs"

    static var ids: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func remember(_ id: String) {
        var current = ids
        current.insert(id)
        UserDefaults.standard.set(Array(current), forKey: key)
    }

    static func contains(_ id: String) -> Bool { ids.contains(id) }
}
