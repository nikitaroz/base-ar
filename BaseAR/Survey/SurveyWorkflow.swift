import Foundation

enum SurveyStep: String, Codable, CaseIterable, Identifiable, Sendable {
    case safety, home, program, meter, meterContext, breaker, panelContext, placement, review
    var id: String { rawValue }
    var title: String {
        switch self {
        case .safety: "Before you walk outside"
        case .home: "Tell us about this home"
        case .program: "Confirm your utility"
        case .meter: "Read the electric meter"
        case .meterContext: "Show the meter surroundings"
        case .breaker: "Read the main disconnect"
        case .panelContext: "Show the panel and nearby equipment"
        case .placement: "Preview a battery location"
        case .review: "Review and share your draft"
        }
    }
    var instruction: String {
        switch self {
        case .safety: "Stay on safe, accessible ground. Never remove a cover, break a seal, operate a breaker, climb, or touch wiring. Stop if equipment is damaged or wet."
        case .home: "Confirm the property address before using location. Answer the energy setup questions so the photo checklist can adapt."
        case .program: "Read the utility name from your bill. A city name or GPS fix does not establish the utility, program, wiring topology, or eligibility."
        case .meter: "Point your camera at the electric meter (not the gas meter). The live scanner reads the printed ID automatically. Hold steady when it shows a value. The meter ID is not the cycling usage reading."
        case .meterContext: "Check your surroundings before stepping back. Show the full wall, ground, windows, doors, pipes and obstructions. Do not walk backward while looking at the screen."
        case .breaker: "Point your camera at the main disconnect. The live scanner reads the amperage automatically. Hold steady when it shows a value. This is not a branch breaker or the panel bus rating."
        case .panelContext: "Show where the panel sits and any safely visible nameplate. A panel bus rating is separate from main-breaker amperage. Do not guess an unreadable rating."
        case .placement: "Stand still to scan, then move slowly along safe ground. The app detects equipment, marks them in AR, and shows realtime clearance feedback as you preview the battery location. Weak tracking or missing measurements stay unknown."
        case .review: "Check the images and unresolved items. You can share an incomplete packet for help. Nothing is submitted to Base automatically, and no result authorizes installation."
        }
    }
}

enum UtilityProgram: String, Codable, CaseIterable, Identifiable, Sendable {
    case unknown, austinEnergy, retailChoice, otherUtility
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unknown: "I don't know yet"
        case .austinEnergy: "Austin Energy"
        case .retailChoice: "Retail-choice service (verify)"
        case .otherUtility: "Another utility / cooperative"
        }
    }
}

enum ContextPhoto: String, Codable, CaseIterable, Identifiable, Sendable {
    case meterWide, meterRight, meterLeft, adjacentWall, behindFence
    case panelOverview, panelSurroundings, panelNameplate, energyEquipment
    var id: String { rawValue }
    var title: String {
        switch self {
        case .meterWide: "Full meter wall and ground"
        case .meterRight: "Area to the right of the meter"
        case .meterLeft: "Area to the left of the meter"
        case .adjacentWall: "Adjacent wall, corner to corner"
        case .behindFence: "Behind the fence"
        case .panelOverview: "Whole panel / enclosure"
        case .panelSurroundings: "Panel location and surroundings"
        case .panelNameplate: "Safely visible panel nameplate"
        case .energyEquipment: "Existing solar / generator / battery equipment"
        }
    }
    var instruction: String {
        switch self {
        case .panelNameplate: "Capture the entire label only if it is already visible. Do not remove or open a cover. This photo goes to a reviewer; we do not infer a bus rating."
        case .energyEquipment: "Show existing energy equipment and its relationship to the meter. Do not operate it. Capture the overall setup for review."
        case .behindFence: "Only enter an area you own and can safely access. Show the ground and nearby wall; otherwise record why it needs review."
        default: "Keep the entire area in frame, including wall, ground and nearby obstructions. Stand still and check the image for blur before accepting it."
        }
    }
}

