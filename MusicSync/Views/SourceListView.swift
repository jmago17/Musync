import SwiftUI

struct SourceListView: View {
    @Environment(AppStore.self) private var store
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if store.sources.isEmpty {
                    ContentUnavailableView("Sin playlists",
                                           systemImage: "music.note.list",
                                           description: Text("Añade una playlist pública de Apple Music para espejarla en tu biblioteca."))
                }
                ForEach(store.sources) { source in
                    NavigationLink(value: source.id) {
                        SourceRow(source: source, progress: store.progress[source.id])
                    }
                }
                .onDelete { store.deleteSources(at: $0) }
            }
            .navigationTitle("Playlists")
            .navigationDestination(for: UUID.self) { id in
                if let source = store.binding(for: id) {
                    SourceEditView(source: source)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await store.syncAll() }
                    } label: {
                        if store.isSyncingAll {
                            ProgressView()
                        } else {
                            Label("Sincronizar todas", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(store.isSyncingAll || store.sources.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddSourceSheet() }
        }
    }
}

struct SourceRow: View {
    let source: SavedSource
    let progress: SyncProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.targetName).font(.body).lineLimit(1)
            if let progress {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(progress.text).font(.caption).foregroundStyle(.secondary)
                }
            } else if let at = source.lastSyncedAt {
                Text(subtitle(at))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(source.mode.label + " · nunca sincronizada")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(_ at: Date) -> String {
        let rel = at.formatted(.relative(presentation: .named))
        var parts = [source.mode.label, rel]
        if let m = source.lastMatched {
            parts.append("\(m) canciones")
            if let miss = source.lastMissed, miss > 0 { parts.append("\(miss) sin match") }
        }
        return parts.joined(separator: " · ")
    }
}
