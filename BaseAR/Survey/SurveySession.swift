import Foundation
import UIKit

/// Shared survey contract for electrical capture, AR placement, and rules/review.
/// Keep new evidence as optional fields so a check can stay unknown until a teammate fills it.
struct SurveySession: Codable, Sendable, Equatable, Identifiable {
    /// 7: adds optional `gridContext` — ERCOT load zone + sample prices captured at survey time.
    /// 8: adds optional `placement.gasMeterMarkSource`, `placement.gasStepOutcome`, `placement.batterySpot`,
    /// `electrical.gasMeterPhotoFilename`, and `electrical.mainBreakerAmperageBasis`.
    /// 9: adds optional `photoKit` — which saved scan frame best matches each of Base's nine photos.
    var schemaVersion: Int = SurveySession.currentSchemaVersion
    var id: UUID
    var createdAt: Date
    var propertyIdentifier: String
    var contactName: String
    var email: String
    var phone: String
    /// Nil until the home form is answered. Base waitlists renters.
    var homeownership: Homeownership?
    var propertyLocationDisclaimer: String
    var prototypeDisclaimer: String
    /// Phone fix for the property. This is not the battery position.
    var propertyLocation: GeoFix?
    /// ERCOT load-zone snapshot at survey time — populated when a Texas ZIP resolves. Context only; does not affect placement color.
    var gridContext: GridContext?
    var electrical: ElectricalEvidence
    var placement: PlacementEvidence
    var ruleResults: [RuleResult]
    var missingInformation: [String]
    var placementTone: PlacementTone
    /// Fixed labels so a Base engineer reading the JSON knows units without inferring.
    var units: SurveyUnits
    /// App/device provenance for support and reproducibility.
    var appVersion: String
    var buildNumber: String
    var iosVersion: String
    var deviceModel: String
    /// Base's nine-photo kit, tagged to the scan's saved frames when the survey is written (v9, optional).
    /// Nil until the first write, and for older files.
    var photoKit: PhotoKit?

    static let currentSchemaVersion = 9

    static let locationDisclaimer = "Latitude, longitude, timestamp, and horizontal accuracy are the phone's reported property location, not the battery position."
    static let prototypeDisclaimer = "Preliminary survey only. This is not an electrical inspection, a code review, or installation approval."

    @MainActor
    static func new(propertyIdentifier: String) -> SurveySession {
        SurveySession(
            id: UUID(),
            createdAt: Date(),
            propertyIdentifier: propertyIdentifier,
            contactName: "",
            email: "",
            phone: "",
            propertyLocationDisclaimer: locationDisclaimer,
            prototypeDisclaimer: prototypeDisclaimer,
            propertyLocation: nil,
            gridContext: nil,
            electrical: ElectricalEvidence(),
            placement: PlacementEvidence(),
            ruleResults: [],
            missingInformation: [],
            placementTone: .incomplete,
            units: SurveyUnits(),
            appVersion: DeviceProvenance.appVersion,
            buildNumber: DeviceProvenance.buildNumber,
            iosVersion: DeviceProvenance.iosVersion(),
            deviceModel: DeviceProvenance.deviceModel()
        )
    }
}

extension SurveySession {
    /// False for a survey nobody has answered or scanned yet. Launch cleanup deletes those, and autosave skips them.
    var hasUserContent: Bool {
        let typed = [propertyIdentifier, contactName, email, phone].contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return typed
            || homeownership != nil
            || propertyLocation != nil
            || electrical != ElectricalEvidence()
            || placement.meterMarked
            || placement.panelMarked
            || placement.gasMeterMarked
            || placement.batteryPlaced
            || placement.snapshotTimestamp != nil
            || placement.pointCloudFilename != nil
            || placement.captureManifestPath != nil
    }
}

