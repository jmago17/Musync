import SwiftUI

/// Selector de playlist destino: en vez de teclear un nombre, el usuario elige
/// una playlist que ya existe en su biblioteca (o crea una nueva desde aquí).
struct PlaylistPickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Id de la playlist seleccionada (nil si aún no hay ninguna).
    @Binding var selectedID: String?
    /// Nombre mostrado, mantenido en sync con la selección.
    @Binding var selectedName: String
    /// Prerrellena el campo "crear nueva" (p. ej. con el título del origen).
    var suggestedName: String = ""

    @State private var search = ""
    @State private var newName = ""
    @State private var creating = false

    private var filtered: [LibraryPlaylist] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return store.libraryPlaylists }
        return store.libraryPlaylists.filter {
            $0.name.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Crear nueva") {
                    HStack {
                        TextField("Nombre de la nueva playlist", text: $newName)
                        Button {
                            // No se crea nada aquí: se registra la intención y la
                            // playlist se crea en el primer sync, ya con canciones.
                            // Así no quedan playlists vacías si te arrepientes.
                            selectedID = nil
                            selectedName = newName.trimmed
                            dismiss()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newName.trimmed.isEmpty)
                    }
                    Text("Se creará en tu biblioteca durante la primera sincronización.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("En tu biblioteca") {
                    if store.isLoadingLibrary && store.libraryPlaylists.isEmpty {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Leyendo tu biblioteca…").foregroundStyle(.secondary)
                        }
                    } else if let err = store.libraryError, store.libraryPlaylists.isEmpty {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                    } else if filtered.isEmpty {
                        Text(search.isEmpty ? "No tienes playlists todavía."
                                            : "Ninguna coincide con «\(search)».")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(filtered) { pl in
                        Button { select(pl) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pl.name)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if !pl.canEdit {
                                        Text("Solo lectura — no se puede modificar")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if !pl.isReplaceable {
                                        Label("Solo permite añadir canciones",
                                              systemImage: "plus.circle")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if pl.id == selectedID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(!pl.canEdit)
                    }
                }
            }
            .searchable(text: $search, prompt: "Buscar playlist")
            .navigationTitle("Playlist destino")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.loadLibraryPlaylists(force: true) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .task {
                await store.loadLibraryPlaylists()
                if newName.isEmpty { newName = suggestedName }
            }
        }
    }

    private func select(_ pl: LibraryPlaylist) {
        selectedID = pl.id
        selectedName = pl.name
        dismiss()
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
