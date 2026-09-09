import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                if store.history.isEmpty {
                    ContentUnavailableView("Sin historial",
                                           systemImage: "clock",
                                           description: Text("Aquí aparecerán tus sincronizaciones."))
                }
                ForEach(store.history) { run in
                    NavigationLink(value: run) {
                        RunRow(run: run)
                    }
                }
            }
            .navigationTitle("Historial")
            .navigationDestination(for: SyncRun.self) { RunDetailView(run: $0) }
        }
    }
}

private struct RunRow: View {
    let run: SyncRun

    var body: some View {
        HStack {
            Image(systemName: run.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(run.failed ? .red : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.targetName).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        if run.failed { return run.errorMessage ?? "Error" }
        var s = "\(run.matched)/\(run.totalTracks) · \(run.date.formatted(.relative(presentation: .named)))"
        let unresolved = run.misses.filter { $0.resolvedSongID == nil }.count
        if unresolved > 0 { s += " · \(unresolved) sin match" }
        return s
    }
}

struct RunDetailView: View {
    @Environment(AppStore.self) private var store
    let run: SyncRun
    @State private var resolving: MissTrack?

    /// Always read the freshest copy so resolved misses update live.
    private var current: SyncRun { store.history.first(where: { $0.id == run.id }) ?? run }

    var body: some View {
        List {
            Section {
                LabeledContent("Destino", value: current.targetName)
                LabeledContent("Modo", value: current.mode.label)
                LabeledContent("Fecha", value: current.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Sincronizadas", value: "\(current.matched)/\(current.totalTracks)")
            }

            if current.failed {
                Section("Error") {
                    Text(current.errorMessage ?? "Error desconocido").foregroundStyle(.red)
                }
            }

            let misses = current.misses
            if !misses.isEmpty {
                Section("Sin match (\(misses.filter { $0.resolvedSongID == nil }.count) pendientes)") {
                    ForEach(misses) { miss in
                        MissRow(miss: miss) {
                            if current.playlistID != nil { resolving = miss }
                        }
                    }
                }
            }

            if let surplus = current.surplus, !surplus.isEmpty {
                Section {
                    ForEach(surplus) { track in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).lineLimit(1)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                } header: {
                    Text("Sobrantes (\(surplus.count))")
                } footer: {
                    Text("Estas canciones están en la playlist pero ya no en el origen. Apple no permite que otra app las quite: bórralas desde la app Música, o convierte el destino en playlist gestionada para que sea automático.")
                }
            }
        }
        .navigationTitle("Detalle")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $resolving) { miss in
            MissResolveSheet(miss: miss, run: current)
        }
    }
}

private struct MissRow: View {
    let miss: MissTrack
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(miss.title).foregroundStyle(.primary).lineLimit(1)
                    Text(miss.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let resolved = miss.resolvedTitle {
                    Label("Añadida", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                        .help(resolved)
                } else {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tint)
                }
            }
        }
        .disabled(miss.resolvedSongID != nil)
    }
}

struct MissResolveSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let miss: MissTrack
    let run: SyncRun

    @State private var results: [CatalogSong] = []
    @State private var loading = true
    @State private var adding: String?

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { ProgressView(); Text("Buscando…") }
                } else if results.isEmpty {
                    ContentUnavailableView("Sin resultados", systemImage: "magnifyingglass")
                }
                ForEach(results) { song in
                    Button {
                        Task {
                            adding = song.id
                            let ok = await store.resolveMiss(miss, with: song, in: run)
                            adding = nil
                            if ok { dismiss() }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).foregroundStyle(.primary).lineLimit(1)
                                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if adding == song.id { ProgressView().controlSize(.small) }
                        }
                    }
                }
            }
            .navigationTitle("Buscar: \(miss.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task {
                results = await store.searchForMiss(miss)
                loading = false
            }
        }
    }
}
