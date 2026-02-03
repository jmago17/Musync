import Foundation

/// Represents the overall status of a synchronization operation
enum SyncStatus: String, Codable, CaseIterable {
    case completed = "completed"
    case partial = "partial"
    case failed = "failed"
    case inProgress = "inProgress"

    var displayName: String {
        switch self {
        case .completed:
            return "Completado"
        case .partial:
            return "Parcial"
        case .failed:
            return "Error"
        case .inProgress:
            return "En progreso"
        }
    }

    var iconName: String {
        switch self {
        case .completed:
            return "checkmark.circle.fill"
        case .partial:
            return "exclamationmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .inProgress:
            return "arrow.triangle.2.circlepath"
        }
    }

    var color: String {
        switch self {
        case .completed:
            return "green"
        case .partial:
            return "orange"
        case .failed:
            return "red"
        case .inProgress:
            return "blue"
        }
    }
}

/// Represents the match status of an individual song during sync
enum SongMatchStatus: String, Codable, CaseIterable {
    case matched = "matched"           // Found via ISRC
    case matchedByTitle = "matchedByTitle"  // Found via title+artist fallback
    case notFound = "notFound"         // Not available in target storefront
    case pending = "pending"           // Not yet processed

    var displayName: String {
        switch self {
        case .matched:
            return "Disponible"
        case .matchedByTitle:
            return "Encontrada por título"
        case .notFound:
            return "No disponible"
        case .pending:
            return "Pendiente"
        }
    }

    var iconName: String {
        switch self {
        case .matched:
            return "checkmark.circle.fill"
        case .matchedByTitle:
            return "exclamationmark.triangle.fill"
        case .notFound:
            return "xmark.circle.fill"
        case .pending:
            return "clock.fill"
        }
    }
}
