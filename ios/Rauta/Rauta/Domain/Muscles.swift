import Foundation

/// The eighteen muscles the anatomy map and the training engine share.
nonisolated enum MuscleId: String, Codable, CaseIterable, Hashable, Sendable {
    case trapezius
    case deltoids
    case chest
    case upperBack = "upper-back"
    case serratus
    case biceps
    case triceps
    case forearm
    case abs
    case obliques
    case lowerBack = "lower-back"
    case gluteal
    case quadriceps
    case hamstring
    case adductors
    case hipFlexors = "hip-flexors"
    case calves
    case tibialis
}

nonisolated extension MuscleId {
    /// Display name, as the body map and every muscle list render it.
    var label: String {
        switch self {
        case .trapezius: return "Traps"
        case .deltoids: return "Shoulders"
        case .chest: return "Chest"
        case .upperBack: return "Upper back"
        case .serratus: return "Serratus"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearm: return "Forearms"
        case .abs: return "Abs"
        case .obliques: return "Obliques"
        case .lowerBack: return "Lower back"
        case .gluteal: return "Glutes"
        case .quadriceps: return "Quads"
        case .hamstring: return "Hamstrings"
        case .adductors: return "Adductors"
        case .hipFlexors: return "Hip flexors"
        case .calves: return "Calves"
        case .tibialis: return "Shins"
        }
    }
}
