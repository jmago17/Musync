import Foundation

extension SavedSource {
    /// Seeded from the original `~/.config/apple-music-sync/playlists.json`.
    static let defaults: [SavedSource] = [
        .init(sourceURL: "https://music.apple.com/es/playlist/disney-essentials/pl.0e2944a3b59d4246be5018c837c6e0ed",
              targetName: "Disney imprescindibles"),
        .init(sourceURL: "https://music.apple.com/es/playlist/metal-español-imprescindibles/pl.2aeb75a066654f508468d8c6a6626920",
              targetName: "Metal en español"),
        .init(sourceURL: "https://music.apple.com/es/playlist/princesas-disney/pl.08cd1b3d5a474cefaa7ae76961e36180",
              targetName: "Princesas Disney para Neia"),
        .init(sourceURL: "https://music.apple.com/es/playlist/rock-espa%C3%B1ol/pl.1075929bcb154ab69cc1a159d3abe548",
              targetName: "Rock en Español"),
        .init(sourceURL: "https://music.apple.com/es/playlist/sol-de-verano/pl.f27ed614acb2429188a9d09f50caa9ff",
              targetName: "Sol de Veraneo"),
        .init(sourceURL: "https://music.apple.com/es/playlist/songs-of-the-summer/pl.34c6bf42a176492abb918edb57b565e9",
              targetName: "Veraneo"),
        .init(sourceURL: "https://music.apple.com/es/playlist/puro-rock/pl.8e3beb1ee7f045e5980c7f8d2cd9c1ef",
              targetName: "¡Puro Rock!"),
    ]
}
