import SwiftUI

// MARK: - Error Handling Modifiers

extension View {
    /// Shows an alert for errors
    func errorAlert(
        error: Binding<Error?>,
        buttonTitle: String = "Aceptar"
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )

        return alert(
            "Error",
            isPresented: isPresented,
            presenting: error.wrappedValue
        ) { _ in
            Button(buttonTitle) {
                error.wrappedValue = nil
            }
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    /// Shows an error banner at the top of the view
    func errorBanner(
        message: Binding<String?>,
        type: ErrorBannerType = .error
    ) -> some View {
        ZStack(alignment: .top) {
            self

            if let msg = message.wrappedValue {
                ErrorBannerContent(
                    message: msg,
                    type: type,
                    onDismiss: { message.wrappedValue = nil }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: message.wrappedValue)
            }
        }
    }

    /// Adds haptic feedback on tap
    func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) -> some View {
        self.simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    let generator = UIImpactFeedbackGenerator(style: style)
                    generator.impactOccurred()
                }
        )
    }

    /// Adds notification haptic feedback
    func notificationFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) -> some View {
        self.onAppear {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(type)
        }
    }
}

// MARK: - Error Banner Types

enum ErrorBannerType {
    case error
    case warning
    case success
    case info

    var backgroundColor: Color {
        switch self {
        case .error:
            return .red
        case .warning:
            return .orange
        case .success:
            return .green
        case .info:
            return .blue
        }
    }

    var iconName: String {
        switch self {
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
}

// MARK: - Error Banner Content

private struct ErrorBannerContent: View {
    let message: String
    let type: ErrorBannerType
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.iconName)
                .font(.title3)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.leading)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
        }
        .foregroundColor(.white)
        .padding()
        .background(type.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Loading State Modifier

extension View {
    /// Overlays a loading indicator when loading
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        ZStack {
            self
                .disabled(isLoading)
                .blur(radius: isLoading ? 2 : 0)

            if isLoading {
                LoadingOverlayContent(message: message)
            }
        }
    }
}

private struct LoadingOverlayContent: View {
    let message: String?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Conditional Modifier

extension View {
    /// Applies a modifier conditionally
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Applies a modifier conditionally with an else branch
    @ViewBuilder
    func `if`<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        ifTrue: (Self) -> TrueContent,
        ifFalse: (Self) -> FalseContent
    ) -> some View {
        if condition {
            ifTrue(self)
        } else {
            ifFalse(self)
        }
    }
}

// MARK: - Skeleton Loading

extension View {
    /// Shows a skeleton loading placeholder
    func skeleton(isLoading: Bool) -> some View {
        self.redacted(reason: isLoading ? .placeholder : [])
            .shimmering(active: isLoading)
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.4),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 2)
                        .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                    }
                    .mask(content)
                }
            }
            .onAppear {
                if active {
                    withAnimation(
                        .linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                    ) {
                        phase = 1
                    }
                }
            }
    }
}

extension View {
    func shimmering(active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}
