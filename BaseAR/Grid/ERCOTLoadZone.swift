import Foundation

/// ERCOT settlement-point load zones. Raw values match ERCOT's own codes so JSON payloads stay portable.
enum ERCOTLoadZone: String, Codable, Sendable, CaseIterable {
    case aen = "LZ_AEN"        // Central (Austin, ERCOT Austin Energy)
    case north = "LZ_NORTH"    // Dallas–Fort Worth
    case south = "LZ_SOUTH"    // San Antonio, Corpus Christi
    case houston = "LZ_HOUSTON"
    case west = "LZ_WEST"      // El Paso, west Texas
}

extension ERCOTLoadZone {
    /// Short label for UI copy. Keeps the raw ERCOT code visible so the user can cross-check with public dashboards.
    var displayName: String {
        switch self {
        case .aen: "AEN (Central)"
        case .north: "North"
        case .south: "South"
        case .houston: "Houston"
        case .west: "West"
        }
    }
}
