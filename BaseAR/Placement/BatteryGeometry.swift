import Foundation
import simd

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
    static var workingSpaceWidthMeters: Float { Float(BaseRuleSet.workingSpaceWidthInches) * inchesToMeters }
    static var workingSpaceDepthMeters: Float { Float(BaseRuleSet.workingSpaceDepthInches) * inchesToMeters }

    /// Closest point on the selected model's base, not on a fixed Base Core proxy.
    static func nearestBasePoint(
        origin: SIMD3<Float>, yaw: Float, toward target: SIMD3<Float>,
        model: BatteryModel = BatteryCatalog.baseCore
    ) -> SIMD3<Float> {
        let rotation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        let local = rotation.inverse.act(target - origin)
        let clamped = SIMD3<Float>(
            min(max(local.x, -model.widthMeters / 2), model.widthMeters / 2),
            0,
            min(max(local.z, -model.depthMeters / 2), model.depthMeters / 2)
        )
        return origin + rotation.act(clamped)
    }
}
