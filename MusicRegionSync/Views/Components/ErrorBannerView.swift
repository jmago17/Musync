import SwiftUI

/// Banner view for displaying errors and notifications
struct ErrorBannerView: View {
    let message: String
    let type: BannerType
    var onDismiss: (() -> Void)?

    enum BannerType {
        case error
        case warning
        case success
        case info

        var backgroundColor: Color {
            switch self {
            case .error: return .red
            case .warning: return .orange
            case .success: return .green
            case .info: return .blue
            }
        }

        var iconName: String {
            switch self {
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .success: return "checkmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.iconName)
                .font(.title3)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.leading)

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
            }
        }
        .foregroundColor(.white)
        .padding()
        .background(type.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String
    let icon: String
    var iconColor: Color = .white

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(iconColor)

            Text(message)
                .font(.subheadline.weight(.medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

// MARK: - Banner Container Modifier

struct BannerContainerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let type: ErrorBannerView.BannerType
    var duration: TimeInterval = 4

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if isPresented {
                ErrorBannerView(
                    message: message,
                    type: type,
                    onDismiss: { isPresented = false }
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                        withAnimation {
                            isPresented = false
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.3), value: isPresented)
    }
}

extension View {
    func banner(
        isPresented: Binding<Bool>,
        message: String,
        type: ErrorBannerView.BannerType = .error,
        duration: TimeInterval = 4
    ) -> some View {
        modifier(BannerContainerModifier(
            isPresented: isPresented,
            message: message,
            type: type,
            duration: duration
        ))
    }
}

// MARK: - Preview

#Preview("Banners") {
    VStack(spacing: 20) {
        ErrorBannerView(
            message: "No se pudo cargar la playlist",
            type: .error
        ) {}

        ErrorBannerView(
            message: "Algunas canciones no están disponibles",
            type: .warning
        ) {}

        ErrorBannerView(
            message: "45 canciones añadidas correctamente",
            type: .success
        ) {}

        ErrorBannerView(
            message: "Sincronización en progreso...",
            type: .info
        ) {}

        ToastView(
            message: "Copiado al portapapeles",
            icon: "doc.on.clipboard"
        )
    }
    .padding()
}
