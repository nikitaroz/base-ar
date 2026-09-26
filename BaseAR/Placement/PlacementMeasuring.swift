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

/// Coarse label for one reconstructed face. Door and window count as wall; ceiling is kept separate so a porch roof is not an obstacle.
enum MeshSurfaceClass: UInt8, Sendable, Equatable {
    case wall
    case floor
    case ceiling
    case other
}

/// One classified face, reduced to a world point and its normal. Not a raw vertex.
struct ClassifiedMeshSample: Sendable, Equatable {
    var faceClass: MeshSurfaceClass
    var point: SIMD3<Float>
    var normal: SIMD3<Float>
}

/// The 1 ft check's chosen hit. Estimated planes are never represented here.
struct WallClearanceHit: Sendable, Equatable {
    var distanceFeet: Double
    var edge: SIMD3<Float>
    var wallPoint: SIMD3<Float>
    /// Horizontal unit normal of the wall face, pointing with the surface.
    var normal: SIMD3<Float>
    var method: MeasurementCaptureMethod
}

/// Placement of the transfer-switch reservation, for the preview box and the occupancy test.
struct TransferSwitchBox: Sendable, Equatable {
    var center: SIMD3<Float>
    var wallPoint: SIMD3<Float>
    var along: SIMD3<Float>
    var up: SIMD3<Float>
    var normal: SIMD3<Float>
    var alongMeters: Float
    var heightMeters: Float
    var outMeters: Float
}

/// Space reserved on the wall beside the meter: 13 in wide, about 3 ft tall, 30 in out from the wall.
enum TransferSwitchReservation {
    static let widthInches: Float = 13
    static let alongWallMeters: Float = widthInches * BatteryGeometry.inchesToMeters
    static let heightMeters: Float = 3 * BatteryGeometry.feetToMeters
    static let outFromWallMeters: Float = 30 * BatteryGeometry.inchesToMeters
}

struct PlacementSceneSnapshot: Sendable, Equatable {
    var batteryPosition: PlacementAnchor?
    var batteryYawRadians: Float = 0
    var meterPosition: PlacementAnchor?
    /// Wall hit at the meter itself, when the user has tapped the meter on a vertical plane. Y drives meter height.
    var meterWallPosition: PlacementAnchor?
    /// Unit normal of the vertical plane the meter wall hit landed on. Same-wall check compares this with the panel's wall normal.
    var meterWallNormal: PlacementAnchor?
    var panelPosition: PlacementAnchor?
    var panelWallPosition: PlacementAnchor?
    var panelWallNormal: PlacementAnchor?
    var gasMeterPosition: PlacementAnchor?
    var verticalPlanes: [PlaneSample] = []
    var lidarMeshAvailable: Bool = false
    /// Classified face samples near the battery, meter, or working space.
    var classifiedMesh: [ClassifiedMeshSample] = []
    /// Rounded automatic wall clearance so the placement screen refreshes when the scan changes.
    var automaticWallClearanceFeet: Double?
    var confirmedMeasurements: [ConfirmedPlacementMeasurement] = []
    var footprintIsClear: Bool?
    var frontWorkingSpaceIsClear: Bool?
    var transferSwitchClearanceObserved: Bool?
    /// Which side of the meter, facing the wall, holds the transfer-switch reservation.
    var transferSwitchOnLeft: Bool = true
    var meterAndPanelShareWall: Bool?
    var workingSpacePosition: PlacementAnchor?
    var workingSpaceYawRadians: Float = 0
    var draftMeasurementStart: MeasurementEndpoint?
    var draftMeasurementEnd: MeasurementEndpoint?

    var hasPlacedContent: Bool {
        batteryPosition != nil || meterPosition != nil || gasMeterPosition != nil || panelPosition != nil
            || !confirmedMeasurements.isEmpty || workingSpacePosition != nil
            || footprintIsClear != nil || frontWorkingSpaceIsClear != nil
            || transferSwitchClearanceObserved != nil || meterAndPanelShareWall != nil
    }
}

