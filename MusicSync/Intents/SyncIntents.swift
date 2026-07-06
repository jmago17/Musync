import AppIntents
import MusicKit

/// Shortcuts action: sync every configured playlist. Drop it into a time-based
/// Shortcuts automation (e.g. viernes 10:00) to replace the Mac's weekly cron.
struct SyncAllPlaylistsIntent: AppIntent {
    static var title: LocalizedStringResource = "Sincronizar todas las playlists"
    static var description = IntentDescription(
        "Espeja todas las playlists configuradas en tu biblioteca de Apple Music.")

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
        "Espeja una playlist concreta en tu biblioteca de Apple Music.")
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

struct MusicSyncShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