/// Base's photo list (help article 10280641), matched to what the survey already holds: meter.jpg and panel.jpg,
/// and the scan's posed keyframes in capture/frames.json. A tag is the app's best guess from camera poses; it is
/// a prototype aid for Base's engineers, never a statement that the photo is good enough.
struct PhotoKit: Codable, Sendable, Equatable {
    /// One entry per Base shot, keyed by `BaseShot.key` ("1-meter" … "9-panel-area").
    var shots: [String: PhotoKitShot] = [:]
    /// Look-around milestones the Live Survey reported, on the same clock as capture/frames.json.
    var moments: [PhotoKitMoment] = []
    /// The meter's and panel's wall normals from the locks. They tell left from right; nil before a lock.
    var meterWallNormal: PlacementAnchor?
    var panelWallNormal: PlacementAnchor?
    /// How many saved frames the tags were chosen from.
    var framesConsidered = 0
    var method = "Each shot names the saved scan frame whose camera pose best matches it: the meter, panel, or wall stretch in view, and the distance back. Prototype tags; a Base engineer decides whether each photo is good enough."

    /// Review's order: Base's numbering.
    var orderedShots: [PhotoKitShot] {
        BaseShot.allCases.compactMap { shots[$0.key] }
    }
}

/// Base's nine photos, numbered as Base numbers them.
enum BaseShot: Int, CaseIterable, Sendable {
    case meter = 1
    case meterArea
    case meterRight
    case meterLeft
    case adjacentWall
    case behindFence
    case panel
    case mainDisconnect
    case panelArea

    var key: String {
        let slug = switch self {
        case .meter: "meter"
        case .meterArea: "meter-area"
        case .meterRight: "meter-right"
        case .meterLeft: "meter-left"
        case .adjacentWall: "adjacent-wall"
        case .behindFence: "behind-fence"
        case .panel: "main-breaker-box"
        case .mainDisconnect: "main-disconnect"
        case .panelArea: "panel-area"
        }
        return "\(rawValue)-\(slug)"
    }

    var title: String {
        switch self {
        case .meter: "Electric meter, number readable"
        case .meterArea: "Area around the meter, 10 steps back"
        case .meterRight: "Area to the right of the meter"
        case .meterLeft: "Area to the left of the meter"
        case .adjacentWall: "Wall next to the meter wall"
        case .behindFence: "Behind the fence, if there is one"
        case .panel: "Main breaker box"
        case .mainDisconnect: "Main disconnect amperage, close up"
        case .panelArea: "Area around the main breaker box"
        }
    }
}

enum PhotoKitShotStatus: String, Codable, Sendable {
    /// A saved photo or frame matches the shot as Base asks for it.
    case covered
    /// A frame is close (too near, or the app cannot confirm what is in it). The note says what to check.
    case partial
    /// Nothing saved matches.
    case missing
    /// The app never tags this shot (behind the fence). Base's own photo upload asks for it.
    case notTagged
}

struct PhotoKitShot: Codable, Sendable, Equatable, Identifiable {
    var number: Int
    var title: String
    var status: PhotoKitShotStatus
    /// Relative to survey.json: "meter.jpg", "panel.jpg", or "capture/frames/000012.jpg".
    var image: String?
    var keyframeIndex: Int?
    /// ARFrame timestamp of that keyframe, as in capture/frames.json.
    var keyframeTimestamp: TimeInterval?
    /// Horizontal distance from the camera to what the shot is about.
    var distanceFeet: Double?
    /// "photo", "pose", or "pose+lookAround.<milestone>" when a look-around milestone picked the frame.
    var source: String?
    var note: String

    var id: Int { number }
}

/// A look-around milestone as it happened: which one, and the ARFrame timestamp then.
struct PhotoKitMoment: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case movedFarther
        case lookedLeft
        case lookedRight
        /// All three at once: the look-around was skipped or timed out, so the moment says nothing about a shot.
        case skipped
    }

    var kind: Kind
    var frameTimestamp: TimeInterval
    var cameraPosition: PlacementAnchor?
}

struct SurveyUnits: Codable, Sendable, Equatable {
    var distances: String = "feet"
    var angles: String = "radians"
    var positions: String = "meters_ARWorld"
}

