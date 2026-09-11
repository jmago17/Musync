import AppIntents
import MusicKit

/// Shortcuts action: sync every configured playlist. Drop it into a time-based
/// Shortcuts automation (e.g. viernes 10:00) to replace the Mac's weekly cron.
struct SyncAllPlaylistsIntent: AppIntent {
    static var title: LocalizedStringResource = "Sincronizar todas las playlists"
    static var description = IntentDescription(
        "Espeja todas las playlists configuradas en tu biblioteca de música.")

    /// Abre la app al ejecutarse: foreground = sin límite de tiempo de background y
    /// MusicKit funciona con fiabilidad (en background daba timeout / fallaba).
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard MusicAuthorization.currentStatus == .authorized else {
            return .result(dialog: "Abre MusicSync y autoriza Apple Music antes de automatizar.")
        }
        let s = await SyncService.syncAll()
        let dialog: String
        if s.failed == 0 {
            dialog = "\(s.ok) playlists sincronizadas · \(s.matched) canciones."
        } else {
            dialog = "\(s.ok) OK, \(s.failed) con error (de \(s.playlists))."
        }
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - Sync a single, selectable playlist

/// A configured playlist, exposed to Shortcuts so it can be picked as a parameter.
struct PlaylistEntity: AppEntity, Identifiable {
    var id: String        // SavedSource.id.uuidString
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Playlist"
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = PlaylistQuery()
}

struct PlaylistQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PlaylistEntity] {
        SourceStore.loadSources()
            .filter { identifiers.contains($0.id.uuidString) }
            .map { PlaylistEntity(id: $0.id.uuidString, name: $0.targetName) }
    }
    func suggestedEntities() async throws -> [PlaylistEntity] {
        SourceStore.loadSources().map { PlaylistEntity(id: $0.id.uuidString, name: $0.targetName) }
    }
}

/// Shortcuts action: sync one chosen playlist. Ligero → cabe en el presupuesto de
/// tiempo de una automatización (a diferencia de "todas de golpe").
struct SyncPlaylistIntent: AppIntent {
    static var title: LocalizedStringResource = "Sincronizar una playlist"
    static var description = IntentDescription(
        "Espeja una playlist concreta en tu biblioteca de música.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Playlist")
    var playlist: PlaylistEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Sincronizar \(\.$playlist)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard MusicAuthorization.currentStatus == .authorized else {
            return .result(dialog: "Abre MusicSync y autoriza Apple Music antes de automatizar.")
        }
        guard let run = await SyncService.syncOne(id: playlist.id) else {
            return .result(dialog: "No encontré esa playlist.")
        }
        let dialog = run.failed
            ? (run.errorMessage ?? "Error al sincronizar.")
            : "\(run.targetName): \(run.matched)/\(run.totalTracks) canciones."
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - Two-step sync for Shortcuts time limits

/// A persisted batch of catalog song IDs returned by "Obtener canciones" and
/// accepted directly by "Añadir/reemplazar canciones" in the next Shortcut step.
struct PreparedSongsEntity: AppEntity, Identifiable {
    var id: String
    var name: String
    var songCount: Int

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Canciones preparadas"
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(songCount) canciones")
    }
    static var defaultQuery = PreparedSongsQuery()
}

struct PreparedSongsQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PreparedSongsEntity] {
        let wanted = Set(identifiers)
        return SourceStore.loadPrepared().compactMap { item in
            guard wanted.contains(item.id.uuidString) else { return nil }
            return PreparedSongsEntity(id: item.id.uuidString, name: item.targetName,
                                       songCount: item.songIDs.count)
        }
    }

    func suggestedEntities() async throws -> [PreparedSongsEntity] {
        SourceStore.loadPrepared().map {
            PreparedSongsEntity(id: $0.id.uuidString, name: $0.targetName,
                                songCount: $0.songIDs.count)
        }
    }
}

struct GetPlaylistSongsIntent: AppIntent {
    static var title: LocalizedStringResource = "Obtener canciones de playlist"
    static var description = IntentDescription(
        "Lee la playlist origen y prepara sus canciones para una acción posterior.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Playlist")
    var playlist: PlaylistEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Obtener canciones de \(\.$playlist)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<PreparedSongsEntity> & ProvidesDialog {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw MusicSyncIntentError.notAuthorized
        }
        guard let prepared = try await SyncService.prepareOne(id: playlist.id) else {
            throw MusicSyncIntentError.playlistNotFound
        }
        let value = PreparedSongsEntity(id: prepared.id.uuidString,
                                        name: prepared.targetName,
                                        songCount: prepared.songIDs.count)
        return .result(value: value,
                       dialog: "\(prepared.songIDs.count) de \(prepared.totalTracks) canciones preparadas.")
    }
}

struct ApplyPlaylistSongsIntent: AppIntent {
    static var title: LocalizedStringResource = "Añadir o reemplazar canciones"
    static var description = IntentDescription(
        "Añade o reemplaza en la playlist destino un lote preparado previamente.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Canciones preparadas")
    var preparedSongs: PreparedSongsEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Añadir o reemplazar \(\.$preparedSongs)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw MusicSyncIntentError.notAuthorized
        }
        guard let id = UUID(uuidString: preparedSongs.id),
              let run = try await SyncService.applyPrepared(id: id) else {
            throw MusicSyncIntentError.preparedBatchNotFound
        }
        return .result(dialog: "\(run.targetName): \(run.matched)/\(run.totalTracks) canciones escritas.")
    }
}

enum MusicSyncIntentError: LocalizedError {
    case notAuthorized
    case playlistNotFound
    case preparedBatchNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Abre MusicSync y autoriza el acceso a Música."
        case .playlistNotFound:
            return "No encontré esa playlist configurada."
        case .preparedBatchNotFound:
            return "El lote preparado no existe o ha caducado. Ejecuta primero Obtener canciones."
        }
    }
}

struct MusicSyncShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetPlaylistSongsIntent(),
            phrases: ["Obtener canciones con \(.applicationName)"],
            shortTitle: "Obtener canciones",
            systemImageName: "arrow.down.circle")
        AppShortcut(
            intent: ApplyPlaylistSongsIntent(),
            phrases: ["Escribir canciones con \(.applicationName)"],
            shortTitle: "Añadir o reemplazar",
            systemImageName: "arrow.up.circle")
        AppShortcut(
            intent: SyncPlaylistIntent(),
            phrases: [
                "Sincronizar \(\.$playlist) con \(.applicationName)",
            ],
            shortTitle: "Sincronizar playlist",
            systemImageName: "music.note.list")
        AppShortcut(
            intent: SyncAllPlaylistsIntent(),
            phrases: [
                "Sincronizar playlists con \(.applicationName)",
                "Sincroniza mi música con \(.applicationName)",
            ],
            shortTitle: "Sincronizar todas",
            systemImageName: "arrow.triangle.2.circlepath")
    }
}
