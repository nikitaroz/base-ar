import Foundation

/// Rules/review boundary. Replace or extend the rule list without changing capture or AR.
protocol SurveyEvaluating: Sendable {
    func evaluate(_ session: SurveySession) -> SurveyAssessment
}

struct BaseSurveyEvaluator: SurveyEvaluating {
    var rules: [EligibilityRule]

    init(rules: [EligibilityRule] = BaseRuleSet.rules) {
        self.rules = rules
    }

    func evaluate(_ session: SurveySession) -> SurveyAssessment {
        let results = rules.map { rule in
            let outcome = rule.evaluate(session)
            return RuleResult(
                id: rule.id,
                title: rule.title,
                requirement: rule.requirement,
                status: outcome.status,
                usedMeasuredEvidence: outcome.usedMeasuredEvidence,
                isRequired: rule.isRequired,
                explanation: outcome.explanation
            )
        }
        return SurveyAssessment(
            results: results,
            placementTone: PlacementTonePolicy.tone(for: results),
            missingInformation: MissingInformation.list(for: session)
        )
    }
}

/// One missing item and the step that fixes it. Review's "What's missing" rows and the step bar's checkmarks
/// both count these, so a step never shows done while Review still lists something for it.
struct MissingItem: Sendable, Equatable {
    enum Step: Sendable, Equatable {
        /// Home Info (and the phone's property fix, which Home Info asks for).
        case home
        /// The numbers the Live Survey reads (or the user types in Electrical): meter photo and number, main breaker.
        case electrical
        /// Everything else the Live Survey measures, including the site check.
        case scan
    }

    var step: Step
    var text: String
}

enum MissingInformation {
    /// The plain list saved in survey.json. Same items and order as `items(for:)`.
    static func list(for session: SurveySession) -> [String] {
        items(for: session).map(\.text)
    }

    static func items(for session: SurveySession) -> [MissingItem] {
        var items: [MissingItem] = []
        func add(_ step: MissingItem.Step, _ text: String) {
            items.append(MissingItem(step: step, text: text))
        }
        if session.propertyIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.home, "Property address or identifier")
        }
        for (value, label) in [
            (session.contactName, "Name"),
            (session.email, "Email"),
            (session.phone, "Phone")
        ] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.home, label)
        }
        if session.propertyLocation == nil {
            add(.home, "Phone location for the property: latitude, longitude, time, and horizontal accuracy")
        }
        if session.electrical.meterPhotoFilename == nil {
            add(.electrical, "Photo of the round electric meter")
        }
        let meterNumber = session.electrical.meterNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if meterNumber.isEmpty {
            add(.electrical, "Meter number")
        } else if session.electrical.meterNumberSource == .ocr {
            add(.electrical, "Check the meter number the scan read")
        }
        if session.electrical.mainBreakerAmperage == nil {
            add(.electrical, "Confirmed main breaker amperage")
        } else if session.electrical.mainBreakerAmperageSource == .ocr {
            add(.electrical, "Check the main breaker amperage the scan read")
        }
        if session.electrical.needsPanelBusRating, session.electrical.panelBusRatingAmps == nil {
            add(.electrical, "Panel bus rating from the panel label, for solar or two batteries")
        }
        if session.homeownership == nil {
            add(.home, "Whether you own or rent the home")
        }
        if session.electrical.hasSolar == nil {
            add(.home, "Whether the home has solar")
        }
        if session.electrical.hasPortableGenerator == nil {
            add(.home, "Whether the home has a portable generator")
        }
        if session.electrical.hasStandbyGenerator == nil {
            add(.home, "Whether the home has a whole-home standby generator")
        }
        if session.electrical.hasExistingWholeHomeBattery == nil {
            add(.home, "Whether the home already has a whole-home battery")
        }
        if session.electrical.plannedBatteryCount == nil {
            add(.home, "Planned battery count")
        }
        if !session.gasMeterQuestionAnswered {
            add(.home, "Whether there is a gas meter outside")
        }
        // The site check the Live Survey runs by itself at the finish. A scan that found no clear spot is a
        // finding (Review says so), not a missing item.
        switch SiteCheck.of(session) {
        case .notRun:
            add(.scan, "Site check beside the meter (the Live Survey runs it when the look-around finishes)")
        case .noMeter:
            add(.scan, "Electric meter found on the scan, for the site check")
        case .notEnoughScanned:
            add(.scan, "More of the ground beside the meter scanned, for the site check")
        case .noClearSpot:
            break
        case .found where session.placement.batterySpot?.source == BatterySpotPlanner.source:
            // The site check measured every spacing rule on the spot itself; only the gas answer can be open.
            if !session.placement.gasMeterMarked && !session.placement.gasMeterNotPresent {
                add(.scan, "Gas meter shown on the scan, for the 3 ft check")
            }
        case .found:
            if !session.placement.meterMarked {
                add(.scan, "Electric meter marked on the scan, for the 20 ft check")
            }
            if session.placement.distanceToWallFeet == nil {
                add(.scan, "Distance from the spot to the meter wall")
            }
            if !session.placement.gasMeterMarked && !session.placement.gasMeterNotPresent {
                add(.scan, "Gas meter shown on the scan, for the 3 ft check")
            }
            if session.placement.clearOfWindows == nil {
                add(.scan, "Whether the spot is in front of a window")
            }
            if session.placement.keepsEquipmentAccess == nil {
                add(.scan, "Whether the spot blocks the meter or panel working space")
            }
        }
        if !session.placement.panelMarked || session.electrical.panelPhotoFilename == nil {
            add(.scan, "Breaker panel found on the scan, with a clear photo of the whole panel")
        }
        if session.placement.meterHeightFeet == nil {
            add(.scan, "Confirmed meter height")
        }
        if session.placement.frontWorkingSpaceIsClear == nil {
            add(.scan, "30 × 36 in front working-space confirmation")
        }
        if session.placement.transferSwitchClearanceObserved == nil {
            add(.scan, "Space for a transfer switch beside the meter")
        }
        if session.placement.meterAndPanelShareWall == nil {
            add(.scan, "Whether the meter and breaker panel share a wall")
        }
        return items
    }
}