struct PlacementMeasurements: Sendable, Equatable {
    var batteryPlaced: Bool
    var meterMarked: Bool
    var gasMeterMarked: Bool
    var panelMarked: Bool
    var lidarMeshAvailable: Bool
    var distanceToMeterFeet: Double?
    var distanceToWallFeet: Double?
    var distanceToGasMeterFeet: Double?
    var meterHeightFeet: Double?
    var meterAndPanelSameWall: Bool?
    var footprintIsClear: Bool?
    var batteryPosition: PlacementAnchor?
    var meterPosition: PlacementAnchor?
    var panelPosition: PlacementAnchor?
    var gasMeterPosition: PlacementAnchor?
    var batteryYawRadians: Float?
    var confirmedMeasurements: [ConfirmedPlacementMeasurement]
    var frontWorkingSpaceIsClear: Bool?
    var transferSwitchClearanceObserved: Bool?
    var meterAndPanelShareWall: Bool?
    var workingSpacePosition: PlacementAnchor?
    var workingSpaceYawRadians: Float?
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
        updated.panelMarked = measured.panelMarked
        updated.lidarMeshAvailable = measured.lidarMeshAvailable
        updated.distanceToMeterFeet = measured.distanceToMeterFeet
        updated.distanceToWallFeet = measured.distanceToWallFeet
        updated.distanceToGasMeterFeet = measured.distanceToGasMeterFeet
        updated.meterHeightFeet = measured.meterHeightFeet
        updated.meterAndPanelSameWall = measured.meterAndPanelSameWall
        // A missing mesh leaves the previous measured result in place. Yes/No answers are not a measurement.
        if let footprint = measured.footprintIsClear {
            updated.footprintIsClear = footprint
        }
        updated.batteryPosition = measured.batteryPosition
        updated.meterPosition = measured.meterPosition
        updated.panelPosition = measured.panelPosition
        updated.gasMeterPosition = measured.gasMeterPosition
        updated.batteryYawRadians = measured.batteryYawRadians
        updated.confirmedMeasurements = measured.confirmedMeasurements
        if let working = measured.frontWorkingSpaceIsClear {
            updated.frontWorkingSpaceIsClear = working
        }
        if let transfer = measured.transferSwitchClearanceObserved {
            updated.transferSwitchClearanceObserved = transfer
        }
        updated.meterAndPanelShareWall = measured.meterAndPanelShareWall
        updated.workingSpacePosition = measured.workingSpacePosition
        updated.workingSpaceYawRadians = measured.workingSpaceYawRadians
        return updated
    }
}

struct CorePlacementMeasurer: PlacementMeasuring {
    /// Extra margin around a detected wall patch before it counts as "the" wall.
    var planeMarginMeters: Float = 0.5
    /// Same-direction wall normals, about 15°. Opposite walls are below zero and fail.
    var wallSameDirectionDotThreshold: Float = 0.96
    /// How far apart two wall taps may be, along the normal, and still be one wall.
    var sameWallPlaneToleranceMeters: Float = 0.30

    func measure(_ snapshot: PlacementSceneSnapshot) -> PlacementMeasurements {
        let meterFeet = confirmed(.batteryToMeter, in: snapshot)?.distanceFeet
            ?? horizontalFeet(snapshot.batteryPosition, snapshot.meterPosition)
        let gasFeet = confirmed(.batteryToGasMeter, in: snapshot)?.distanceFeet
            ?? horizontalFeet(snapshot.batteryPosition, snapshot.gasMeterPosition)
        let wallFeet = wallDistanceFeet(snapshot)
        let heightFeet = meterHeightFeet(snapshot) ?? confirmed(.meterHeight, in: snapshot)?.distanceFeet
        let sameWall = meterAndPanelSameWall(snapshot)
        let footprint = footprintClearance(snapshot)
        let working = workingSpaceClearance(snapshot)
        let transfer = transferSwitchClearance(snapshot)
        return PlacementMeasurements(
            batteryPlaced: snapshot.batteryPosition != nil,
            meterMarked: snapshot.meterPosition != nil,
            gasMeterMarked: snapshot.gasMeterPosition != nil,
            panelMarked: snapshot.panelPosition != nil,
            lidarMeshAvailable: snapshot.lidarMeshAvailable,
            distanceToMeterFeet: meterFeet,
            distanceToWallFeet: wallFeet,
            distanceToGasMeterFeet: gasFeet,
            meterHeightFeet: heightFeet,
            meterAndPanelSameWall: sameWall,
            footprintIsClear: footprint,
            batteryPosition: snapshot.batteryPosition,
            meterPosition: snapshot.meterPosition,
            panelPosition: snapshot.panelPosition,
            gasMeterPosition: snapshot.gasMeterPosition,
            batteryYawRadians: snapshot.batteryPosition == nil ? nil : snapshot.batteryYawRadians,
            confirmedMeasurements: snapshot.confirmedMeasurements,
            frontWorkingSpaceIsClear: working,
            transferSwitchClearanceObserved: transfer,
            meterAndPanelShareWall: sameWall,
            workingSpacePosition: snapshot.workingSpacePosition,
            workingSpaceYawRadians: snapshot.workingSpacePosition == nil ? nil : snapshot.workingSpaceYawRadians
        )
    }

