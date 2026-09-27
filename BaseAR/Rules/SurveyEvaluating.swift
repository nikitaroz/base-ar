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

enum MissingInformation {
    static func list(for session: SurveySession) -> [String] {
        var items: [String] = []
        if session.propertyIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append("Property address or identifier")
        }
        for (value, label) in [
            (session.contactName, "Name"),
            (session.email, "Email"),
            (session.phone, "Phone")
        ] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(label)
        }
        if session.propertyLocation == nil {
            items.append("Phone location for the property: latitude, longitude, time, and horizontal accuracy")
        }
        if session.electrical.meterPhotoFilename == nil {
            items.append("Photo of the round electric meter")
        }
        let meterNumber = session.electrical.meterNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if meterNumber.isEmpty {
            items.append("Meter number")
        } else if session.electrical.meterNumberSource == .ocr {
            items.append("Check the meter number the scan read")
        }
        if session.electrical.mainBreakerAmperage == nil {
            items.append("Confirmed main breaker amperage")
        } else if session.electrical.mainBreakerAmperageSource == .ocr {
            items.append("Check the main breaker amperage the scan read")
        }
        if session.electrical.needsPanelBusRating, session.electrical.panelBusRatingAmps == nil {
            items.append("Panel bus rating from the panel label, for solar or two batteries")
        }
        if session.homeownership == nil {
            items.append("Whether you own or rent the home")
        }
        if session.electrical.hasSolar == nil {
            items.append("Whether the home has solar")
        }
        if session.electrical.hasPortableGenerator == nil {
            items.append("Whether the home has a portable generator")
        }
        if session.electrical.hasStandbyGenerator == nil {
            items.append("Whether the home has a whole-home standby generator")
        }
        if session.electrical.hasExistingWholeHomeBattery == nil {
            items.append("Whether the home already has a whole-home battery")
        }
        if session.electrical.plannedBatteryCount == nil {
            items.append("Planned battery count")
        }
        if !session.gasMeterQuestionAnswered {
            items.append("Whether there is a gas meter outside")
        }
        if !session.placement.batteryPlaced {
            items.append("AR placement of the battery")
        } else {
            if !session.placement.meterMarked {
                items.append("Electric meter marked in AR, for the 20 ft check")
            }
            if session.placement.distanceToWallFeet == nil {
                items.append("Confirmed battery-to-wall measurement")
            }
            if !session.placement.gasMeterMarked && !session.placement.gasMeterNotPresent {
                items.append("Gas meter marked in AR, for the 3 ft check")
            }
            if session.placement.footprintIsClear == nil {
                items.append("Clearance inside the 3 ft × 3 ft planning footprint")
            }
            if session.placement.clearOfWindows == nil {
                items.append("Whether the battery is in front of a window")
            }
            if session.placement.keepsEquipmentAccess == nil {
                items.append("Whether the battery blocks the meter or panel working space")
            }
        }
        if session.placement.meterHeightFeet == nil {
            items.append("Confirmed meter height")
        }
        if session.placement.frontWorkingSpaceIsClear == nil {
            items.append("30 × 36 in front working-space confirmation")
        }
        if session.placement.transferSwitchClearanceObserved == nil {
            items.append("Space for a transfer switch beside the meter")
        }
        if session.placement.meterAndPanelShareWall == nil {
            items.append("Whether the meter and breaker panel share a wall")
        }
        return items
    }
}

extension SurveySession {
    /// Home Info's gas question. A gas meter marked on the scan answers it too.
    var gasMeterQuestionAnswered: Bool {
        electrical.gasMeterAnswer != nil || placement.gasMeterMarked
    }
}