enum DeviceProvenance {
    static let appVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }()

    static let buildNumber: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }()

    @MainActor
    static func iosVersion() -> String { UIDevice.current.systemVersion }

    @MainActor
    static func deviceModel() -> String { UIDevice.current.model }
}

enum Homeownership: String, Codable, Sendable {
    case own
    case rent
}

enum MeterNumberSource: String, Codable, Sendable {
    case manual
    case ocr
}

struct GeoFix: Codable, Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    /// Meters, as reported by Core Location. Not a survey-grade battery coordinate.
    var horizontalAccuracyMeters: Double
}

/// Snapshot of ERCOT load-zone + sample prices at survey time, plus the derived per-count math
/// the customer was shown on the decision card. Lets an engineer reading `survey.json` reproduce
/// the numbers with no ambiguity about which assumptions produced them.
struct GridContext: Codable, Sendable, Equatable {
    var loadZone: ERCOTLoadZone
    var sampleDate: Date
    var cheapHourPriceUSDPerMWh: Double
    var expensiveHourPriceUSDPerMWh: Double
    var cheapHourLabel: String
    var expensiveHourLabel: String
    var chosenCount: Int
    var capacityKWh: Double
    var dailyArbitrageUSD: Double
    var annualizedArbitrageLowUSD: Double
    var annualizedArbitrageHighUSD: Double
    var assumedHouseholdLoadKW: Double
    var hoursOfBackupAtAssumedLoad: Double
}

struct ElectricalEvidence: Codable, Sendable, Equatable {
    var meterPhotoFilename: String?
    /// Distinct from mainBreakerAmperage. A scan can fill this; the typed value is the one that is saved.
    var meterNumber: String?
    /// How the meter number was captured. Nil until a value is set.
    var meterNumberSource: MeterNumberSource?
    /// Confirmed by the user. Distinct from meterNumber. A scan can fill this.
    var mainBreakerAmperage: Int?
    /// Nil means the question has not been answered.
    var hasSolar: Bool?
    /// Nil means the question has not been answered.
    var hasPortableGenerator: Bool?
    /// Nil means the question has not been answered. Base treats an existing standby transfer switch as incompatible.
    var hasStandbyGenerator: Bool?
    /// Nil means the question has not been answered. Base does not install beside a third-party whole-home battery.
    var hasExistingWholeHomeBattery: Bool?
    /// Nil until the home form asks. 1 or 2. Two batteries require a 200A panel.
    var plannedBatteryCount: Int?
    /// The panel's bus rating in amps, typed from the panel label. Distinct from mainBreakerAmperage:
    /// the main breaker never stands in for the bus rating. Nil until the user enters it.
    var panelBusRatingAmps: Int?
    /// Home Info answer that decides whether the Live Survey looks for a gas meter. Nil means not answered.
    var gasMeterAnswer: GasMeterAnswer?
    /// How `mainBreakerAmperage` was captured (v6, optional). `.ocr` is a scan's read of the main breaker that the
    /// user has not confirmed, so the breaker rule stays unknown until they do. Nil with no value, and for older files.
    var mainBreakerAmperageSource: MeterNumberSource?
    /// The Live Survey's photo of the panel, taken when it read the main breaker (v6, optional). Nil until then.
    var panelPhotoFilename: String?
    /// The Live Survey's crop of the spot shown as the gas meter, "gas.jpg" (v8, optional). Nil until one is shown.
    var gasMeterPhotoFilename: String?
    /// Which OCR rule read `mainBreakerAmperage` from the panel (v8, optional). Nil when typed, or for older files.
    var mainBreakerAmperageBasis: MainBreakerBasis?

    /// Solar or two batteries need a 200A panel, so only then does the bus rating matter.
    var needsPanelBusRating: Bool {
        hasSolar == true || (plannedBatteryCount ?? 0) >= 2
    }
}

/// "No" is the homeowner's statement, not a measurement: it skips the gas step and records the gas check as their answer.
enum GasMeterAnswer: String, Codable, Sendable, CaseIterable {
    case yes
    case no
    case notSure
}

