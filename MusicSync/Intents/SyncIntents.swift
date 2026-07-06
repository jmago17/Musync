import AppIntents
import MusicKit

/// Shortcuts action: sync every configured playlist. Drop it into a time-based
/// Shortcuts automation (e.g. viernes 10:00) to replace the Mac's weekly cron.
struct SyncAllPlaylistsIntent: AppIntent {
    static var title: LocalizedStringResource = "Sincronizar todas las playlists"
    static var description = IntentDescription(
        "Espeja todas las playlists configuradas en tu biblioteca de Apple Music.")

    /// Runs in the background (no UI). If MusicKit ever fails headless, flip to true.
    static var openAppWhenRun: Bool = false

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

struct MusicSyncShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncAllPlaylistsIntent(),
            phrases: [
                "Sincronizar playlists con \(.applicationName)",
                "Sincroniza mi música con \(.applicationName)",
            ],
            shortTitle: "Sincronizar playlists",
            systemImageName: "arrow.triangle.2.circlepath")
    }
}