struct ContextEvidence: Codable, Equatable, Sendable {
    var filename: String
    var capturedAt: Date
    /// Human photo-quality attestation, never a machine quality score.
    var accepted: Bool = false
}

struct GuidedSurveyProgress: Codable, Equatable, Sendable {
    var currentStep: SurveyStep = .safety
    var safetyAcknowledged = false
    var program: UtilityProgram = .unknown
    var utilityName = ""
    var programAnswered = false
    var meterConfirmed = false
    var breakerConfirmed = false
    var fencePresent: Bool?
    var contextPhotos: [String: ContextEvidence] = [:]
    var deferred: [String: String] = [:]
}

enum SurveyWorkflow {
    static func photos(for step: SurveyStep, session: SurveySession) -> [ContextPhoto] {
        if step == .meterContext {
            var photos: [ContextPhoto] = [.meterWide, .meterRight, .meterLeft, .adjacentWall]
            if session.guidedProgress?.fencePresent == true { photos.append(.behindFence) }
            return photos
        }
        if step == .panelContext {
            var photos: [ContextPhoto] = [.panelOverview, .panelSurroundings, .panelNameplate]
            let e = session.electrical
            if e.hasSolar == true || e.hasPortableGenerator == true ||
                e.hasStandbyGenerator == true || e.hasExistingWholeHomeBattery == true {
                photos.append(.energyEquipment)
            }
            return photos
        }
        return []
    }

    static func issues(for step: SurveyStep, session s: SurveySession) -> [String] {
        let p = s.guidedProgress ?? GuidedSurveyProgress()
        switch step {
        case .safety: return p.safetyAcknowledged ? [] : ["Acknowledge the safety guidance."]
        case .home:
            var issues: [String] = []
            if s.propertyIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Enter the property address.") }
            if s.contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Enter your name.") }
            if !s.email.contains("@") || !s.email.contains(".") { issues.append("Check your email address.") }
            if s.phone.filter(\.isNumber).count < 7 { issues.append("Check your phone number.") }
            if s.homeownership == nil { issues.append("Answer own or rent.") }
            let e = s.electrical
            if e.hasSolar == nil || e.hasPortableGenerator == nil || e.hasStandbyGenerator == nil ||
                e.hasExistingWholeHomeBattery == nil || e.plannedBatteryCount == nil {
                issues.append("Finish the energy setup questions.")
            }
            return issues
        case .program: return p.programAnswered ? [] : ["Record your utility choice, including unknown if necessary."]
        case .meter:
            // With realtime feedback, a captured value (from scan or manual entry) is sufficient
            var issues: [String] = []
            if s.electrical.meterNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                issues.append("Scan or enter the meter number.")
            }
            if s.electrical.meterPhotoFilename == nil {
                issues.append("Capture at least one meter photo.")
            }
            return issues
        case .breaker:
            // With realtime feedback, a captured value is sufficient
            var issues: [String] = []
            if s.electrical.mainBreakerAmperage == nil || s.electrical.mainBreakerAmperage == 0 {
                issues.append("Scan or enter the main breaker amperage.")
            }
            if s.electrical.breakerPhotoFilename == nil {
                issues.append("Capture at least one breaker photo.")
            }
            return issues
        case .meterContext, .panelContext:
            var issues = photos(for: step, session: s).compactMap { photo -> String? in
                p.contextPhotos[photo.rawValue]?.accepted == true ? nil : "Capture and check: \(photo.title)."
            }
            if step == .meterContext && p.fencePresent == nil { issues.append("Answer whether a fence obstructs the area.") }
            return issues
        case .placement:
            return (!s.placement.batteryPlaced ? ["Preview a battery location or defer for a site visit."] : []) +
                (s.placement.screenshotFilename == nil || s.placement.captureIdentity == nil
                    ? ["Save one version-matched placement and screenshot, or defer this step."] : [])
        case .review: return []
        }
    }

    static func canContinue(_ step: SurveyStep, session: SurveySession) -> Bool {
        issues(for: step, session: session).isEmpty ||
            (step != .safety && session.guidedProgress?.deferred[step.rawValue] != nil)
    }
}
