import SwiftUI
import MusicKit

/// Onboarding view for requesting MusicKit permissions
struct OnboardingView: View {
    @StateObject private var musicKitService = MusicKitService.shared
    @State private var isRequesting = false
    @Binding var showOnboarding: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Illustration
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.pink.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)

                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 12) {
                    Text("Bienvenido a MusicRegionSync")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)

                    Text("Sincroniza playlists de Apple Music España a tu cuenta US")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            // Features
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "globe.europe.africa.fill",
                    iconColor: .blue,
                    title: "Accede a playlists españolas",
                    description: "Novedades Viernes, Éxitos España y más"
                )

                FeatureRow(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .green,
                    title: "Sincronización automática",
                    description: "Encuentra las mismas canciones en tu catálogo"
                )

                FeatureRow(
                    icon: "heart.fill",
                    iconColor: .pink,
                    title: "Guarda tus favoritas",
                    description: "Re-sincroniza playlists con un solo toque"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Authorization Button
            VStack(spacing: 16) {
                Button(action: requestAuthorization) {
                    HStack(spacing: 8) {
                        if isRequesting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "music.note")
                        }
                        Text("Conectar con Apple Music")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.pink, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isRequesting)

                Text("Necesitamos acceso a Apple Music para buscar y añadir canciones a tu biblioteca")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }

    private func requestAuthorization() {
        isRequesting = true

        Task {
            let authorized = await musicKitService.requestAuthorization()

            await MainActor.run {
                isRequesting = false

                if authorized {
                    withAnimation {
                        showOnboarding = false
                    }
                }
            }
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - No Subscription View

struct NoSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "music.note.house")
                .font(.system(size: 70))
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Text("Suscripción requerida")
                    .font(.title2.bold())

                Text("Para añadir canciones a tu biblioteca necesitas una suscripción activa a Apple Music")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: openAppleMusicSubscription) {
                    Text("Suscribirse a Apple Music")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.pink)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button("Continuar sin suscripción") {
                    dismiss()
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func openAppleMusicSubscription() {
        if let url = URL(string: "https://music.apple.com/subscribe") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView(showOnboarding: .constant(true))
}

#Preview("No Subscription") {
    NoSubscriptionView()
}
