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

/// Coarse label for one reconstructed face. A door counts as wall. A window stays its own class so the cabinet can be checked against it. Ceiling is kept separate so a porch roof is not an obstacle.
enum MeshSurfaceClass: UInt8, Sendable, Equatable {
    case wall
    case floor
    case ceiling
    case window
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
    /// Wall-side proposal shown before Confirm. Measurements for the live preview copy this into `batteryPosition`.
    var suggestedBatteryPosition: PlacementAnchor?
    var suggestedBatteryYawRadians: Float = 0
    var meterPosition: PlacementAnchor?
    /// Wall hit at the meter itself, when the user has tapped the meter on a vertical plane. Y drives meter height.
    var meterWallPosition: PlacementAnchor?
    /// Unit normal of the vertical plane the meter wall hit landed on. Same-wall check compares this with the panel's wall normal.
    var meterWallNormal: PlacementAnchor?
    var panelPosition: PlacementAnchor?
    var panelWallPosition: PlacementAnchor?
    var panelWallNormal: PlacementAnchor?
    /// Which path locked the meter and panel. Nil while that item is not marked.
    var meterLockSource: EquipmentLockSource?
    var panelLockSource: EquipmentLockSource?
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
    /// Half the meter enclosure's width along its wall, from the lock box. Nil until the meter locks.
    var meterHalfWidthMeters: Float?
    /// How the gas-meter mark was made. Nil with no mark.
    var gasMarkSource: GasMarkSource?
    /// The scan's own battery-spot suggestion. Nil until the scan finishes.
    var batterySpot: BatterySpotSummary?

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
    /// False when a classified window overlaps the cabinet on the host wall. Nil until that face has been scanned.
    var clearOfWindows: Bool?
    /// False when the cabinet stands in the meter's or panel's own 30 × 36 in working space. Nil until both are tapped on the wall.
    var keepsEquipmentAccess: Bool?
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
        // A missing mesh leaves the previous measured result in place, but only for the same spot.
        // With a mesh, nil means this spot is not measured, so an old answer must not carry over. Yes/No answers are not a measurement.
        let keepBatteryChecks = !measured.lidarMeshAvailable && measured.batteryPosition == placement.batteryPosition
        updated.footprintIsClear = measured.footprintIsClear ?? (keepBatteryChecks ? placement.footprintIsClear : nil)
        updated.clearOfWindows = measured.clearOfWindows ?? (keepBatteryChecks ? placement.clearOfWindows : nil)
        updated.keepsEquipmentAccess = measured.keepsEquipmentAccess
        updated.batteryPosition = measured.batteryPosition
        updated.meterPosition = measured.meterPosition
        updated.panelPosition = measured.panelPosition
        updated.gasMeterPosition = measured.gasMeterPosition
        // Provenance, not a measurement: copied from the scene so survey.json says how each spot was chosen.
        updated.meterLockSource = snapshot.meterPosition == nil ? nil : snapshot.meterLockSource
        updated.panelLockSource = snapshot.panelPosition == nil ? nil : snapshot.panelLockSource
        updated.gasMeterMarkSource = snapshot.gasMeterPosition == nil ? nil : snapshot.gasMarkSource
        updated.batterySpot = snapshot.batterySpot
        updated.batteryYawRadians = measured.batteryYawRadians
        updated.confirmedMeasurements = measured.confirmedMeasurements
        let keepWorkingSpace = !measured.lidarMeshAvailable
            && measured.batteryPosition == placement.batteryPosition
            && measured.workingSpacePosition == placement.workingSpacePosition
        updated.frontWorkingSpaceIsClear = measured.frontWorkingSpaceIsClear
            ?? (keepWorkingSpace ? placement.frontWorkingSpaceIsClear : nil)
        // Same keep rule as the footprint, keyed to the meter lock the reservation sits beside.
        let keepTransfer = !measured.lidarMeshAvailable && measured.meterPosition == placement.meterPosition
        updated.transferSwitchClearanceObserved = measured.transferSwitchClearanceObserved
            ?? (keepTransfer ? placement.transferSwitchClearanceObserved : nil)
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
    /// Opposite lock normals whose planes are this close are one wall seen with a flipped normal, or both faces of a
    /// thin wall: unknown, not a conflict.
    var oppositeNormalPlaneToleranceMeters: Float = 0.40
    /// Faces lower than this are grass, mulch, or the rounded seam where wall meets ground, not obstacles.
    var minObstacleHeightMeters: Float = 0.08
    /// One stray face is noise. The snapshot keeps every second face, so two samples is roughly four faces.
    var minObstacleSamples = 2
    /// Share of 10 cm cells under a box that must hold scanned surface before "clear" can mean clear.
    var minScanCoverage: Float = 0.6
    /// The pad and the working space count as blocked only on this many faces spanning this much height. Fewer is
    /// unknown, never clear: three faces smeared along an edge read as a blocked pad on the demo wall. Tune on device.
    var minBlockingSamples = 4
    var minBlockingHeightMeters: Float = 0.10
    /// The meter enclosure's half width along its wall when the lock box gave none. Tune on device.
    static let defaultMeterHalfWidthMeters: Float = 0.23

