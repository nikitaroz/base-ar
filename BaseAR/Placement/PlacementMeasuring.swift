import Foundation
import simd

/// A vertical plane copied out of ARKit so measurement code does not keep AR objects.
struct PlaneSample: Sendable, Equatable {
    var id: UUID
    var center: SIMD3<Float>
    var xAxis: SIMD3<Float>
    var normal: SIMD3<Float>
    var zAxis: SIMD3<Float>
    var width: Float
    var length: Float
}

struct PlacementSceneSnapshot: Sendable, Equatable {
    var batteryPosition: PlacementAnchor?
    var batteryYawRadians: Float = 0
    var meterPosition: PlacementAnchor?
    var gasMeterPosition: PlacementAnchor?
    var verticalPlanes: [PlaneSample] = []
    var lidarMeshAvailable: Bool = false

    var hasPlacedContent: Bool {
        batteryPosition != nil || meterPosition != nil || gasMeterPosition != nil
    }
}

struct PlacementMeasurements: Sendable, Equatable {
    var batteryPlaced: Bool
    var meterMarked: Bool
    var gasMeterMarked: Bool
    var lidarMeshAvailable: Bool
    var distanceToMeterFeet: Double?
    var distanceToWallFeet: Double?
    var distanceToGasMeterFeet: Double?
    var batteryPosition: PlacementAnchor?
    var meterPosition: PlacementAnchor?
    var gasMeterPosition: PlacementAnchor?
    var batteryYawRadians: Float?
}

/// AR placement boundary. Turns a scene snapshot into distances the rule set can read.
protocol PlacementMeasuring: Sendable {
    func measure(_ snapshot: PlacementSceneSnapshot) -> PlacementMeasurements
}

extension PlacementMeasuring {
    func applying(_ snapshot: PlacementSceneSnapshot, to placement: PlacementEvidence) -> PlacementEvidence {
        let measured = measure(snapshot)
        var updated = placement
        updated.batteryPlaced = measured.batteryPlaced
        updated.meterMarked = measured.meterMarked
        updated.gasMeterMarked = measured.gasMeterMarked
        updated.lidarMeshAvailable = measured.lidarMeshAvailable
        updated.distanceToMeterFeet = measured.distanceToMeterFeet
        updated.distanceToWallFeet = measured.distanceToWallFeet
        updated.distanceToGasMeterFeet = measured.distanceToGasMeterFeet
        updated.batteryPosition = measured.batteryPosition
        updated.meterPosition = measured.meterPosition
        updated.gasMeterPosition = measured.gasMeterPosition
        updated.batteryYawRadians = measured.batteryYawRadians
        return updated
    }
}

struct CorePlacementMeasurer: PlacementMeasuring {
    /// Extra margin around a detected wall patch before it counts as "the" wall.
    var planeMarginMeters: Float = 0.5

    func measure(_ snapshot: PlacementSceneSnapshot) -> PlacementMeasurements {
        let meterFeet = horizontalFeet(snapshot.batteryPosition, snapshot.meterPosition)
        let gasFeet = horizontalFeet(snapshot.batteryPosition, snapshot.gasMeterPosition)
        let wallFeet = wallClearanceFeet(snapshot)
        return PlacementMeasurements(
            batteryPlaced: snapshot.batteryPosition != nil,
            meterMarked: snapshot.meterPosition != nil,
            gasMeterMarked: snapshot.gasMeterPosition != nil,
            lidarMeshAvailable: snapshot.lidarMeshAvailable,
            distanceToMeterFeet: meterFeet,
            distanceToWallFeet: wallFeet,
            distanceToGasMeterFeet: gasFeet,
            batteryPosition: snapshot.batteryPosition,
            meterPosition: snapshot.meterPosition,
            gasMeterPosition: snapshot.gasMeterPosition,
            batteryYawRadians: snapshot.batteryPosition == nil ? nil : snapshot.batteryYawRadians
        )
    }

    private func horizontalFeet(_ origin: PlacementAnchor?, _ target: PlacementAnchor?) -> Double? {
        guard let origin, let target else { return nil }
        let dx = Double(origin.x - target.x)
        let dz = Double(origin.z - target.z)
        return (dx * dx + dz * dz).squareRoot() / 0.3048
    }

    /// Horizontal clearance from the battery's nearest bottom corner to a vertical plane whose patch runs past that corner.
    /// Walls are treated as reaching the ground: people usually scan a wall at chest height, well above the battery's base.
    private func wallClearanceFeet(_ snapshot: PlacementSceneSnapshot) -> Double? {
        guard let battery = snapshot.batteryPosition else { return nil }
        let corners = bottomCorners(origin: battery.simd, yaw: snapshot.batteryYawRadians)
        let up = SIMD3<Float>(0, 1, 0)
        var bestMeters: Float?
        for plane in snapshot.verticalPlanes {
            guard plane.width >= 0.2, plane.length >= 0.2 else { continue }
            guard let xAxis = unit(plane.xAxis), let normal = unit(plane.normal), let zAxis = unit(plane.zAxis) else {
                continue
            }
            guard abs(normal.y) < 0.5,
                  let flatNormal = unit(SIMD3(normal.x, 0, normal.z)),
                  let along = unit(simd_cross(up, flatNormal)) else { continue }
            // Half the patch's horizontal run along the wall, whichever extent axis is horizontal.
            let halfRun = abs(simd_dot(xAxis, along)) * plane.width / 2 + abs(simd_dot(zAxis, along)) * plane.length / 2
            for corner in corners {
                let delta = corner - plane.center
                guard abs(simd_dot(delta, along)) <= halfRun + planeMarginMeters else { continue }
                let clearance = abs(simd_dot(delta, flatNormal))
                bestMeters = min(bestMeters ?? clearance, clearance)
            }
        }
        guard let bestMeters else { return nil }
        return Double(bestMeters) / 0.3048
    }

    private func bottomCorners(origin: SIMD3<Float>, yaw: Float) -> [SIMD3<Float>] {
        let rotation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        let halfW = BatteryGeometry.widthMeters / 2
        let halfD = BatteryGeometry.depthMeters / 2
        let locals = [
            SIMD3<Float>(halfW, 0, halfD),
            SIMD3<Float>(halfW, 0, -halfD),
            SIMD3<Float>(-halfW, 0, halfD),
            SIMD3<Float>(-halfW, 0, -halfD)
        ]
        return locals.map { origin + rotation.act($0) }
    }

    private func unit(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let length = simd_length(vector)
        guard length > 0.001 else { return nil }
        return vector / length
    }
}
