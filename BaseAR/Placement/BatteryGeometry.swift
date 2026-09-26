import Foundation

/// Base Core placeholder size for this milestone: 30.68 in W × 35.9 in H × 22 in D.
/// The planning pad uses the published 3 ft × 3 ft footprint from `BaseRuleSet`.
enum BatteryGeometry {
    static let widthInches: Float = 30.68
    static let heightInches: Float = 35.9
    static let depthInches: Float = 22

    static let inchesToMeters: Float = 0.0254
    static let feetToMeters: Float = 0.3048

    static var widthMeters: Float { widthInches * inchesToMeters }
    static var heightMeters: Float { heightInches * inchesToMeters }
    static var depthMeters: Float { depthInches * inchesToMeters }
    static var footprintMeters: Float { Float(BaseRuleSet.footprintSideFeet) * feetToMeters }
}
