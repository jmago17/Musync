import SwiftUI

struct SourceEditView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SavedSource
    @State private var lastRun: SyncRun?
    @State private var showPicker = false

    init(source: SavedSource) { _draft = State(initialValue: source) }

    private var progress: SyncProgress? { store.progress[draft.id] }

    /// ¿Puede MusicSync reemplazar el contenido del destino elegido?
    /// Si aún no hay destino (se creará en el primer sync) sí podrá, porque la
    /// habrá creado esta app.
    private var canReplace: Bool {
        guard let id = draft.lastPlaylistID else { return true }
        guard let pl = store.libraryPlaylists.first(where: { $0.id == id }) else { return true }
        return pl.isReplaceable
    }

    var body: some View {
        Form {
            Section("Playlist destino") {
                Button { showPicker = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.targetName.isEmpty ? "Elegir playlist…" : draft.targetName)
                                .foregroundStyle(draft.targetName.isEmpty ? .secondary : .primary)
                            if draft.lastPlaylistID != nil {
                                Text("Vinculada a tu biblioteca")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Section("Modo") {
                Picker("Modo", selection: $draft.mode) {
                    ForEach(SyncMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!canReplace)
                .onChange(of: draft.mode) { store.updateSource(draft) }
                Text(draft.mode.help).font(.caption).foregroundStyle(.secondary)

                if !canReplace, draft.lastPlaylistID != nil {
                    Label("Esta playlist la creaste tú (o la app Música), así que Apple no permite reemplazar su contenido desde otra app. Solo se pueden añadir canciones nuevas.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Origen") {
                Text(draft.sourceURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let at = draft.lastSyncedAt {
                Section("Última sincronización") {
                    LabeledContent("Fecha", value: at.formatted(date: .abbreviated, time: .shortened))
                    if let m = draft.lastMatched {
                        LabeledContent("Canciones", value: "\(m)")
                    }
                    if let miss = draft.lastMissed {
                        LabeledContent("Sin match", value: "\(miss)")
                    }
                }
            }

            Section {
                Button {
                    Task {
                        let run = await store.sync(draft)
                        lastRun = run
                        if let updated = store.binding(for: draft.id) { draft = updated }
                    }
                } label: {
                    if let progress {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(progress.text)
                        }
                    } else {
                        Label("Sincronizar ahora", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(progress != nil)
            }

            if let run = lastRun {
                Section("Resultado") {
                    if run.failed {
                        Label(run.errorMessage ?? "Error", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    } else {
                        Label("\(run.matched)/\(run.totalTracks) sincronizadas",
                              systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                        if !run.misses.isEmpty {
                            NavigationLink("Ver \(run.misses.count) sin match") {
                                RunDetailView(run: run)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(draft.targetName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            PlaylistPickerView(selectedID: Binding(
                get: { draft.lastPlaylistID },
                set: { draft.lastPlaylistID = $0 }
            ), selectedName: $draft.targetName)
        }
        .onChange(of: draft.lastPlaylistID) {
            draft.lastPlaylistName = draft.targetName
            // Si el destino no admite reemplazo, cae a "Añadir" en vez de fallar
            // en mitad del sync.
            if !canReplace { draft.mode = .append }
            store.updateSource(draft)
        }
        .task { await store.loadLibraryPlaylists() }
    }
}

struct AddSourceSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var name = ""
    @State private var targetID: String?
    @State private var mode: SyncMode = .replace
    @State private var probing = false
    @State private var showPicker = false
    @State private var suggestedName = ""
    @State private var error: String?

    private var validURL: Bool { AppleMusicClient.parseSourceURL(url) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("URL de la playlist") {
                    TextField("https://music.apple.com/es/playlist/…", text: $url, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: url) { error = nil }
                    Button {
                        Task {
                            probing = true; error = nil
                            if let t = await store.peekTitle(url: url) {
                                suggestedName = t
                                showPicker = true
                            } else {
                                error = "No pude leer la playlist. Revisa la URL."
                            }
                            probing = false
                        }
                    } label: {
                        if probing { ProgressView() } else { Text("Leer nombre del origen") }
                    }
                    .disabled(!validURL || probing)
                }

                Section("Playlist destino") {
                    Button { showPicker = true } label: {
                        HStack {
                            Text(name.isEmpty ? "Elegir playlist de tu biblioteca…" : name)
                                .foregroundStyle(name.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Text("Elige una playlist existente o crea una nueva desde el selector.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Modo") {
                    Picker("Modo", selection: $mode) {
                        ForEach(SyncMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(mode.help).font(.caption).foregroundStyle(.secondary)
                }

                if let error {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("Añadir playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir") {
                        store.addSource(.init(sourceURL: url,
                                              targetName: name.isEmpty ? "Nueva playlist" : name,
                                              mode: mode,
                                              lastPlaylistID: targetID,
                                              lastPlaylistName: name.isEmpty ? nil : name))
                        dismiss()
                    }
                    .disabled(!validURL || targetID == nil)
                }
            }
            .sheet(isPresented: $showPicker) {
                PlaylistPickerView(selectedID: $targetID,
                                   selectedName: $name,
                                   suggestedName: suggestedName)
            }
        }
    }
}
