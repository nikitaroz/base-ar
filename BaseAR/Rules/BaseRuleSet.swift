import Foundation

/// Published Base thresholds used by this prototype.
/// Austin main-breaker range and the solar / two-battery panel rule come from Base's
/// electrical requirements. Distances and the 3 ft pad come from Base's siting guidance.
/// Edit these constants to reconfigure the rule set. Do not mark a check passed without evidence.
enum BaseRuleSet {
    static let austinMainBreakerRange = 150...200
    static let panelAmpsForSolarOrTwoBatteries = 200
    static let maxMeterDistanceFeet = 20.0
    static let maxWallDistanceFeet = 1.0
    static let minGasMeterDistanceFeet = 3.0
    static let footprintSideFeet = 3.0

    static let rules: [EligibilityRule] = [
        austinBreaker,
        solarOrTwoBatteries,
        planningFootprint,
        meterDistance,
        wallDistance,
        gasMeterClearance,
        transferSwitchSpace
    ]

    private static let austinBreaker = EligibilityRule(
        id: "austin-main-breaker",
        title: "Austin main breaker",
        requirement: "In Austin the main breaker must be 150–200A.",
        isRequired: true,
        evaluate: { session in
            guard let amps = session.electrical.mainBreakerAmperage else {
                return .unknown("Main breaker amperage has not been confirmed.")
            }
            if austinMainBreakerRange.contains(amps) {
                return .pass("Confirmed main breaker is \(amps)A, inside 150–200A.")
            }
            return .conflict("Confirmed main breaker is \(amps)A, outside the 150–200A Austin range.")
        }
    )

    private static let solarOrTwoBatteries = EligibilityRule(
        id: "solar-or-two-batteries",
        title: "Solar or two batteries",
        requirement: "Solar, or two batteries, requires a 200A panel.",
        isRequired: true,
        evaluate: { session in
            guard let amps = session.electrical.mainBreakerAmperage else {
                return .unknown("Main breaker amperage has not been confirmed.")
            }
            if amps >= panelAmpsForSolarOrTwoBatteries {
                return .pass("Confirmed main breaker is \(amps)A, which covers solar and a two-battery system.")
            }
            let hasSolar = session.electrical.hasSolar
            let count = session.electrical.plannedBatteryCount
            if hasSolar == true || (count ?? 0) >= 2 {
                let reason = hasSolar == true ? "Solar was reported" : "Two batteries are planned"
                return .conflict("\(reason) and the confirmed main breaker is \(amps)A. This case needs 200A.")
            }
            if hasSolar == false, let count, count < 2 {
                return .pass("Solar was reported as not present and fewer than two batteries are planned, so the 200A requirement does not apply.")
            }
            return .unknown("Confirmed main breaker is \(amps)A. Solar or planned battery count is still missing, so the 200A requirement cannot be decided.")
        }
    )

    private static let planningFootprint = EligibilityRule(
        id: "planning-footprint",
        title: "3 ft × 3 ft footprint",
        requirement: "Each battery needs a 3 ft × 3 ft planning footprint.",
        isRequired: true,
        evaluate: { session in
            let side = Int(footprintSideFeet)
            guard session.placement.batteryPlaced else {
                return .unknown("The battery has not been placed, so the \(side) ft pad was not checked on site.")
            }
            guard let clear = session.placement.footprintIsClear else {
                return .unknown("The preview draws a \(side) ft × \(side) ft pad. Clearance inside that pad was not measured.")
            }
            return clear
                ? .pass("The \(side) ft × \(side) ft pad was measured clear.")
                : .conflict("The \(side) ft × \(side) ft pad was measured as blocked.")
        }
    )

    private static let meterDistance = EligibilityRule(
        id: "meter-distance",
        title: "Within 20 ft of the meter",
        requirement: "The battery should be within 20 ft of the electric meter.",
        isRequired: true,
        evaluate: { session in
            distanceOutcome(
                feet: session.placement.distanceToMeterFeet,
                missing: "The battery and electric meter have not both been placed, so this distance was not measured.",
                passes: { $0 <= maxMeterDistanceFeet },
                passText: { "Measured distance to the electric meter is \($0), within 20 ft." },
                conflictText: { "Measured distance to the electric meter is \($0), farther than 20 ft." }
            )
        }
    )

    private static let wallDistance = EligibilityRule(
        id: "wall-distance",
        title: "Within 1 ft of the wall",
        requirement: "The battery should be within 1 ft of the wall.",
        isRequired: true,
        evaluate: { session in
            distanceOutcome(
                feet: session.placement.distanceToWallFeet,
                missing: "No wall plane was close enough to measure clearance from the battery.",
                passes: { $0 <= maxWallDistanceFeet },
                passText: { "Measured clearance to the nearest detected wall is \($0), within 1 ft." },
                conflictText: { "Measured clearance to the nearest detected wall is \($0), more than 1 ft." }
            )
        }
    )

    private static let gasMeterClearance = EligibilityRule(
        id: "gas-meter-clearance",
        title: "At least 3 ft from a gas meter",
        requirement: "The battery must be at least 3 ft from a gas meter.",
        isRequired: true,
        evaluate: { session in
            distanceOutcome(
                feet: session.placement.distanceToGasMeterFeet,
                missing: "The gas meter was not marked, so clearance was not measured.",
                passes: { $0 >= minGasMeterDistanceFeet },
                passText: { "Measured distance to the marked gas meter is \($0), at least 3 ft." },
                conflictText: { "Measured distance to the marked gas meter is \($0), closer than 3 ft." }
            )
        }
    )

    private static let transferSwitchSpace = EligibilityRule(
        id: "transfer-switch-space",
        title: "Transfer switch beside the meter",
        requirement: "Leave space for a transfer switch on the wall beside the meter.",
        isRequired: true,
        evaluate: { session in
            guard let observed = session.placement.transferSwitchClearanceObserved else {
                return .unknown("Space for a transfer switch beside the meter was not measured.")
            }
            return observed
                ? .pass("Transfer-switch space beside the meter was measured as available.")
                : .conflict("Transfer-switch space beside the meter was measured as blocked.")
        }
    )
}

/// `passText` and `conflictText` receive the distance already formatted, such as "4.2 ft".
private func distanceOutcome(
    feet: Double?,
    missing: String,
    passes: (Double) -> Bool,
    passText: (String) -> String,
    conflictText: (String) -> String
) -> RuleOutcome {
    guard let feet else { return .unknown(missing) }
    let formatted = String(format: "%.1f ft", feet)
    return passes(feet) ? .pass(passText(formatted)) : .conflict(conflictText(formatted))
}
