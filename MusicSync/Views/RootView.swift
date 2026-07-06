import SwiftUI
import MusicKit

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.isAuthorized {
                MainTabs()
            } else {
                AuthGateView()
            }
        }
        .animation(.default, value: store.isAuthorized)
    }
}

private struct MainTabs: View {
    var body: some View {
        TabView {
            SourceListView()
                .tabItem { Label("Playlists", systemImage: "music.note.list") }
            HistoryView()
                .tabItem { Label("Historial", systemImage: "clock.arrow.circlepath") }
        }
    }
}

struct AuthGateView: View {
    @Environment(AppStore.self) private var store
    @State private var working = false

    var body: some View {
        ContentUnavailableView {
            Label("Conecta Apple Music", systemImage: "music.note")
        } description: {
            Text(message)
        } actions: {
            if store.authStatus == .denied || store.authStatus == .restricted {
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    working = true
                    Task {
                        await store.requestAuthorization()
                        store.requestNotificationPermission()
                        working = false
                    }
                } label: {
                    if working { ProgressView() } else { Text("Autorizar") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(working)
            }
        }
    }

    private var message: String {
        switch store.authStatus {
        case .denied, .restricted:
            return "El acceso a Apple Music está denegado. Actívalo en Ajustes → MusicSync."
        default:
            return "MusicSync necesita permiso para leer y modificar tu biblioteca de Apple Music. Requiere una suscripción activa."
        }
    }
}