    func measure(_ snapshot: PlacementSceneSnapshot) -> PlacementMeasurements {
        let meterFeet = confirmed(.batteryToMeter, in: snapshot)?.distanceFeet
            ?? horizontalFeet(snapshot.batteryPosition, snapshot.meterPosition)
        let gasFeet = confirmed(.batteryToGasMeter, in: snapshot)?.distanceFeet
            ?? horizontalFeet(snapshot.batteryPosition, snapshot.gasMeterPosition)
        let wallFeet = wallDistanceFeet(snapshot)
        let heightFeet = meterHeightFeet(snapshot) ?? confirmed(.meterHeight, in: snapshot)?.distanceFeet
        let sameWall = meterAndPanelSameWall(snapshot)
        let scan = ScanIndex(snapshot.classifiedMesh)
        let footprint = footprintClearance(snapshot, scan: scan)
        let windows = clearOfWindows(snapshot)
        let access = keepsEquipmentAccess(snapshot)
        let working = workingSpaceClearance(snapshot, scan: scan)
        let transfer = transferSwitch(snapshot, scan: scan)?.clear
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
            clearOfWindows: windows,
            keepsEquipmentAccess: access,
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

    /// Drawn on the side the check used: the chosen side, or the other side when only that one is clear.
    func transferSwitchBox(in snapshot: PlacementSceneSnapshot) -> TransferSwitchBox? {
        guard let frame = transferSwitch(snapshot, scan: ScanIndex(snapshot.classifiedMesh))?.frame else { return nil }
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

    /// Pad clearance from classified faces. Floor and the wall the battery sits against are not obstacles.
    /// A pad the scan has not mostly covered stays unknown, so a gap in the mesh never reads as clear.
    private func footprintClearance(_ snapshot: PlacementSceneSnapshot, scan: ScanIndex) -> Bool? {
        guard snapshot.lidarMeshAvailable, let battery = snapshot.batteryPosition?.simd else { return nil }
        let host = hostWall(
            battery: battery,
            yaw: snapshot.batteryYawRadians,
            samples: snapshot.classifiedMesh,
            planes: snapshot.verticalPlanes
        )
        let half = BatteryGeometry.footprintMeters / 2
        let coverage = scan.groundCoverage(
            center: battery,
            yaw: snapshot.batteryYawRadians,
            halfWidth: half,
            halfDepth: half,
            inFrontOf: host,
            openSide: battery
        )
        guard coverage >= minScanCoverage else { return nil }
        let hits = snapshot.classifiedMesh.filter { sample in
            guard occupiesVolume(sample, ignoring: host) else { return false }
            return point(
                sample.point,
                isInsideBoxAt: battery,
                yaw: snapshot.batteryYawRadians,
                halfWidth: half,
                halfDepth: half,
                minHeight: minObstacleHeightMeters,
                maxHeight: BatteryGeometry.heightMeters
            )
        }
        return obstacleVerdict(hits)
    }

    /// Blocked needs a real object: `minBlockingSamples` faces spanning `minBlockingHeightMeters` of height. A few
    /// faces smeared along a pad edge (mesh noise, a seam, turf) are not proof of anything, so they give unknown,
    /// never clear. No face at all is clear.
    private func obstacleVerdict(_ hits: [ClassifiedMeshSample]) -> Bool? {
        guard !hits.isEmpty else { return true }
        let heights = hits.map(\.point.y)
        let span = (heights.max() ?? 0) - (heights.min() ?? 0)
        if hits.count >= minBlockingSamples, span >= minBlockingHeightMeters { return false }
        return nil
    }

    /// The cabinet may not stand in the meter's or panel's own 30 × 36 in working space.
    /// One blocked piece of equipment is a conflict. Otherwise both need a wall tap to pass.
    private func keepsEquipmentAccess(_ snapshot: PlacementSceneSnapshot) -> Bool? {
        guard let battery = snapshot.batteryPosition?.simd else { return nil }
        let equipment = [
            wallFrame(position: snapshot.meterWallPosition, normal: snapshot.meterWallNormal),
            wallFrame(position: snapshot.panelWallPosition, normal: snapshot.panelWallNormal)
        ]
        var missing = false
        for frame in equipment {
            guard let frame else {
                missing = true
                continue
            }
            if cabinet(battery: battery, yaw: snapshot.batteryYawRadians, blocksAccessTo: frame) { return false }
        }
        return missing ? nil : true
    }

    private func cabinet(battery: SIMD3<Float>, yaw: Float, blocksAccessTo equipment: WallFrame) -> Bool {
        guard let along = unit(simd_cross(equipment.normal, SIMD3(0, 1, 0))) else { return false }
        let out = simd_dot(battery - equipment.point, equipment.normal) >= 0 ? equipment.normal : -equipment.normal
        let corners = bottomCorners(origin: battery, yaw: yaw)
        let alongs = corners.map { simd_dot($0 - equipment.point, along) }
        let outs = corners.map { simd_dot($0 - equipment.point, out) }
        let halfWidth = BatteryGeometry.workingSpaceWidthMeters / 2
        guard let minAlong = alongs.min(), let maxAlong = alongs.max(),
              let minOut = outs.min(), let maxOut = outs.max() else { return false }
        return minAlong < halfWidth && maxAlong > -halfWidth
            && minOut < BatteryGeometry.workingSpaceDepthMeters && maxOut > 0
    }

    /// The cabinet cannot sit in front of a window. A window on the host wall that falls inside the cabinet's projection is a conflict. No classified face there stays unknown.
    /// Only a wall the mesh itself found behind the cabinet can pass: a detected plane reaches past where the wall
    /// ends (its margin), so on the plane alone "no window" would be a guess.
    private func clearOfWindows(_ snapshot: PlacementSceneSnapshot) -> Bool? {
        guard snapshot.lidarMeshAvailable, let battery = snapshot.batteryPosition?.simd else { return nil }
        guard hasScan(snapshot.classifiedMesh, around: battery, radius: 2) else { return nil }
        guard let hit = meshWallHit(battery: battery, yaw: snapshot.batteryYawRadians, samples: snapshot.classifiedMesh) else {
            return nil
        }
        let host = WallFrame(point: hit.wallPoint, normal: hit.normal)
        let up = SIMD3<Float>(0, 1, 0)
        guard let along = unit(simd_cross(host.normal, up)) else { return nil }
        let span = cabinetSpanOnWall(battery: battery, yaw: snapshot.batteryYawRadians, host: host, along: along, up: up)
        var sawFace = false
        var coversWindow = false
        for sample in snapshot.classifiedMesh {
            guard sample.faceClass == .wall || sample.faceClass == .window else { continue }
            guard isOnWall(sample, wall: host) else { continue }
            let delta = sample.point - host.point
            let margin: Float = 0.05
            guard simd_dot(delta, along) >= span.minAlong - margin,
                  simd_dot(delta, along) <= span.maxAlong + margin,
                  simd_dot(delta, up) >= span.minUp - margin,
                  simd_dot(delta, up) <= span.maxUp + margin else { continue }
            sawFace = true
            if sample.faceClass == .window { coversWindow = true }
        }
        if coversWindow { return false }
        return sawFace ? true : nil
    }

    /// The cabinet projected onto the host wall, in along-wall and up coordinates measured from the wall point.
    private func cabinetSpanOnWall(
        battery: SIMD3<Float>,
        yaw: Float,
        host: WallFrame,
        along: SIMD3<Float>,
        up: SIMD3<Float>
    ) -> (minAlong: Float, maxAlong: Float, minUp: Float, maxUp: Float) {
        let rotation = simd_quatf(angle: yaw, axis: up)
        let half = SIMD3<Float>(
            BatteryGeometry.widthMeters / 2,
            BatteryGeometry.heightMeters / 2,
            BatteryGeometry.depthMeters / 2
        )
        let center = battery + SIMD3(0, half.y, 0)
        var minAlong = Float.greatestFiniteMagnitude
        var maxAlong = -Float.greatestFiniteMagnitude
        var minUp = Float.greatestFiniteMagnitude
        var maxUp = -Float.greatestFiniteMagnitude
        for corner in 0..<8 {
            let local = SIMD3<Float>(
                corner & 1 == 0 ? -half.x : half.x,
                corner & 2 == 0 ? -half.y : half.y,
                corner & 4 == 0 ? -half.z : half.z
            )
            let delta = (center + rotation.act(local)) - host.point
            let alongDistance = simd_dot(delta, along)
            let upDistance = simd_dot(delta, up)
            minAlong = min(minAlong, alongDistance)
            maxAlong = max(maxAlong, alongDistance)
            minUp = min(minUp, upDistance)
            maxUp = max(maxUp, upDistance)
        }
        return (minAlong, maxAlong, minUp, maxUp)
    }

    /// Sideways shifts of the 30 in width tried in front of the meter. The meter only needs 30 in of clear space
    /// somewhere across its face, so one clear slide passes. Tune on device.
    static let workingSpaceSlidesMeters: [Float] = [0, 0.05, -0.05, 0.10, -0.10, 0.15, -0.15]
    /// 6 in: faces this close in front of the meter's face are wall-mounted equipment beside it, not an obstacle.
    static let flushEquipmentMeters: Float = 0.15

    /// The positioned 30 × 36 in slab. Floor, the host wall, and the meter's own enclosure are ignored. Yes/No is not
    /// consulted. It needs no battery: from the meter lock, the host is the meter wall. The width slides sideways a
    /// little (always keeping the meter enclosure inside it), and any clear slide passes. Unknown when no slide has
    /// enough scan under it, or every covered slide holds only a few stray faces.
    private func workingSpaceClearance(_ snapshot: PlacementSceneSnapshot, scan: ScanIndex) -> Bool? {
        guard snapshot.lidarMeshAvailable, let center = snapshot.workingSpacePosition?.simd else { return nil }
        let meterWall = wallFrame(position: snapshot.meterWallPosition, normal: snapshot.meterWallNormal)
        let battery = snapshot.batteryPosition?.simd
        let host = battery.map {
            hostWall(battery: $0, yaw: snapshot.batteryYawRadians, samples: snapshot.classifiedMesh, planes: snapshot.verticalPlanes)
        } ?? meterWall
        let yaw = snapshot.workingSpaceYawRadians
        let halfWidth = BatteryGeometry.workingSpaceWidthMeters / 2
        let halfDepth = BatteryGeometry.workingSpaceDepthMeters / 2
        let enclosureHalf = (snapshot.meterHalfWidthMeters ?? Self.defaultMeterHalfWidthMeters) + 0.03
        let widthAxis = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let up = SIMD3<Float>(0, 1, 0)
        let meterAlong = meterWall.flatMap { unit(simd_cross(up, $0.normal)) }
        /// Faces of the meter itself (glass, socket, collar) stand in the slab by definition. So do the sides of
        /// equipment mounted beside it, such as the panel: the NEC lets associated equipment stand up to 6 in beyond
        /// the meter's front inside its working space. Neither is an obstacle.
        func isMeterEnclosure(_ sample: ClassifiedMeshSample) -> Bool {
            guard let meterWall, let meterAlong else { return false }
            let delta = sample.point - meterWall.point
            let out = simd_dot(delta, meterWall.normal)
            if out <= Self.flushEquipmentMeters { return true }
            return abs(simd_dot(delta, meterAlong)) <= enclosureHalf && out <= 0.30 && abs(delta.y) <= 0.35
        }
        let candidates = snapshot.classifiedMesh.filter { sample in
            occupiesVolume(sample, ignoring: host, alsoIgnoring: meterWall) && !isMeterEnclosure(sample)
        }
        var sawBlocked = false
        for slide in Self.workingSpaceSlidesMeters where abs(slide) + enclosureHalf <= halfWidth || slide == 0 {
            let slid = center + widthAxis * slide
            let coverage = scan.groundCoverage(
                center: slid,
                yaw: yaw,
                halfWidth: halfWidth,
                halfDepth: halfDepth,
                inFrontOf: host,
                openSide: battery ?? center
            )
            guard coverage >= minScanCoverage else { continue }
            let hits = candidates.filter {
                point($0.point, isInsideBoxAt: slid, yaw: yaw, halfWidth: halfWidth, halfDepth: halfDepth,
                      minHeight: minObstacleHeightMeters, maxHeight: 2)
            }
            switch obstacleVerdict(hits) {
            case true?: return true
            case false?: sawBlocked = true
            case nil: break
            }
        }
        return sawBlocked ? false : nil
    }

    /// The chosen side of the meter, or the other side when the chosen one is blocked and the other is clear.
    /// Either side works for a transfer switch, so one clear side passes.
    private func transferSwitch(_ snapshot: PlacementSceneSnapshot, scan: ScanIndex) -> (frame: TransferFrame, clear: Bool?)? {
        let preferred = snapshot.transferSwitchOnLeft
        guard let first = transferSwitchFrame(snapshot, onLeft: preferred) else { return nil }
        let firstClear = transferSwitchClearance(first, snapshot: snapshot, scan: scan)
        if firstClear == false,
           let other = transferSwitchFrame(snapshot, onLeft: !preferred),
           transferSwitchClearance(other, snapshot: snapshot, scan: scan) == true {
            return (other, true)
        }
        return (first, firstClear)
    }

    /// 13 in wide by about 3 ft tall beside the meter, 30 in out from the wall. A wall face the scan has not mostly covered stays unknown.
    private func transferSwitchClearance(_ frame: TransferFrame, snapshot: PlacementSceneSnapshot, scan: ScanIndex) -> Bool? {
        guard snapshot.lidarMeshAvailable else { return nil }
        guard scan.wallCoverage(of: frame) >= minScanCoverage else { return nil }
        let mounting = WallFrame(point: frame.wallPoint, normal: frame.normal)
        return !isBlocked(snapshot.classifiedMesh) { sample in
            guard occupiesVolume(sample, ignoring: mounting) else { return false }
            let delta = sample.point - frame.center
            return abs(simd_dot(delta, frame.along)) <= frame.halfAlong
                && abs(simd_dot(delta, frame.up)) <= frame.halfHeight
                && abs(simd_dot(delta, frame.normal)) <= frame.halfOut
        }
    }

    private func isBlocked(_ samples: [ClassifiedMeshSample], by occupies: (ClassifiedMeshSample) -> Bool) -> Bool {
        var hits = 0
        for sample in samples where occupies(sample) {
            hits += 1
            if hits >= minObstacleSamples { return true }
        }
        return false
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

    /// Both locks must face the same way and lie on nearly the same plane. Yes/No is not a fallback.
    /// Lock normals come from a small patch, and an open panel door or a meter collar can tilt one by 30° or more, so a
    /// wall the mesh sees running between them also counts: most of the 10 cm strips between the two locks hold wall
    /// faces on the meter's plane. Opposite normals are a flipped patch or the two faces of one thin wall when their
    /// planes nearly coincide (unknown), and opposite walls otherwise.
    private func meterAndPanelSameWall(_ snapshot: PlacementSceneSnapshot) -> Bool? {
        guard let meterNormal = horizontalUnit(snapshot.meterWallNormal?.simd),
              let panelNormal = horizontalUnit(snapshot.panelWallNormal?.simd),
              let meterPoint = snapshot.meterWallPosition?.simd,
              let panelPoint = snapshot.panelWallPosition?.simd else { return nil }
        let dot = simd_dot(meterNormal, panelNormal)
        let separation = abs(simd_dot(panelPoint - meterPoint, meterNormal))
        if dot >= wallSameDirectionDotThreshold { return separation <= sameWallPlaneToleranceMeters }
        if dot <= -wallSameDirectionDotThreshold { return separation <= oppositeNormalPlaneToleranceMeters ? nil : false }
        guard separation <= sameWallPlaneToleranceMeters else { return false }
        return wallRuns(from: meterPoint, to: panelPoint, normal: meterNormal, samples: snapshot.classifiedMesh)
    }

    /// Share of 10 cm along-wall strips between two points on one wall that must hold a wall face on that plane.
    static let wallRunShare: Float = 0.6
    /// A wall face this close to the plane (in front of or behind it) is on it. The meter face sits about 0.12 m in
    /// front of the siding, so this also finds the siding behind a lock made on the meter's glass.
    static let wallRunPlaneToleranceMeters: Float = 0.15

    /// True when most 10 cm strips from `start` to `end`, along the wall with this normal, hold a vertical wall face
    /// within `wallRunPlaneToleranceMeters` of the plane through `start`.
    private func wallRuns(from start: SIMD3<Float>, to end: SIMD3<Float>, normal: SIMD3<Float>, samples: [ClassifiedMeshSample]) -> Bool {
        guard let along = unit(simd_cross(SIMD3(0, 1, 0), normal)) else { return false }
        let bin: Float = 0.1
        let a0 = min(0, simd_dot(end - start, along))
        let a1 = max(0, simd_dot(end - start, along))
        let bins = max(1, Int(((a1 - a0) / bin).rounded(.up)))
        var filled = Set<Int>()
        for sample in samples where sample.faceClass == .wall {
            guard abs(sample.normal.y) < 0.45 * max(simd_length(sample.normal), 1e-6),
                  let faceNormal = horizontalUnit(sample.normal), abs(simd_dot(faceNormal, normal)) > 0.85 else { continue }
            let delta = sample.point - start
            guard abs(simd_dot(delta, normal)) <= Self.wallRunPlaneToleranceMeters, abs(delta.y) <= 1.5 else { continue }
            let position = simd_dot(delta, along)
            guard position >= a0, position <= a1 else { continue }
            filled.insert(min(bins - 1, Int((position - a0) / bin)))
        }
        return Float(filled.count) >= Self.wallRunShare * Float(bins)
    }

    /// The wall behind the cabinet: wall faces behind its back face (never in front of it), facing it within about
    /// 30°, and at least three of them on one plane. The clearance is that cluster's median gap, so one stray face at
    /// the cabinet's edge no longer reads as a wall at 0 in. Faces in the bottom 10 cm are skipped: the rounded seam
    /// where wall meets ground tilts every which way.
    private func meshWallHit(battery: SIMD3<Float>, yaw: Float, samples: [ClassifiedMeshSample]) -> WallClearanceHit? {
        let rotation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        // The cabinet's front (+Z, where its face mark is) points away from its wall, so the wall is toward −Z.
        let back = -rotation.act(SIMD3(0, 0, 1))
        let side = rotation.act(SIMD3(1, 0, 0))
        let halfDepth = BatteryGeometry.depthMeters / 2
        let halfWidth = BatteryGeometry.widthMeters / 2
        var faces: [(gap: Float, normal: SIMD3<Float>)] = []
        for sample in samples where sample.faceClass == .wall || sample.faceClass == .window {
            guard let normal = horizontalUnit(sample.normal), abs(simd_dot(normal, back)) >= 0.85 else { continue }
            let delta = sample.point - battery
            guard delta.x * delta.x + delta.z * delta.z <= 25, delta.y > 0.1, delta.y < 2.5 else { continue }
            let behind = simd_dot(delta, back)
            guard behind >= halfDepth - 0.02, abs(simd_dot(delta, side)) <= halfWidth + 0.75 else { continue }
            faces.append((behind - halfDepth, simd_dot(normal, back) > 0 ? -normal : normal))
        }
        faces.sort { $0.gap < $1.gap }
        for index in faces.indices {
            let start = faces[index].gap
            let cluster = faces[index...].prefix { $0.gap <= start + Self.wallClusterMeters }
            guard cluster.count >= Self.wallClusterFaces else { continue }
            let gaps = cluster.map(\.gap)
            let clearance = max(0, gaps[gaps.count / 2])
            let normal = unit(cluster.reduce(SIMD3<Float>.zero) { $0 + $1.normal }) ?? -back
            let edge = battery + back * halfDepth
            return WallClearanceHit(
                distanceFeet: Double(clearance) / 0.3048,
                edge: edge,
                wallPoint: edge + back * clearance,
                normal: normal,
                method: .lidarMesh
            )
        }
        return nil
    }

    /// Faces within this depth of each other are one wall plane; a plane needs this many of them. Tune on device.
    static let wallClusterMeters: Float = 0.05
    static let wallClusterFaces = 3

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

    fileprivate struct WallFrame {
        var point: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    fileprivate struct TransferFrame {
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

    private func transferSwitchFrame(_ snapshot: PlacementSceneSnapshot, onLeft: Bool) -> TransferFrame? {
        guard let wallPoint = snapshot.meterWallPosition?.simd,
              let outward = horizontalUnit(snapshot.meterWallNormal?.simd ?? .zero) else { return nil }
        let up = SIMD3<Float>(0, 1, 0)
        // Facing the wall, the viewer's right. `cross(outward, up)` pointed to the viewer's left, so "left" was right.
        guard let viewerRight = unit(simd_cross(up, outward)) else { return nil }
        let side: Float = onLeft ? -1 : 1
        let along = viewerRight * side
        let halfAlong = TransferSwitchReservation.alongWallMeters / 2
        let halfHeight = TransferSwitchReservation.heightMeters / 2
        let halfOut = TransferSwitchReservation.outFromWallMeters / 2
        // The reservation starts at the meter enclosure's edge, not 8 cm from the meter's center, which put the box
        // over the meter itself and read the meter as an obstacle.
        let meterHalfWidth = snapshot.meterHalfWidthMeters ?? Self.defaultMeterHalfWidthMeters
        var center = wallPoint + along * (meterHalfWidth + 0.02 + halfAlong) + outward * halfOut
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
        case .wall, .window, .other: break
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
        // Same axes as the entity drawn with `simd_quatf(angle: yaw, axis: +Y)`: local X = (cos, 0, −sin) and local
        // Z = (sin, 0, cos). The old signs tested the mirror image of the drawn box, which at the demo wall's 59° yaw
        // turned the working space 117° and reached into the wall and past the meter's side.
        let cosYaw = cos(yaw)
        let sinYaw = sin(yaw)
        let dx = point.x - origin.x
        let dz = point.z - origin.z
        let localX = cosYaw * dx - sinYaw * dz
        let localZ = sinYaw * dx + cosYaw * dz
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

    // MARK: - Pad checks for the battery-spot search

    /// The battery rules that move with the pad, for one candidate spot. Nil is unknown.
    fileprivate struct PadChecks {
        var footprintClear: Bool?
        var withinWallDistance: Bool?
        var clearOfWindows: Bool?
        var keepsAccess: Bool?
        /// Nil without a gas mark.
        var clearOfGas: Bool?
        var withinMeterDistance: Bool?
    }

    /// Only the checks that depend on the pad, with one `ScanIndex` shared by every candidate. Same functions as
    /// `measure`, so a chosen spot reads the same in Review.
    fileprivate func padChecks(_ snapshot: PlacementSceneSnapshot, scan: ScanIndex) -> PadChecks {
        PadChecks(
            footprintClear: footprintClearance(snapshot, scan: scan),
            withinWallDistance: wallDistanceFeet(snapshot).map { $0 <= BaseRuleSet.maxWallDistanceFeet },
            clearOfWindows: clearOfWindows(snapshot),
            keepsAccess: keepsEquipmentAccess(snapshot),
            clearOfGas: horizontalFeet(snapshot.batteryPosition, snapshot.gasMeterPosition).map { $0 >= BaseRuleSet.minGasMeterDistanceFeet },
            withinMeterDistance: horizontalFeet(snapshot.batteryPosition, snapshot.meterPosition).map { $0 <= BaseRuleSet.maxMeterDistanceFeet }
        )
    }

    // MARK: - Lock geometry from the mesh

    /// Median height of the floor faces within 0.6 m of a spot 0.3 m out from a lock (the ground in front of the
    /// meter), `below` or more under the lock. Nil with fewer than `minSamples`. The plane raycast it goes before put
    /// the demo wall's ground 8 cm high, on the turf edge. Pure, for the meter height and the gas height.
    static func floorMedianY<S: Sequence>(
        _ samples: S,
        near point: SIMD3<Float>,
        outward: SIMD3<Float>,
        below: Float = 0.2,
        minSamples: Int = 8
    ) -> Float? where S.Element == ClassifiedMeshSample {
        let flat = SIMD3<Float>(outward.x, 0, outward.z)
        let length = simd_length(flat)
        let center = length > 0.001 ? point + flat / length * 0.3 : point
        var heights: [Float] = []
        for sample in samples where sample.faceClass == .floor {
            let dx = sample.point.x - center.x
            let dz = sample.point.z - center.z
            guard dx * dx + dz * dz <= 0.36, sample.point.y <= point.y - below else { continue }
            heights.append(sample.point.y)
        }
        guard heights.count >= minSamples else { return nil }
        heights.sort()
        return heights[heights.count / 2]
    }

    /// The wall under a lock, from the mesh: the dominant direction of the wall faces 0–0.35 m behind the lock point
    /// and within 0.6 m of it, in 5° bins, when at least 12 agree. `behind` is how far that wall sits behind the lock
    /// point (the meter's glass stands off the siding). Nil keeps the lock's own patch normal: an open panel door or a
    /// meter collar tilted the demo wall's panel patch 37° off the siding.
    static func snappedWallNormal<S: Sequence>(
        _ samples: S,
        at point: SIMD3<Float>,
        patchNormal: SIMD3<Float>
    ) -> (normal: SIMD3<Float>, behind: Float)? where S.Element == ClassifiedMeshSample {
        let up = SIMD3<Float>(0, 1, 0)
        let flatPatch = SIMD3<Float>(patchNormal.x, 0, patchNormal.z)
        guard simd_length(flatPatch) > 0.001 else { return nil }
        let patch = simd_normalize(flatPatch)
        let right = simd_normalize(simd_cross(up, patch))
        let binWidth: Float = 5 * .pi / 180
        let widest: Float = cos(50 * .pi / 180)
        var faces: [(angle: Float, behind: Float, bin: Int)] = []
        for sample in samples where sample.faceClass == .wall {
            let length = simd_length(sample.normal)
            guard length > 1e-6, abs(sample.normal.y) / length < 0.3 else { continue }
            var flat = simd_normalize(SIMD3(sample.normal.x, 0, sample.normal.z))
            if simd_dot(flat, patch) < 0 { flat = -flat }
            guard simd_dot(flat, patch) >= widest, simd_distance(sample.point, point) <= 0.6 else { continue }
            let behind = simd_dot(point - sample.point, patch)
            guard behind >= 0, behind <= 0.35 else { continue }
            let angle = atan2(simd_dot(flat, right), simd_dot(flat, patch))
            faces.append((angle, behind, Int((angle / binWidth).rounded(.down))))
        }
        guard faces.count >= Self.snapMinFaces else { return nil }
        var counts: [Int: Int] = [:]
        for face in faces { counts[face.bin, default: 0] += 1 }
        let window = { (bin: Int) in (counts[bin - 1] ?? 0) + (counts[bin] ?? 0) + (counts[bin + 1] ?? 0) }
        guard let best = counts.keys.max(by: { window($0) < window($1) || (window($0) == window($1) && $0 > $1) }) else { return nil }
        let cluster = faces.filter { abs($0.bin - best) <= 1 }
        guard cluster.count >= Self.snapMinFaces else { return nil }
        let angles = cluster.map(\.angle).sorted()
        let behinds = cluster.map(\.behind).sorted()
        let angle = angles[angles.count / 2]
        return (simd_normalize(patch * cos(angle) + right * sin(angle)), behinds[behinds.count / 2])
    }

    /// Wall faces that must agree before a lock's normal is taken from the mesh. Tune on device.
    static let snapMinFaces = 12
}

/// The Live Survey's own battery spot. Candidates stand along the meter wall on both sides, judged from the scan in the
/// background while the user looks around, and the best is placed when the scan ends. Pure: it runs on a snapshot copy
/// off the main thread, and the same code runs at the finish.
///
/// A candidate is out when the wall ends under it, when something stands between it and the meter (the conduit run),
/// when it is within 3.25 ft of the gas mark, or when any pad rule measures a conflict. The rest rank by fewest
/// unknown pad rules, then nearest the meter, then away from the panel.
struct BatterySpotPlanner: Sendable {
    /// Cabinet-center offsets from the meter along its wall, each tried on both sides. Tune on device.
    static let offsetsMeters: [Float] = [0.9, 1.4, 1.8, 2.7, 3.6]
    static let binMeters: Float = 0.1
    /// Share of the 10 cm strips across the cabinet's width that must hold the meter wall. Tune on device.
    static let wallShare: Float = 0.6
    static let wallToleranceMeters: Float = 0.15
    static let wallBandMeters: ClosedRange<Float> = 0.1...1.5
    /// The run from the meter to the pad: faces here are something in the way. Tune on device.
    static let corridorOutMeters: ClosedRange<Float> = 0.05...0.9
    static let corridorHeightMeters: ClosedRange<Float> = 0.1...2.0
    /// Faces this close to the meter's own plane are the siding, the meter, or the panel, not an obstacle.
    static let corridorPlaneMeters: Float = 0.15
    static let corridorBlockingFaces = 4
    /// A little over the 3 ft rule, so a gas mark a few inches off does not flip the pick.
    static let gasKeepAwayFeet: Double = 3.25
    /// A few inches off the wall, so the back face sits inside the 1 ft wall check.
    static let wallGapMeters: Float = 3 * BatteryGeometry.inchesToMeters

    struct Input: Sendable {
        var snapshot: PlacementSceneSnapshot
        /// The meter lock and its outward wall normal (horizontal, unit).
        var meterPoint: SIMD3<Float>
        var outward: SIMD3<Float>
        /// How far the siding sits behind the meter lock point. 0 when the mesh did not say.
        var wallBehindMeters: Float
        var groundY: Float
        /// At the finish a stretch nobody scanned is out ("not scanned"); during the scan it is only pending.
        var final: Bool
    }

    enum Verdict: Sendable, Equatable {
        case fits(unknowns: Int)
        case pending(String)
        case rejected(String)
    }

    struct Candidate: Sendable, Equatable {
        /// Along the wall from the meter, positive to the right of someone facing the wall.
        var offsetMeters: Float
        var position: SIMD3<Float>
        var yaw: Float
        var verdict: Verdict
    }

    struct Plan: Sendable, Equatable {
        var candidates: [Candidate]
        var winner: Candidate?
        var status: BatterySpotSummary.Status
        /// The panel lock along the meter wall, same sign as `offsetMeters`. Nil without a panel.
        var panelAlongMeters: Float?

        /// What survey.json records. Along-wall distances are positive toward the panel (to the right without one).
        var summary: BatterySpotSummary {
            let towardPanelSign: Float = (panelAlongMeters ?? 1) < 0 ? -1 : 1
            func label(_ candidate: Candidate) -> String {
                String(format: "%+.1f m", locale: Locale(identifier: "en_US_POSIX"), candidate.offsetMeters * towardPanelSign)
            }
            let rejections = candidates.compactMap { candidate -> String? in
                switch candidate.verdict {
                case .fits: return nil
                case .pending(let reason), .rejected(let reason): return "\(label(candidate)): \(reason)"
                }
            }
            return BatterySpotSummary(
                status: status,
                alongWallFeet: winner.map { Double($0.offsetMeters * towardPanelSign / BatteryGeometry.feetToMeters) },
                towardPanel: winner.flatMap { winner in panelAlongMeters.map { ($0 < 0) == (winner.offsetMeters < 0) } },
                candidatesTried: candidates.count,
                rejections: rejections
            )
        }
    }

    static let wallEnds = "wall ends"
    static let notScanned = "not scanned"

    static func plan(_ input: Input, measurer: CorePlacementMeasurer = CorePlacementMeasurer()) -> Plan {
        let up = SIMD3<Float>(0, 1, 0)
        let outward = simd_normalize(SIMD3(input.outward.x, 0, input.outward.z))
        let axis = simd_normalize(simd_cross(up, outward))
        let wall = input.meterPoint - outward * input.wallBehindMeters
        let yaw = atan2(outward.x, outward.z)
        let snapshot = input.snapshot
        let meterHalfWidth = snapshot.meterHalfWidthMeters ?? CorePlacementMeasurer.defaultMeterHalfWidthMeters
        let panel = snapshot.panelWallPosition?.simd
        let panelAlong = panel.map { simd_dot($0 - wall, axis) }

        // One pass over the mesh: which strips hold the wall, which were seen at all, and what stands in front.
        var wallBins = Set<Int>()
        var seenBins = Set<Int>()
        var corridor: [Float] = []
        for sample in snapshot.classifiedMesh {
            let delta = sample.point - wall
            let along = simd_dot(delta, axis)
            let out = simd_dot(delta, outward)
            let height = sample.point.y - input.groundY
            let bin = Int((along / binMeters).rounded(.down))
            if out >= -0.3, out <= 1.5, height >= -0.3, height <= 2 { seenBins.insert(bin) }
            switch sample.faceClass {
            case .floor, .ceiling:
                continue
            case .wall, .window, .other:
                break
            }
            let length = simd_length(sample.normal)
            if length > 1e-6, abs(sample.normal.y) / length < 0.45,
               abs(simd_dot(SIMD3(sample.normal.x, 0, sample.normal.z) / length, outward)) > 0.85,
               abs(out) <= wallToleranceMeters, wallBandMeters.contains(height) {
                wallBins.insert(bin)
            }
            let fromMeterPlane = simd_dot(sample.point - input.meterPoint, outward)
            guard corridorOutMeters.contains(fromMeterPlane), abs(fromMeterPlane) > corridorPlaneMeters,
                  corridorHeightMeters.contains(height) else { continue }
            // The panel and its open door stand beside the meter by design; they are not in the way.
            if let panel, let panelAlong, abs(along - panelAlong) <= 0.35, fromMeterPlane <= 0.6,
               abs(sample.point.y - panel.y) <= 0.6 { continue }
            corridor.append(along)
        }

        let scan = ScanIndex(snapshot.classifiedMesh)
        let halfWidth = BatteryGeometry.widthMeters / 2
        let halfPad = BatteryGeometry.footprintMeters / 2
        let standOff = BatteryGeometry.depthMeters / 2 + wallGapMeters
        let gas = snapshot.gasMeterPosition?.simd
        var candidates: [Candidate] = []
        for magnitude in offsetsMeters {
            for sign: Float in [1, -1] {
                let offset = magnitude * sign
                var position = wall + outward * standOff + axis * offset
                position.y = input.groundY
                let low = Int(((offset - halfWidth) / binMeters).rounded(.down))
                let high = Int(((offset + halfWidth) / binMeters).rounded(.up)) - 1
                let strips = max(1, high - low + 1)
                let onWall = (low...max(low, high)).filter { wallBins.contains($0) }.count
                let seen = (low...max(low, high)).filter { seenBins.contains($0) }.count
                func verdict() -> Verdict {
                    if Float(onWall) < wallShare * Float(strips) {
                        if Float(seen) < wallShare * Float(strips) {
                            return input.final ? .rejected(notScanned) : .pending(notScanned)
                        }
                        return .rejected(wallEnds)
                    }
                    let near = meterHalfWidth
                    let far = magnitude - halfPad
                    if far > near {
                        let between = corridor.filter { along in
                            let reach = along * sign
                            return reach > near && reach < far
                        }.count
                        if between >= corridorBlockingFaces { return .rejected("something between it and the meter") }
                    }
                    if let gas {
                        let dx = Double(position.x - gas.x)
                        let dz = Double(position.z - gas.z)
                        if (dx * dx + dz * dz).squareRoot() / Double(BatteryGeometry.feetToMeters) < gasKeepAwayFeet {
                            return .rejected("too close to the gas meter")
                        }
                    }
                    var probe = snapshot
                    probe.batteryPosition = PlacementAnchor(position)
                    probe.batteryYawRadians = yaw
                    let checks = measurer.padChecks(probe, scan: scan)
                    let rules: [(Bool?, String)] = [
                        (checks.footprintClear, "pad blocked"),
                        (checks.withinWallDistance, "more than 1 ft from the wall"),
                        (checks.clearOfWindows, "in front of a window"),
                        (checks.keepsAccess, "in the meter or panel working space"),
                        (checks.clearOfGas, "within 3 ft of the gas meter"),
                        (checks.withinMeterDistance, "more than 20 ft from the meter")
                    ]
                    if let conflict = rules.first(where: { $0.0 == false }) { return .rejected(conflict.1) }
                    let counted = gas == nil ? rules.filter { $0.1 != "within 3 ft of the gas meter" } : rules
                    return .fits(unknowns: counted.filter { $0.0 == nil }.count)
                }
                candidates.append(Candidate(offsetMeters: offset, position: position, yaw: yaw, verdict: verdict()))
            }
        }

        func rank(_ candidate: Candidate) -> (Int, Float, Int)? {
            guard case .fits(let unknowns) = candidate.verdict else { return nil }
            let panelSide = panelAlong.map { ($0 < 0) == (candidate.offsetMeters < 0) } ?? false
            return (unknowns, abs(candidate.offsetMeters), panelSide ? 1 : 0)
        }
        let winner = candidates
            .compactMap { candidate in rank(candidate).map { (candidate, $0) } }
            .min { lhs, rhs in lhs.1 < rhs.1 }?.0
        let status: BatterySpotSummary.Status
        if winner != nil {
            status = .placed
        } else if candidates.allSatisfy({ $0.verdict == .rejected(wallEnds) || $0.verdict == .rejected(notScanned) || $0.verdict == .pending(notScanned) }) {
            status = .noWall
        } else {
            status = .allRejected
        }
        return Plan(candidates: candidates, winner: winner, status: status, panelAlongMeters: panelAlong)
    }
}

/// Which 10 cm cells of the scene hold any scanned face, so a check can tell "clear" from "never scanned".
/// Obstacles count as scanned: a spot blocked by an AC unit is known, not a gap.
fileprivate struct ScanIndex {
    static let cell: Float = 0.1
    private var columns = Set<SIMD2<Int32>>()
    private var voxels = Set<SIMD3<Int32>>()

    init(_ samples: [ClassifiedMeshSample]) {
        for sample in samples {
            let key = Self.key(sample.point)
            columns.insert(SIMD2(key.x, key.z))
            voxels.insert(key)
        }
    }

    private static func key(_ point: SIMD3<Float>) -> SIMD3<Int32> {
        SIMD3(Int32((point.x / cell).rounded(.down)), Int32((point.y / cell).rounded(.down)), Int32((point.z / cell).rounded(.down)))
    }

    /// Share of ground cells inside the box, seen from above, that hold scanned surface.
    /// Cells behind the host wall are skipped: that is inside the house and is never scanned.
    /// Same local axes as `CorePlacementMeasurer.point(_:isInsideBoxAt:...)`.
    func groundCoverage(
        center: SIMD3<Float>,
        yaw: Float,
        halfWidth: Float,
        halfDepth: Float,
        inFrontOf host: CorePlacementMeasurer.WallFrame?,
        openSide: SIMD3<Float>
    ) -> Float {
        let cosYaw = cos(yaw)
        let sinYaw = sin(yaw)
        let openSign: Float = host.map { simd_dot(openSide - $0.point, $0.normal) >= 0 ? 1 : -1 } ?? 1
        var seen = 0
        var total = 0
        var localX = -halfWidth + Self.cell / 2
        while localX < halfWidth {
            var localZ = -halfDepth + Self.cell / 2
            while localZ < halfDepth {
                let world = center + SIMD3(cosYaw * localX + sinYaw * localZ, 0, -sinYaw * localX + cosYaw * localZ)
                localZ += Self.cell
                if let host, simd_dot(world - host.point, host.normal) * openSign < -0.05 { continue }
                total += 1
                let key = Self.key(world)
                if columns.contains(SIMD2(key.x, key.z)) { seen += 1 }
            }
            localX += Self.cell
        }
        return total == 0 ? 0 : Float(seen) / Float(total)
    }

    /// Share of cells on the wall face behind a transfer-switch box that hold scanned surface.
    func wallCoverage(of frame: CorePlacementMeasurer.TransferFrame) -> Float {
        let wallCenter = frame.center - frame.normal * frame.halfOut
        var seen = 0
        var total = 0
        var along = -frame.halfAlong + Self.cell / 2
        while along < frame.halfAlong {
            var up = -frame.halfHeight + Self.cell / 2
            while up < frame.halfHeight {
                let point = wallCenter + frame.along * along + frame.up * up
                total += 1
                if [-Self.cell, 0, Self.cell].contains(where: { voxels.contains(Self.key(point + frame.normal * $0)) }) {
                    seen += 1
                }
                up += Self.cell
            }
            along += Self.cell
        }
        return total == 0 ? 0 : Float(seen) / Float(total)
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

/// Colored geometry for `scene.ply`, in the same ARKit world frame as the mesh: the battery, its footprint,
/// marked equipment, and each distance as a bar. Bars and outlines are green when they pass, red on a conflict,
/// amber when there is no verdict. The numbers go into header comments, since PLY has no text.
enum MeasurementOverlay {
    static let pass = SIMD3<UInt8>(52, 199, 89)
    static let conflict = SIMD3<UInt8>(255, 59, 48)
    static let unknown = SIMD3<UInt8>(255, 176, 0)
    static let battery = SIMD3<UInt8>(225, 225, 230)
    static let meter = SIMD3<UInt8>(175, 82, 222)
    static let panel = SIMD3<UInt8>(0, 199, 190)
    static let gas = SIMD3<UInt8>(255, 45, 85)

    static func build(_ snapshot: PlacementSceneSnapshot, measurer: CorePlacementMeasurer) -> (chunk: MeshPointCloudChunk, comments: [String]) {
        let measured = measurer.measure(snapshot)
        var shape = OverlayShapes()
        var comments = [
            "overlay: battery light gray, meter purple, panel teal, gas meter pink",
            "overlay: distance bars and outlines green pass, red conflict, amber unknown"
        ]
        func tone(_ passes: Bool?) -> SIMD3<UInt8> {
            switch passes {
            case true?: pass
            case false?: conflict
            case nil: unknown
            }
        }
        func note(_ name: String, _ feet: Double?, _ passes: Bool?) {
            guard let feet else { return }
            let verdict = passes.map { $0 ? "pass" : "conflict" } ?? "unknown"
            comments.append(String(format: "measurement %@ %.2f ft %@", locale: Locale(identifier: "en_US_POSIX"), name, feet, verdict))
        }
        func flag(_ name: String, _ value: Bool?) {
            comments.append("check \(name) \(value.map { $0 ? "clear" : "blocked" } ?? "unknown")")
        }
        func confirmed(_ kind: PlacementMeasurementKind) -> ConfirmedPlacementMeasurement? {
            snapshot.confirmedMeasurements.first { $0.kind == kind }
        }
        let up = SIMD3<Float>(0, 1, 0)
        func frame(yaw: Float) -> [SIMD3<Float>] {
            let rotation = simd_quatf(angle: yaw, axis: up)
            return [rotation.act(SIMD3(1, 0, 0)), up, rotation.act(SIMD3(0, 0, 1))]
        }

        let batteryPoint = snapshot.batteryPosition?.simd
        if let batteryPoint {
            let axes = frame(yaw: snapshot.batteryYawRadians)
            shape.box(
                center: batteryPoint + SIMD3(0, BatteryGeometry.heightMeters / 2, 0),
                axes: axes,
                half: SIMD3(BatteryGeometry.widthMeters, BatteryGeometry.heightMeters, BatteryGeometry.depthMeters) / 2,
                color: battery
            )
            let half = BatteryGeometry.footprintMeters / 2
            shape.groundRectangle(center: batteryPoint, axes: axes, halfWidth: half, halfDepth: half, color: tone(measured.footprintIsClear))
        }
        if let center = snapshot.workingSpacePosition?.simd {
            shape.groundRectangle(
                center: center,
                axes: frame(yaw: snapshot.workingSpaceYawRadians),
                halfWidth: BatteryGeometry.workingSpaceWidthMeters / 2,
                halfDepth: BatteryGeometry.workingSpaceDepthMeters / 2,
                color: tone(measured.frontWorkingSpaceIsClear)
            )
        }
        if let box = measurer.transferSwitchBox(in: snapshot) {
            shape.wireBox(
                center: box.center,
                axes: [box.along, box.up, box.normal],
                half: SIMD3(box.alongMeters, box.heightMeters, box.outMeters) / 2,
                color: tone(measured.transferSwitchClearanceObserved)
            )
        }
        for (point, color) in [
            (snapshot.meterPosition, meter), (snapshot.meterWallPosition, meter),
            (snapshot.panelPosition, panel), (snapshot.panelWallPosition, panel),
            (snapshot.gasMeterPosition, gas)
        ] {
            if let point { shape.marker(point.simd, color: color) }
        }

        // Each bar uses the same endpoints the measurer read, so its length matches the number.
        func horizontal(_ target: PlacementAnchor?, kind: PlacementMeasurementKind, color: SIMD3<UInt8>) {
            if let saved = confirmed(kind) {
                shape.bar(saved.start.position.simd, saved.end.position.simd, color: color)
            } else if let batteryPoint, let target = target?.simd {
                let lift = batteryPoint.y + 0.02
                shape.bar(SIMD3(batteryPoint.x, lift, batteryPoint.z), SIMD3(target.x, lift, target.z), color: color)
            }
        }
        let meterPasses = measured.distanceToMeterFeet.map { $0 <= BaseRuleSet.maxMeterDistanceFeet }
        horizontal(snapshot.meterPosition, kind: .batteryToMeter, color: tone(meterPasses))
        note("battery_to_meter", measured.distanceToMeterFeet, meterPasses)

        let gasPasses = measured.distanceToGasMeterFeet.map { $0 >= BaseRuleSet.minGasMeterDistanceFeet }
        horizontal(snapshot.gasMeterPosition, kind: .batteryToGasMeter, color: tone(gasPasses))
        note("battery_to_gas_meter", measured.distanceToGasMeterFeet, gasPasses)

        let wallPasses = measured.distanceToWallFeet.map { $0 <= BaseRuleSet.maxWallDistanceFeet }
        if let hit = measurer.wallClearance(in: snapshot) {
            shape.bar(hit.edge, hit.wallPoint, color: tone(wallPasses))
        } else if let saved = confirmed(.batteryToWall), saved.captureMethod != .estimatedPlane {
            shape.bar(saved.start.position.simd, saved.end.position.simd, color: tone(wallPasses))
        }
        note("battery_to_wall", measured.distanceToWallFeet, wallPasses)

        let heightPasses = measured.meterHeightFeet.map {
            $0 >= BaseRuleSet.minMeterHeightFeet && $0 <= BaseRuleSet.maxMeterHeightFeet
        }
        if let ground = snapshot.meterPosition, let wall = snapshot.meterWallPosition, wall.y > ground.y {
            shape.bar(SIMD3(wall.x, ground.y, wall.z), wall.simd, color: tone(heightPasses))
        } else if let saved = confirmed(.meterHeight) {
            shape.bar(saved.start.position.simd, saved.end.position.simd, color: tone(heightPasses))
        }
        note("meter_height", measured.meterHeightFeet, heightPasses)

        flag("footprint", measured.footprintIsClear)
        flag("clear_of_windows", measured.clearOfWindows)
        flag("keeps_meter_and_panel_access", measured.keepsEquipmentAccess)
        flag("front_working_space", measured.frontWorkingSpaceIsClear)
        flag("transfer_switch_space", measured.transferSwitchClearanceObserved)
        if let same = measured.meterAndPanelSameWall {
            comments.append("check meter_and_panel_same_wall \(same ? "yes" : "no")")
        }

        // Exact survey marks, so offline tools never have to find them from the overlay colors.
        // `mark <name> x y z [normal nx ny nz] [yaw radians]`, meters and radians in the ARKit world frame.
        func mark(_ name: String, _ point: PlacementAnchor?, normal: PlacementAnchor? = nil, yaw: Float? = nil) {
            guard let point else { return }
            var line = String(format: "mark %@ %.5f %.5f %.5f", locale: Locale(identifier: "en_US_POSIX"), name, point.x, point.y, point.z)
            if let normal {
                line += String(format: " normal %.5f %.5f %.5f", locale: Locale(identifier: "en_US_POSIX"), normal.x, normal.y, normal.z)
            }
            if let yaw {
                line += String(format: " yaw %.5f", locale: Locale(identifier: "en_US_POSIX"), yaw)
            }
            comments.append(line)
        }
        // With only a wall tap, the snapshot copies the wall point into the ground slot. That is not a ground tap.
        func isGroundTap(_ ground: PlacementAnchor?, below wall: PlacementAnchor?) -> Bool {
            guard let ground else { return false }
            guard let wall else { return true }
            return ground.y < wall.y - 0.1
        }
        if isGroundTap(snapshot.meterPosition, below: snapshot.meterWallPosition) {
            mark("meter_ground", snapshot.meterPosition)
        }
        mark("meter_wall", snapshot.meterWallPosition, normal: snapshot.meterWallNormal)
        if isGroundTap(snapshot.panelPosition, below: snapshot.panelWallPosition) {
            mark("panel_ground", snapshot.panelPosition)
        }
        mark("panel_wall", snapshot.panelWallPosition, normal: snapshot.panelWallNormal)
        mark("gas_meter", snapshot.gasMeterPosition)
        mark("battery", snapshot.batteryPosition, yaw: snapshot.batteryPosition == nil ? nil : snapshot.batteryYawRadians)
        mark(
            "battery_suggested",
            snapshot.suggestedBatteryPosition,
            yaw: snapshot.suggestedBatteryPosition == nil ? nil : snapshot.suggestedBatteryYawRadians
        )
        mark("working_space", snapshot.workingSpacePosition, yaw: snapshot.workingSpacePosition == nil ? nil : snapshot.workingSpaceYawRadians)
        comments.append("mark transfer_switch_preferred_side \(snapshot.transferSwitchOnLeft ? "left" : "right")")
        return (shape.chunk, comments)
    }
}

/// Triangle boxes and bars, so the overlay renders in any PLY viewer without line support.
private struct OverlayShapes {
    var chunk = MeshPointCloudChunk(positions: [], colors: [], triangles: [])

    mutating func box(center: SIMD3<Float>, axes: [SIMD3<Float>], half: SIMD3<Float>, color: SIMD3<UInt8>) {
        let base = UInt32(chunk.positions.count)
        for corner in 0..<8 {
            let x: Float = corner & 1 == 0 ? -1 : 1
            let y: Float = corner & 2 == 0 ? -1 : 1
            let z: Float = corner & 4 == 0 ? -1 : 1
            chunk.positions.append(center + axes[0] * (x * half.x) + axes[1] * (y * half.y) + axes[2] * (z * half.z))
            chunk.colors.append(color)
        }
        // Corner bits: x = 1, y = 2, z = 4.
        let quads: [[UInt32]] = [[0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4], [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6]]
        for quad in quads {
            chunk.triangles += [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]].map { base + $0 }
        }
    }

    mutating func bar(_ start: SIMD3<Float>, _ end: SIMD3<Float>, thickness: Float = 0.025, color: SIMD3<UInt8>) {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 0.001 else { return }
        let along = delta / length
        let reference: SIMD3<Float> = abs(along.y) > 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
        let side = simd_normalize(simd_cross(along, reference))
        box(
            center: (start + end) / 2,
            axes: [along, side, simd_cross(along, side)],
            half: SIMD3(length / 2, thickness / 2, thickness / 2),
            color: color
        )
    }

    mutating func marker(_ point: SIMD3<Float>, color: SIMD3<UInt8>) {
        box(center: point, axes: [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)], half: SIMD3(repeating: 0.05), color: color)
    }

    mutating func groundRectangle(center: SIMD3<Float>, axes: [SIMD3<Float>], halfWidth: Float, halfDepth: Float, color: SIMD3<UInt8>) {
        let lifted = center + SIMD3(0, 0.01, 0)
        let corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { x, z in
            lifted + axes[0] * (Float(x) * halfWidth) + axes[2] * (Float(z) * halfDepth)
        }
        for index in corners.indices {
            bar(corners[index], corners[(index + 1) % corners.count], thickness: 0.015, color: color)
        }
    }

    mutating func wireBox(center: SIMD3<Float>, axes: [SIMD3<Float>], half: SIMD3<Float>, color: SIMD3<UInt8>) {
        func corner(_ bits: Int) -> SIMD3<Float> {
            center
                + axes[0] * (bits & 1 == 0 ? -half.x : half.x)
                + axes[1] * (bits & 2 == 0 ? -half.y : half.y)
                + axes[2] * (bits & 4 == 0 ? -half.z : half.z)
        }
        // The 12 edges join corners that differ in exactly one bit.
        for bits in 0..<8 {
            for flip in [1, 2, 4] where bits & flip == 0 {
                bar(corner(bits), corner(bits | flip), thickness: 0.015, color: color)
            }
        }
    }
}