    /// Live 1 ft check. Classified wall faces win; a real vertical plane is the fallback. Estimated-plane tape never counts.
    func wallClearance(in snapshot: PlacementSceneSnapshot) -> WallClearanceHit? {
        guard let battery = snapshot.batteryPosition?.simd else { return nil }
        if let meshHit = meshWallHit(battery: battery, yaw: snapshot.batteryYawRadians, samples: snapshot.classifiedMesh) {
            return meshHit
        }
        return planeWallHit(battery: battery, yaw: snapshot.batteryYawRadians, planes: snapshot.verticalPlanes)
    }

    func transferSwitchBox(in snapshot: PlacementSceneSnapshot) -> TransferSwitchBox? {
        guard let frame = transferSwitchFrame(snapshot) else { return nil }
        return TransferSwitchBox(
            center: frame.center,
            wallPoint: frame.wallPoint,
            along: frame.along,
            up: frame.up,
            normal: frame.normal,
            alongMeters: frame.halfAlong * 2,
            heightMeters: frame.halfHeight * 2,
            outMeters: frame.halfOut * 2
        )
    }

    private func confirmed(_ kind: PlacementMeasurementKind, in snapshot: PlacementSceneSnapshot) -> ConfirmedPlacementMeasurement? {
        snapshot.confirmedMeasurements.first { $0.kind == kind }
    }

    /// Automatic wall clearance wins. A saved estimated-plane tape does not fill in when the scan has no real wall.
    private func wallDistanceFeet(_ snapshot: PlacementSceneSnapshot) -> Double? {
        if let automatic = wallClearance(in: snapshot)?.distanceFeet {
            return automatic
        }
        guard let saved = confirmed(.batteryToWall, in: snapshot), saved.captureMethod != .estimatedPlane else {
            return nil
        }
        return saved.distanceFeet
    }

    /// Pad clearance from classified faces. Floor and the wall the battery sits against are not obstacles. No mesh stays unknown.
    private func footprintClearance(_ snapshot: PlacementSceneSnapshot) -> Bool? {
        guard snapshot.lidarMeshAvailable, let battery = snapshot.batteryPosition?.simd else { return nil }
        guard hasScan(snapshot.classifiedMesh, around: battery, radius: 2) else { return nil }
        let host = hostWall(
            battery: battery,
            yaw: snapshot.batteryYawRadians,
            samples: snapshot.classifiedMesh,
            planes: snapshot.verticalPlanes
        )
        let blocked = snapshot.classifiedMesh.contains { sample in
            guard occupiesVolume(sample, ignoring: host) else { return false }
            return point(
                sample.point,
                isInsideBoxAt: battery,
                yaw: snapshot.batteryYawRadians,
                halfWidth: BatteryGeometry.footprintMeters / 2,
                halfDepth: BatteryGeometry.footprintMeters / 2,
                minHeight: 0.02,
                maxHeight: BatteryGeometry.heightMeters
            )
        }
        return !blocked
    }

