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
        if session.electrical.breakerPhotoFilename == nil {
            items.append("Photo of the main disconnect or breaker")
        }
        let meterNumber = session.electrical.meterNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if meterNumber.isEmpty {
            items.append("Meter number")
        }
        if session.electrical.mainBreakerAmperage == nil {
            items.append("Confirmed main breaker amperage")
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
        if session.placement.screenshotFilename == nil {
            items.append("AR placement screenshot")
        }
        if !session.placement.batteryPlaced {
            items.append("AR placement of the battery")
        } else {
            if !session.placement.meterMarked {
                items.append("Electric meter marked in AR, for the 20 ft check")
            }
            if session.placement.distanceToWallFeet == nil {
                items.append("Wall clearance. No nearby wall plane was measured")
            }
            if !session.placement.gasMeterMarked {
                items.append("Gas meter marked in AR, for the 3 ft check")
            }
            if session.placement.footprintIsClear == nil {
                items.append("Clearance inside the 3 ft × 3 ft planning footprint")
            }
        }
        if session.placement.transferSwitchClearanceObserved == nil {
            items.append("Space for a transfer switch beside the meter")
        }
        return items
    }
}