/// The one site check the Live Survey runs by itself after the look-around: is there a clear 3 × 3 ft ground spot
/// beside the meter that meets Base's spacing rules. Nothing is drawn or placed on the camera; this only reads what
/// the scan saved (`batterySpot` and the spot's measured checks), so Review and "What's missing" say the same thing.
enum SiteCheck: Equatable, Sendable {
    /// The Live Survey has not finished the look-around yet.
    case notRun
    /// No meter was found, so there was nothing to check beside.
    case noMeter
    /// Some of the ground or wall beside the meter was never scanned: unknown, not a conflict.
    case notEnoughScanned
    /// Everything beside the meter was scanned and every spot was blocked: a measured conflict.
    case noClearSpot
    /// A spot that meets the spacing rules was found. `measured` is false when its pad rests on an answer.
    case found(measured: Bool)

    static func of(_ session: SurveySession) -> SiteCheck {
        let placement = session.placement
        if let spot = placement.batterySpot {
            switch spot.status {
            case .placed where spot.source == BatterySpotPlanner.source:
                // The site check passes a spot only when every check on it was measured clear. The gas part is
                // measured only when the scan recognized the gas meter; a spot the user showed, or "No", is an answer.
                let gasMeasured = placement.gasMeterPosition != nil && placement.gasMeterMarkSource == .recognized
                return .found(measured: gasMeasured)
            case .placed:
                break
            case .noMeter:
                return .noMeter
            case .noWall:
                return .notEnoughScanned
            case .allRejected:
                let unscanned = spot.candidatesTried == 0
                    || spot.rejections.contains { $0.hasSuffix(BatterySpotPlanner.notScanned) }
                return unscanned ? .notEnoughScanned : .noClearSpot
            }
        } else if !placement.batteryPlaced {
            return .notRun
        }
        if placement.footprintIsClear == false || placement.clearOfWindows == false
            || placement.keepsEquipmentAccess == false {
            return .noClearSpot
        }
        if placement.footprintIsClear == true { return .found(measured: true) }
        if placement.footprintClearAttested == true { return .found(measured: false) }
        return .notEnoughScanned
    }
}

extension SurveySession {
    /// Home Info's gas question. A gas meter marked on the scan answers it too.
    var gasMeterQuestionAnswered: Bool {
        electrical.gasMeterAnswer != nil || placement.gasMeterMarked
    }
}
