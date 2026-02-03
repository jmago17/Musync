import SwiftUI
import SwiftData
import MusicKit

/// Main application entry point
@main
struct MusicRegionSyncApp: App {
    @StateObject private var musicKitService = MusicKitService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared

    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView(showOnboarding: $showOnboarding)
                .environmentObject(musicKitService)
                .environmentObject(networkMonitor)
                .task {
                    await checkAuthorization()
                }
        }
        .modelContainer(DataController.shared.container)
    }

    private func checkAuthorization() async {
        await musicKitService.checkAuthorizationStatus()

        if !musicKitService.isAuthorized {
            await MainActor.run {
                showOnboarding = true
            }
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject private var musicKitService: MusicKitService
    @Binding var showOnboarding: Bool

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Inicio", systemImage: "house.fill")
                }

            FavoritesView()
                .tabItem {
                    Label("Favoritos", systemImage: "heart.fill")
                }

            HistoryView()
                .tabItem {
                    Label("Historial", systemImage: "clock.fill")
                }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(showOnboarding: $showOnboarding)
        }
        .onChange(of: musicKitService.isAuthorized) { _, isAuthorized in
            if isAuthorized {
                showOnboarding = false
            }
        }
    }
}

// MARK: - App Delegate Adapter

/// Handles app lifecycle events if needed
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }
}

// MARK: - Preview

#Preview("App") {
    ContentView(showOnboarding: .constant(false))
        .environmentObject(MusicKitService.shared)
        .environmentObject(NetworkMonitor.shared)
        .modelContainer(DataController.previewContainer())
}
