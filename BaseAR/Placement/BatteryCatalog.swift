import Foundation

/// A battery product with real published dimensions. Chip picker in the AR view swaps between models.
/// Seeded with Base Core; add more entries as we're ready to preview them.
struct BatteryModel: Sendable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var widthInches: Float
    var heightInches: Float
    var depthInches: Float

    var widthMeters: Float { widthInches * BatteryGeometry.inchesToMeters }
    var heightMeters: Float { heightInches * BatteryGeometry.inchesToMeters }
    var depthMeters: Float { depthInches * BatteryGeometry.inchesToMeters }
}

enum BatteryCatalog {
    static let baseCore = BatteryModel(
        id: "base-core",
        displayName: "Base Core",
        widthInches: 30.68,
        heightInches: 35.9,
        depthInches: 22
    )

    // Public spec-sheet dimensions; verify before shipping to a customer demo.
    static let powerwall3 = BatteryModel(
        id: "tesla-powerwall-3",
        displayName: "Powerwall 3",
        widthInches: 24,
        heightInches: 43.25,
        depthInches: 7.6
    )

    static let enphase5P = BatteryModel(
        id: "enphase-iq-5p",
        displayName: "IQ Battery 5P",
        widthInches: 20.47,
        heightInches: 42.13,
        depthInches: 12.6
    )

    static let all: [BatteryModel] = [baseCore, powerwall3, enphase5P]

    static func model(for id: String?) -> BatteryModel {
        guard let id, let match = all.first(where: { $0.id == id }) else { return baseCore }
        return match
    }
}
