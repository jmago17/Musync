import SwiftUI
import SwiftData

/// View for displaying sync history
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = HistoryViewModel()

    @Query(sort: \SyncHistory.date, order: .reverse)
    private var history: [SyncHistory]

    var body: some View {
        Group {
            if history.isEmpty {
                EmptyStateView.noHistory
            } else {
                historyList
            }
        }
        .navigationTitle("Historial")
        .toolbar {
            if !history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            viewModel.showClearConfirmation = true
                        } label: {
                            Label("Borrar todo", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationDestination(isPresented: $viewModel.navigateToDetail) {
            if let selected = viewModel.selectedHistory {
                SyncDetailView(history: selected)
            }
        }
        .navigationDestination(isPresented: $viewModel.navigateToSync) {
            if let data = viewModel.playlistToSync {
                SyncView(playlistData: data)
            }
        }
        .refreshable {
            await viewModel.refresh(context: modelContext)
        }
        .alert("Borrar historial", isPresented: $viewModel.showClearConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar todo", role: .destructive) {
                viewModel.clearAllHistory(context: modelContext)
            }
        } message: {
            Text("Se eliminarán todas las entradas del historial. Esta acción no se puede deshacer.")
        }
        .banner(
            isPresented: $viewModel.showError,
            message: viewModel.errorMessage ?? "",
            type: .error
        )
        .onAppear {
            viewModel.loadHistory(context: modelContext)
        }
        .onChange(of: viewModel.navigateToDetail) { _, newValue in
            if !newValue {
                viewModel.resetNavigation()
            }
        }
        .onChange(of: viewModel.navigateToSync) { _, newValue in
            if !newValue {
                viewModel.resetNavigation()
            }
        }
    }

    // MARK: - History List

    private var historyList: some View {
        List {
            ForEach(groupedDates, id: \.self) { date in
                Section(header: Text(formatSectionDate(date))) {
                    ForEach(entriesForDate(date)) { entry in
                        HistoryRowView(entry: entry) {
                            viewModel.viewDetail(entry)
                        } onRepeat: {
                            Task { await viewModel.repeatSync(entry) }
                        }
                    }
                    .onDelete { offsets in
                        deleteEntries(at: offsets, for: date)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Grouping

    private var groupedDates: [Date] {
        let grouped = Dictionary(grouping: history) { entry in
            Calendar.current.startOfDay(for: entry.date)
        }
        return grouped.keys.sorted(by: >)
    }

    private func entriesForDate(_ date: Date) -> [SyncHistory] {
        history.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Hoy"
        } else if calendar.isDateInYesterday(date) {
            return "Ayer"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.locale = Locale(identifier: "es_ES")
            return formatter.string(from: date)
        }
    }

    private func deleteEntries(at offsets: IndexSet, for date: Date) {
        let entriesForThisDate = entriesForDate(date)
        for index in offsets {
            viewModel.deleteEntry(entriesForThisDate[index], context: modelContext)
        }
    }
}

// MARK: - History Row View

private struct HistoryRowView: View {
    let entry: SyncHistory
    let onDetail: () -> Void
    let onRepeat: () -> Void

    var body: some View {
        Button(action: onDetail) {
            HStack(spacing: 12) {
                // Status Icon
                Image(systemName: entry.status.iconName)
                    .font(.title2)
                    .foregroundColor(statusColor)
                    .frame(width: 40)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.sourcePlaylistName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text("→ \(entry.destinationPlaylistName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Text(entry.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Time
                Text(formatTime(entry.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                // Delete handled by parent
            } label: {
                Label("Eliminar", systemImage: "trash")
            }

            Button {
                onRepeat()
            } label: {
                Label("Repetir", systemImage: "arrow.counterclockwise")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                onDetail()
            } label: {
                Label("Ver detalle", systemImage: "info.circle")
            }

            Button {
                onRepeat()
            } label: {
                Label("Repetir sincronización", systemImage: "arrow.counterclockwise")
            }

            Divider()

            Button(role: .destructive) {
                // Delete action
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .completed: return .green
        case .partial: return .orange
        case .failed: return .red
        case .inProgress: return .blue
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("History") {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(DataController.previewContainer())
}

#Preview("History Empty") {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(for: SyncHistory.self, inMemory: true)
}
