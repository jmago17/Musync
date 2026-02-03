import SwiftUI

/// Empty state view with illustration and action button
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))

            // Text
            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)

                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(.horizontal, 32)

            // Action Button
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.body.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Predefined Empty States

extension EmptyStateView {
    static var noFavorites: EmptyStateView {
        EmptyStateView(
            icon: "heart.slash",
            title: "Sin favoritos",
            message: "Guarda tus playlists favoritas para acceder a ellas rápidamente"
        )
    }

    static var noHistory: EmptyStateView {
        EmptyStateView(
            icon: "clock.arrow.circlepath",
            title: "Sin historial",
            message: "Aquí aparecerán las sincronizaciones que realices"
        )
    }

    static func noResults(action: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "Sin resultados",
            message: "No se encontraron canciones disponibles en el catálogo US",
            actionTitle: "Intentar de nuevo",
            action: action
        )
    }

    static func error(message: String, action: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "Algo salió mal",
            message: message,
            actionTitle: "Reintentar",
            action: action
        )
    }

    static func noConnection(action: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "wifi.slash",
            title: "Sin conexión",
            message: "Comprueba tu conexión a internet e inténtalo de nuevo",
            actionTitle: "Reintentar",
            action: action
        )
    }
}

// MARK: - Loading State View

struct LoadingStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("Empty States") {
    TabView {
        EmptyStateView.noFavorites
            .tabItem { Label("Favoritos", systemImage: "heart") }

        EmptyStateView.noHistory
            .tabItem { Label("Historial", systemImage: "clock") }

        EmptyStateView.noConnection {}
            .tabItem { Label("Error", systemImage: "wifi.slash") }

        LoadingStateView(message: "Cargando...")
            .tabItem { Label("Loading", systemImage: "arrow.clockwise") }
    }
}
