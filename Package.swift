// swift-tools-version: 6.0
import PackageDescription

let package = Package(name: "MusicSyncCore", platforms: [.macOS(.v13)], products: [], targets: [
    .target(name: "MusicSyncCore", path: "MusicSync", exclude: ["Assets.xcassets", "Views", "Intents", "MusicSyncApp.swift", "Info.plist", "Store/AppStore.swift", "Services/AppleMusicClient.swift", "Services/SyncService.swift"], sources: ["Models/Models.swift", "Store/DefaultSources.swift", "Services/SyncAlgorithms.swift", "Services/Syncer.swift", "Services/SourceStore.swift", "Services/CreatedPlaylists.swift"]),
    .testTarget(name: "MusicSyncCoreTests", dependencies: ["MusicSyncCore"], path: "Tests")
])
