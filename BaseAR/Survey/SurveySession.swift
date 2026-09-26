import Foundation
import UIKit

/// Shared survey contract for electrical capture, AR placement, and rules/review.
/// Keep new evidence as optional fields so a check can stay unknown until a teammate fills it.
struct SurveySession: Codable, Sendable, Equatable, Identifiable {
    var schemaVersion: Int = 6
    /// Optional so version-4 packets remain decodable.
    var guidedProgress: GuidedSurveyProgress?
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
    var electrical: ElectricalEvidence
    var placement: PlacementEvidence
    var ruleResults: [RuleResult]
    var missingInformation: [String]
    var placementTone: PlacementTone
    /// Battery model selected for AR preview. Always "base-core" after commit 71ac660.
    var selectedBatteryModelId: String = "base-core"
    /// Fixed labels so a Base engineer reading the JSON knows units without inferring.
    var units: SurveyUnits
    /// App/device provenance for support and reproducibility.
    var appVersion: String
    var buildNumber: String
    var iosVersion: String
    var deviceModel: String

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

struct ElectricalEvidence: Codable, Sendable, Equatable {
    var meterPhotoFilename: String?
    var breakerPhotoFilename: String?
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

/// A measured observation and an exported screenshot are different lifecycle states.
struct PlacementObservationIdentity: Codable, Sendable, Equatable {
    var scanID: UUID
    var revision: UInt64
    var batteryModelID: String
    var trackingIsNormal: Bool
    var observedAt: Date
}

/// Binds a durable image to the exact scan, scene revision and battery model measured.
struct PlacementCaptureIdentity: Codable, Sendable, Equatable {
    var captureID: UUID
    var scanID: UUID
    var revision: UInt64
    var batteryModelID: String
    var capturedAt: Date
}

struct PlacementEvidence: Codable, Sendable, Equatable {
    /// Optional for decoding older drafts; absent provenance cannot pass spatial checks.
    var observationIdentity: PlacementObservationIdentity?
    var captureIdentity: PlacementCaptureIdentity?
    var screenshotFilename: String?
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
    /// Set after transfer-switch space beside the meter is actually measured. Nil stays unknown.
    var transferSwitchClearanceObserved: Bool?
    /// User attestation (not measurement) that the 3 ft × 3 ft pad is clear. Rule engine falls back to this only if the measured field is nil.
    var footprintClearAttested: Bool?
    /// User attestation (not measurement) that space for a transfer switch beside the meter is available.
    var transferSwitchSpaceAttested: Bool?
    /// AR-owned measurements listed in AGENTS.md, not yet wired. Slots reserved so schema stays stable.
    var meterHeightFeet: Double?
    var frontWorkspaceWidthInches: Double?
    var frontWorkspaceDepthInches: Double?
    var meterAndPanelSameWall: Bool?
    var batteryPosition: PlacementAnchor?
    var meterPosition: PlacementAnchor?
    var panelPosition: PlacementAnchor?
    var gasMeterPosition: PlacementAnchor?
    var batteryYawRadians: Float?
    /// When the placement snapshot was committed. Nil until a save happens.
    var snapshotTimestamp: Date?
    var confirmedMeasurements: [ConfirmedPlacementMeasurement] = []
    /// Explicit answer after positioning the 30 × 36 in overlay. Nil stays unknown.
    var frontWorkingSpaceIsClear: Bool?
    /// Explicit homeowner observation; no geometry-only inference is accepted.
    var meterAndPanelShareWall: Bool?
    var workingSpacePosition: PlacementAnchor?
    var workingSpaceYawRadians: Float?
    /// LiDAR mesh written next to survey.json. Nil when the phone had no reconstructed mesh.
    var pointCloudFilename: String?

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
