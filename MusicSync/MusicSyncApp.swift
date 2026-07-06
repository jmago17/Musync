import SwiftUI

@main
struct MusicSyncApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { store.refreshAuthStatus() }
        }
    }
}