    /// The positioned 30 × 36 in slab. Floor and the host wall are ignored. Yes/No is not consulted.
    private func workingSpaceClearance(_ snapshot: PlacementSceneSnapshot) -> Bool? {
        guard snapshot.lidarMeshAvailable,
              let battery = snapshot.batteryPosition?.simd,
              let center = snapshot.workingSpacePosition?.simd else { return nil }
        guard hasScan(snapshot.classifiedMesh, around: center, radius: 2) else { return nil }
        let host = hostWall(
            battery: battery,
            yaw: snapshot.batteryYawRadians,
            samples: snapshot.classifiedMesh,
            planes: snapshot.verticalPlanes
        )
        let meterWall = wallFrame(position: snapshot.meterWallPosition, normal: snapshot.meterWallNormal)
        let blocked = snapshot.classifiedMesh.contains { sample in
            guard occupiesVolume(sample, ignoring: host, alsoIgnoring: meterWall) else { return false }
            return point(
                sample.point,
                isInsideBoxAt: center,
                yaw: snapshot.workingSpaceYawRadians,
                halfWidth: BatteryGeometry.workingSpaceWidthMeters / 2,
                halfDepth: BatteryGeometry.workingSpaceDepthMeters / 2,
                minHeight: 0.05,
                maxHeight: 2
            )
        }
        return !blocked
    }

    /// 13 in wide by about 3 ft tall beside the meter, 30 in out from the wall. No mesh stays unknown.
    private func transferSwitchClearance(_ snapshot: PlacementSceneSnapshot) -> Bool? {
        guard snapshot.lidarMeshAvailable, let frame = transferSwitchFrame(snapshot) else { return nil }
        guard hasScan(snapshot.classifiedMesh, around: frame.center, radius: 2) else { return nil }
        let mounting = WallFrame(point: frame.wallPoint, normal: frame.normal)
        let blocked = snapshot.classifiedMesh.contains { sample in
            guard occupiesVolume(sample, ignoring: mounting) else { return false }
            let delta = sample.point - frame.center
            return abs(simd_dot(delta, frame.along)) <= frame.halfAlong
                && abs(simd_dot(delta, frame.up)) <= frame.halfHeight
                && abs(simd_dot(delta, frame.normal)) <= frame.halfOut
        }
        return !blocked
    }

    private func horizontalFeet(_ origin: PlacementAnchor?, _ target: PlacementAnchor?) -> Double? {
        guard let origin, let target else { return nil }
        let dx = Double(origin.x - target.x)
        let dz = Double(origin.z - target.z)
        return (dx * dx + dz * dz).squareRoot() / 0.3048
    }

    private func meterHeightFeet(_ snapshot: PlacementSceneSnapshot) -> Double? {
        guard let ground = snapshot.meterPosition, let wall = snapshot.meterWallPosition else { return nil }
        let deltaMeters = Double(wall.y - ground.y)
        guard deltaMeters > 0 else { return nil }
        return deltaMeters / 0.3048
    }

    /// Both taps must face the same way and lie on nearly the same plane. Opposite walls fail. Yes/No is not a fallback.
    private func meterAndPanelSameWall(_ snapshot: PlacementSceneSnapshot) -> Bool? {
        guard let meterNormal = unit(snapshot.meterWallNormal?.simd ?? .zero),
              let panelNormal = unit(snapshot.panelWallNormal?.simd ?? .zero),
              let meterPoint = snapshot.meterWallPosition?.simd,
              let panelPoint = snapshot.panelWallPosition?.simd else { return nil }
        guard simd_dot(meterNormal, panelNormal) >= wallSameDirectionDotThreshold else { return false }
        let separation = abs(simd_dot(panelPoint - meterPoint, meterNormal))
        return separation <= sameWallPlaneToleranceMeters
    }

    private func meshWallHit(battery: SIMD3<Float>, yaw: Float, samples: [ClassifiedMeshSample]) -> WallClearanceHit? {
        var best: (clearance: Float, edge: SIMD3<Float>, wallPoint: SIMD3<Float>, normal: SIMD3<Float>)?
        for sample in samples where sample.faceClass == .wall {
            guard let normal = horizontalUnit(sample.normal) else { continue }
            let dx = sample.point.x - battery.x
            let dz = sample.point.z - battery.z
            guard dx * dx + dz * dz <= 25 else { continue }
            let height = sample.point.y - battery.y
            guard height > -0.4, height < 2.5 else { continue }
            let edge = BatteryGeometry.nearestBasePoint(origin: battery, yaw: yaw, toward: sample.point)
            let signed = simd_dot(edge - sample.point, normal)
            let inPlane = (edge - sample.point) - normal * signed
            let along = simd_length(SIMD3(inPlane.x, 0, inPlane.z))
            guard along < 0.75 else { continue }
            let clearance = abs(signed)
            if clearance < (best?.clearance ?? .greatestFiniteMagnitude) {
                best = (clearance, edge, edge - normal * signed, normal)
            }
        }
        guard let best else { return nil }
        return WallClearanceHit(
            distanceFeet: Double(best.clearance) / 0.3048,
            edge: best.edge,
            wallPoint: best.wallPoint,
            normal: best.normal,
            method: .lidarMesh
        )
    }

