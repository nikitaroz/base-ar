import Foundation

/// A battery product with real published dimensions. Drives the AR preview mesh.
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
}
