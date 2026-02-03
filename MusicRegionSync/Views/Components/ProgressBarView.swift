import SwiftUI

/// Custom progress bar view for sync operations
struct ProgressBarView: View {
    let progress: Double
    var currentItem: String?
    var showPercentage: Bool = true
    var accentColor: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(min(progress, 1.0)), height: 8)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 8)

            // Info Row
            HStack {
                if let currentItem {
                    Text(currentItem)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if showPercentage {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Circular Progress

struct CircularProgressView: View {
    let progress: Double
    var lineWidth: CGFloat = 4
    var size: CGFloat = 50
    var accentColor: Color = .blue

    var body: some View {
        ZStack {
            // Background Circle
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)

            // Progress Circle
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    accentColor,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)

            // Percentage Text
            Text("\(Int(progress * 100))")
                .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Scanning Progress View

struct ScanningProgressView: View {
    let progress: Double
    let currentSong: String?
    let totalSongs: Int
    let processedSongs: Int

    var body: some View {
        VStack(spacing: 20) {
            CircularProgressView(progress: progress, size: 80, accentColor: .blue)

            VStack(spacing: 8) {
                Text("Escaneando canciones...")
                    .font(.headline)

                Text("\(processedSongs) de \(totalSongs)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let currentSong {
                    Text(currentSong)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 250)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Preview

#Preview("Progress Views") {
    VStack(spacing: 30) {
        ProgressBarView(
            progress: 0.65,
            currentItem: "Bad Bunny - Monaco",
            accentColor: .blue
        )
        .padding(.horizontal)

        CircularProgressView(progress: 0.75, size: 80)

        ScanningProgressView(
            progress: 0.45,
            currentSong: "Quevedo - Columbia",
            totalSongs: 50,
            processedSongs: 23
        )
    }
    .padding()
}
