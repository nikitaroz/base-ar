import Foundation

/// Shared survey contract for electrical capture, AR placement, and rules/review.
/// Keep new evidence as optional fields so a check can stay unknown until a teammate fills it.
struct SurveySession: Codable, Sendable, Equatable, Identifiable {
    var schemaVersion: Int = 1
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

    static let locationDisclaimer = "Latitude, longitude, timestamp, and horizontal accuracy are the phone's reported property location, not the battery position."
    static let prototypeDisclaimer = "Preliminary survey only. This is not an electrical inspection, a code review, or installation approval."

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
            placementTone: .incomplete
        )
    }
}

enum Homeownership: String, Codable, Sendable {
    case own
    case rent
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
    /// Distinct from mainBreakerAmperage. Manual until OCR is connected.
    var meterNumber: String?
    /// Confirmed by the user. Distinct from meterNumber.
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

struct PlacementEvidence: Codable, Sendable, Equatable {
    var screenshotFilename: String?
    var batteryPlaced: Bool = false
    var meterMarked: Bool = false
    var gasMeterMarked: Bool = false
    var lidarMeshAvailable: Bool = false
    var distanceToMeterFeet: Double?
    var distanceToWallFeet: Double?
    var distanceToGasMeterFeet: Double?
    /// Set by the placement workstream after a real clearance measurement. Nil stays unknown.
    var footprintIsClear: Bool?
    /// Set after transfer-switch space beside the meter is actually measured. Nil stays unknown.
    var transferSwitchClearanceObserved: Bool?
    var batteryPosition: PlacementAnchor?
    var meterPosition: PlacementAnchor?
    var gasMeterPosition: PlacementAnchor?
    var batteryYawRadians: Float?
}

enum CheckStatus: String, Codable, Sendable {
    case pass
    case conflict
    case unknown
}

enum PlacementTone: String, Codable, Sendable {
    /// Every required check passed on measured evidence.
    case clear
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