/// How the gas-meter mark was made (v8). `shownOnScan`: the user held the camera on a low spot by a wall during the
/// gas step; the scan did not recognize a gas meter, so the clearance is attested, not measured.
/// `recognized` is reserved for a detector that knows gas meters.
enum GasMarkSource: String, Codable, Sendable {
    case shownOnScan
    case recognized
}

/// How the Live Survey's gas step ended (v8). Nil when the step never ran.
enum GasStepOutcome: String, Codable, Sendable {
    case shown
    case timedOut
    case answeredNo
    case rejectedInReview
}

/// Which OCR rule read the main-breaker amperage (v8): on the row that says MAIN, the row next to MAIN, or the
/// largest handle print on a real panel box.
enum MainBreakerBasis: String, Codable, Sendable {
    case mainRow
    case mainNeighbor
    case largestHandle
}

/// The battery spot the Live Survey suggested by itself (v8). `alongWallFeet` is positive toward the panel.
struct BatterySpotSummary: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case placed
        case noMeter
        case noWall
        case allRejected
    }

    var status: Status
    var source = "autoSuggested"
    /// Along the meter wall from the meter, in feet. Positive toward the panel.
    var alongWallFeet: Double?
    var towardPanel: Bool?
    var candidatesTried = 0
    /// One short reason per rejected candidate, for engineers and DEBUG builds.
    var rejections: [String] = []
}

struct PlacementAnchor: Codable, Sendable, Equatable {
    var x: Float
    var y: Float
    var z: Float

    init(_ vector: SIMD3<Float>) {
        x = vector.x
        y = vector.y
        z = vector.z
    }

    var simd: SIMD3<Float> { SIMD3(x, y, z) }
}

enum PlacementMeasurementKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case batteryToMeter
    case batteryToWall
    case batteryToGasMeter
    case meterHeight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .batteryToMeter: "Battery to meter"
        case .batteryToWall: "Battery to wall"
        case .batteryToGasMeter: "Battery to gas meter"
        case .meterHeight: "Meter height"
        }
    }
}

enum MeasurementCaptureMethod: String, Codable, Sendable {
    case lidarMesh
    case existingPlane
    case estimatedPlane

    var title: String {
        switch self {
        case .lidarMesh: "LiDAR-supported surface"
        case .existingPlane: "Detected plane"
        case .estimatedPlane: "Estimated plane"
        }
    }
}

struct MeasurementEndpoint: Codable, Sendable, Equatable {
    var position: PlacementAnchor
    var captureMethod: MeasurementCaptureMethod
}

struct ConfirmedPlacementMeasurement: Codable, Sendable, Equatable, Identifiable {
    var kind: PlacementMeasurementKind
    var start: MeasurementEndpoint
    var end: MeasurementEndpoint
    var distanceFeet: Double
    var captureMethod: MeasurementCaptureMethod
    var confirmedAt: Date

    var id: String { kind.rawValue }
}

/// Who chose a meter or panel spot. Every source is an ARKit wall or depth hit; none of them is a user statement.
enum EquipmentLockSource: String, Codable, Sendable {
    /// Detector boxes on consecutive frames landed on the same wall spot.
    case detector
    /// The center dot held still on a wall spot while the detector's box covered it.
    case hold
    /// The user put the dot on it and tapped "Mark it myself". No detector agreement.
    case tap
    /// The Live Survey captured it by itself: a steady, sharp, well-lit view of it on a wall, and the same label
    /// value (the meter number, or the main-breaker rating beside "MAIN") read twice. The value is a suggestion.
    case scanCapture = "scan-capture"
}