    /// Horizontal clearance from the battery's nearest bottom corner to a detected vertical plane.
    /// Walls are treated as reaching the ground: people usually scan a wall at chest height, well above the battery's base.
    private func planeWallHit(battery: SIMD3<Float>, yaw: Float, planes: [PlaneSample]) -> WallClearanceHit? {
        let corners = bottomCorners(origin: battery, yaw: yaw)
        let up = SIMD3<Float>(0, 1, 0)
        var best: (clearance: Float, edge: SIMD3<Float>, wallPoint: SIMD3<Float>, normal: SIMD3<Float>)?
        for plane in planes {
            guard plane.width >= 0.2, plane.length >= 0.2 else { continue }
            guard let xAxis = unit(plane.xAxis), let normal = unit(plane.normal), let zAxis = unit(plane.zAxis) else {
                continue
            }
            guard abs(normal.y) < 0.5,
                  let flatNormal = unit(SIMD3(normal.x, 0, normal.z)),
                  let along = unit(simd_cross(up, flatNormal)) else { continue }
            let halfRun = abs(simd_dot(xAxis, along)) * plane.width / 2 + abs(simd_dot(zAxis, along)) * plane.length / 2
            for corner in corners {
                let delta = corner - plane.center
                guard abs(simd_dot(delta, along)) <= halfRun + planeMarginMeters else { continue }
                let signed = simd_dot(delta, flatNormal)
                let clearance = abs(signed)
                if clearance < (best?.clearance ?? .greatestFiniteMagnitude) {
                    best = (clearance, corner, corner - flatNormal * signed, flatNormal)
                }
            }
        }
        guard let best else { return nil }
        return WallClearanceHit(
            distanceFeet: Double(best.clearance) / 0.3048,
            edge: best.edge,
            wallPoint: best.wallPoint,
            normal: best.normal,
            method: .existingPlane
        )
    }

    private struct WallFrame {
        var point: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    private struct TransferFrame {
        var center: SIMD3<Float>
        var wallPoint: SIMD3<Float>
        var along: SIMD3<Float>
        var up: SIMD3<Float>
        var normal: SIMD3<Float>
        var halfAlong: Float
        var halfHeight: Float
        var halfOut: Float
    }

    /// Nearest wall face, or the nearest detected plane when the mesh has no wall label.
    /// Occupancy ignores faces on this plane so the wall itself is not an obstacle.
    private func hostWall(battery: SIMD3<Float>, yaw: Float, samples: [ClassifiedMeshSample], planes: [PlaneSample]) -> WallFrame? {
        if let hit = meshWallHit(battery: battery, yaw: yaw, samples: samples) {
            return WallFrame(point: hit.wallPoint, normal: hit.normal)
        }
        if let hit = planeWallHit(battery: battery, yaw: yaw, planes: planes) {
            return WallFrame(point: hit.wallPoint, normal: hit.normal)
        }
        return nil
    }

    private func wallFrame(position: PlacementAnchor?, normal: PlacementAnchor?) -> WallFrame? {
        guard let position, let normal, let flat = horizontalUnit(normal.simd) else { return nil }
        return WallFrame(point: position.simd, normal: flat)
    }

