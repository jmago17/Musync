import Foundation
import Network
import Combine

/// Monitors network connectivity status
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: ConnectionType = .unknown

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.musicregionsync.networkmonitor")

    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown

        var displayName: String {
            switch self {
            case .wifi:
                return "Wi-Fi"
            case .cellular:
                return "Datos móviles"
            case .ethernet:
                return "Ethernet"
            case .unknown:
                return "Desconocido"
            }
        }
    }

    private init() {
        monitor = NWPathMonitor()

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.updateStatus(with: path)
            }
        }

        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    private func updateStatus(with path: NWPath) {
        isConnected = path.status == .satisfied

        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else {
            connectionType = .unknown
        }
    }

    /// Waits for network connectivity with a timeout
    func waitForConnection(timeout: TimeInterval = 10) async -> Bool {
        if isConnected { return true }

        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if isConnected { return true }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        return isConnected
    }
}

// MARK: - Retry Logic

extension NetworkMonitor {
    /// Executes an async operation with retry logic and exponential backoff
    static func withRetry<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 10.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delay = initialDelay

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Check if it's a network error worth retrying
                if !shouldRetry(error: error) {
                    throw error
                }

                // Don't sleep on the last attempt
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay = min(delay * 2, maxDelay)
                }
            }
        }

        throw lastError ?? NetworkError.maxRetriesExceeded
    }

    private static func shouldRetry(error: Error) -> Bool {
        // Check for URL session errors that indicate network issues
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .timedOut,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost:
                return true
            default:
                return false
            }
        }

        return false
    }

    enum NetworkError: LocalizedError {
        case noConnection
        case maxRetriesExceeded
        case timeout

        var errorDescription: String? {
            switch self {
            case .noConnection:
                return "Sin conexión a internet"
            case .maxRetriesExceeded:
                return "No se pudo completar la operación después de varios intentos"
            case .timeout:
                return "La operación tardó demasiado tiempo"
            }
        }
    }
}