struct PlacementEvidence: Codable, Sendable, Equatable {
    var batteryPlaced: Bool = false
    var meterMarked: Bool = false
    var gasMeterMarked: Bool = false
    var panelMarked: Bool = false
    /// The homeowner answered that there is no gas meter near the placement.
    var gasMeterNotPresent: Bool = false
    var lidarMeshAvailable: Bool = false
    var distanceToMeterFeet: Double?
    var distanceToWallFeet: Double?
    var distanceToGasMeterFeet: Double?
    /// Set by the placement workstream after a real clearance measurement. Nil stays unknown.
    var footprintIsClear: Bool?
    /// False when a classified window overlaps the cabinet. Nil until the wall behind the battery has been scanned.
    var clearOfWindows: Bool?
    /// False when the battery stands in the meter's or panel's 30 × 36 in working space. Nil until both are tapped on the wall.
    var keepsEquipmentAccess: Bool?
    /// Set after transfer-switch space beside the meter is actually measured. Nil stays unknown.
    var transferSwitchClearanceObserved: Bool?
    /// With the transfer-switch space measured blocked: clear wall the scan saw on each side of the meter (facing
    /// it), from the enclosure's edge to the nearest obstacle, in inches. Nil for a side not measured blocked.
    var transferSwitchFreeLeftInches: Double?
    var transferSwitchFreeRightInches: Double?
    /// User attestation (not measurement) that the 3 ft × 3 ft pad is clear. Rule engine falls back to this only if the measured field is nil.
    var footprintClearAttested: Bool?
    /// User attestation (not measurement) that space for a transfer switch beside the meter is available.
    var transferSwitchSpaceAttested: Bool?
    /// AR-owned measurements listed in AGENTS.md, not yet wired. Slots reserved so schema stays stable.
    var meterHeightFeet: Double?
    var frontWorkspaceWidthInches: Double?
    var frontWorkspaceDepthInches: Double?
    var batteryPosition: PlacementAnchor?
    var meterPosition: PlacementAnchor?
    var panelPosition: PlacementAnchor?
    var gasMeterPosition: PlacementAnchor?
    /// How the meter and panel positions were locked. Nil while that item is not marked.
    var meterLockSource: EquipmentLockSource?
    var panelLockSource: EquipmentLockSource?
    var batteryYawRadians: Float?
    /// When the placement snapshot was committed. Nil until a save happens.
    var snapshotTimestamp: Date?
    var confirmedMeasurements: [ConfirmedPlacementMeasurement] = []
    /// Explicit answer after positioning the 30 × 36 in overlay. Nil stays unknown.
    var frontWorkingSpaceIsClear: Bool?
    /// True when the meter and panel wall taps sit on the same wall (either side counts).
    /// Populated by `CorePlacementMeasurer.meterAndPanelSameWall` from the two wall locks.
    var meterAndPanelShareWall: Bool?
    var workingSpacePosition: PlacementAnchor?
    var workingSpaceYawRadians: Float?
    /// LiDAR mesh written next to survey.json. Nil when the phone had no reconstructed mesh.
    var pointCloudFilename: String?
    /// Manifest of the posed scan photos and LiDAR depth, relative to survey.json. Nil when nothing was captured.
    var captureManifestPath: String?
    var capturedFrameCount: Int?
    /// How the gas-meter mark was made (v8). Nil with no mark, and for older files.
    var gasMeterMarkSource: GasMarkSource?
    /// How the Live Survey's gas step ended (v8). Nil when it never ran.
    var gasStepOutcome: GasStepOutcome?
    /// The battery spot the scan suggested by itself (v8). Nil until the scan finishes.
    var batterySpot: BatterySpotSummary?

    init() {}
}

enum CheckStatus: String, Codable, Sendable {
    case pass
    case conflict
    case unknown
}

enum PlacementTone: String, Codable, Sendable {
    /// Every required check passed on measured evidence.
    case clear
    /// Every required check passed, but one or more passes rely on a user attestation instead of a measurement.
    case attested
    /// A required check has no measurement yet, and none conflict.
    case incomplete
    /// At least one check observed a conflict.
    case conflict
}

struct RuleResult: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var title: String
    var requirement: String
    var status: CheckStatus
    var usedMeasuredEvidence: Bool
    var isRequired: Bool
    var explanation: String
}