    private func transferSwitchFrame(_ snapshot: PlacementSceneSnapshot) -> TransferFrame? {
        guard let wallPoint = snapshot.meterWallPosition?.simd,
              let outward = horizontalUnit(snapshot.meterWallNormal?.simd ?? .zero) else { return nil }
        let up = SIMD3<Float>(0, 1, 0)
        guard let userRight = unit(simd_cross(outward, up)) else { return nil }
        let side: Float = snapshot.transferSwitchOnLeft ? -1 : 1
        let along = userRight * side
        let halfAlong = TransferSwitchReservation.alongWallMeters / 2
        let halfHeight = TransferSwitchReservation.heightMeters / 2
        let halfOut = TransferSwitchReservation.outFromWallMeters / 2
        var center = wallPoint + along * (halfAlong + 0.08) + outward * halfOut
        if let ground = snapshot.meterPosition?.simd {
            center.y = max(center.y, ground.y + halfHeight)
        }
        return TransferFrame(
            center: center,
            wallPoint: wallPoint,
            along: along,
            up: up,
            normal: outward,
            halfAlong: halfAlong,
            halfHeight: halfHeight,
            halfOut: halfOut
        )
    }

    private func occupiesVolume(_ sample: ClassifiedMeshSample, ignoring host: WallFrame?, alsoIgnoring extra: WallFrame? = nil) -> Bool {
        switch sample.faceClass {
        case .floor, .ceiling: return false
        case .wall, .other: break
        }
        if let host, isOnWall(sample, wall: host) { return false }
        if let extra, isOnWall(sample, wall: extra) { return false }
        return true
    }

    /// A vertical face on the host plane is the wall, even when its label is still unclassified.
    /// Opposite walls fail the plane-distance test. Normal direction may be flipped on one surface, so the dot is unsigned here only.
    private func isOnWall(_ sample: ClassifiedMeshSample, wall: WallFrame) -> Bool {
        guard abs(sample.normal.y) < 0.45, let normal = horizontalUnit(sample.normal) else { return false }
        guard abs(simd_dot(normal, wall.normal)) > 0.85 else { return false }
        return abs(simd_dot(sample.point - wall.point, wall.normal)) < 0.20
    }

    private func hasScan(_ samples: [ClassifiedMeshSample], around point: SIMD3<Float>, radius: Float) -> Bool {
        let limit = radius * radius
        return samples.contains { sample in
            let dx = sample.point.x - point.x
            let dz = sample.point.z - point.z
            return dx * dx + dz * dz <= limit
        }
    }

    private func point(
        _ point: SIMD3<Float>,
        isInsideBoxAt origin: SIMD3<Float>,
        yaw: Float,
        halfWidth: Float,
        halfDepth: Float,
        minHeight: Float,
        maxHeight: Float
    ) -> Bool {
        let height = point.y - origin.y
        guard height >= minHeight, height <= maxHeight else { return false }
        let cosYaw = cos(yaw)
        let sinYaw = sin(yaw)
        let dx = point.x - origin.x
        let dz = point.z - origin.z
        let localX = cosYaw * dx + sinYaw * dz
        let localZ = -sinYaw * dx + cosYaw * dz
        return abs(localX) <= halfWidth && abs(localZ) <= halfDepth
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

    private func horizontalUnit(_ vector: SIMD3<Float>?) -> SIMD3<Float>? {
        guard let vector else { return nil }
        return unit(SIMD3(vector.x, 0, vector.z))
    }

    private func unit(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let length = simd_length(vector)
        guard length > 0.001 else { return nil }
        return vector / length
    }
}

extension PlacementMeasurementKind {
    /// Battery distances start at the battery itself, which a raycast cannot hit, so the app supplies that end.
    var startsAtBattery: Bool { self != .meterHeight }

    /// Meter height is the vertical rise. Battery distances are horizontal, as the siting rules read them.
    func feet(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Double {
        switch self {
        case .meterHeight:
            return Double(abs(end.y - start.y)) / 0.3048
        case .batteryToMeter, .batteryToWall, .batteryToGasMeter:
            let dx = Double(end.x - start.x)
            let dz = Double(end.z - start.z)
            return (dx * dx + dz * dz).squareRoot() / 0.3048
        }
    }
}

extension BatteryGeometry {
    /// Closest point on the battery's base to `target`, on the ground under the battery.
    static func nearestBasePoint(origin: SIMD3<Float>, yaw: Float, toward target: SIMD3<Float>) -> SIMD3<Float> {
        let rotation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        let local = rotation.inverse.act(target - origin)
        let clamped = SIMD3<Float>(
            min(max(local.x, -widthMeters / 2), widthMeters / 2),
            0,
            min(max(local.z, -depthMeters / 2), depthMeters / 2)
        )
        return origin + rotation.act(clamped)
    }
}
