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
    static let minMeterHeightFeet = 3.0
    static let maxMeterHeightFeet = 6.0
    static let workingSpaceWidthInches = 30.0
    static let workingSpaceDepthInches = 36.0

    static let rules: [EligibilityRule] = [
        austinBreaker,
        solarOrTwoBatteries,
        planningFootprint,
        meterDistance,
        wallDistance,
        gasMeterClearance,
        transferSwitchSpace,
        meterHeight,
        frontWorkingSpace,
        meterAndPanelSameWall
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
            if let clear = session.placement.footprintIsClear {
                return clear
                    ? .pass("The \(side) ft × \(side) ft pad was measured clear.")
                    : .conflict("The \(side) ft × \(side) ft pad was measured as blocked.")
            }
            if session.placement.footprintClearAttested == true {
                return RuleOutcome(status: .pass, usedMeasuredEvidence: false, explanation: "The user attested the \(side) ft × \(side) ft pad is clear. Not a measurement.")
            }
            return .unknown("The preview draws a \(side) ft × \(side) ft pad. Clearance inside that pad was not measured from the scan.")
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
                missing: "Clearance from the battery to the wall has not been measured.",
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
            if session.placement.distanceToGasMeterFeet == nil, session.placement.gasMeterNotPresent {
                return .pass("No gas meter was observed near the placement.")
            }
            return distanceOutcome(
                feet: session.placement.distanceToGasMeterFeet,
                missing: "The gas meter was not marked, so clearance was not measured.",
                passes: { $0 >= minGasMeterDistanceFeet },
                passText: { "Measured distance to the marked gas meter is \($0), at least 3 ft." },
                conflictText: { "Measured distance to the marked gas meter is \($0), closer than 3 ft." }
            )
        }
    )

    private static let meterHeight = EligibilityRule(
        id: "meter-height",
        title: "Meter height",
        requirement: "The electric meter must be between \(Int(minMeterHeightFeet)) and \(Int(maxMeterHeightFeet)) ft off the ground.",
        isRequired: true,
        evaluate: { session in
            guard let height = session.placement.meterHeightFeet else {
                return .unknown("Meter height was not measured. Tap the ground below the meter and then the meter on the wall to measure it.")
            }
            let formatted = String(format: "%.1f ft", height)
            if height >= minMeterHeightFeet && height <= maxMeterHeightFeet {
                return .pass("Measured meter height is \(formatted), inside the \(Int(minMeterHeightFeet))–\(Int(maxMeterHeightFeet)) ft range.")
            }
            return .conflict("Measured meter height is \(formatted), outside the \(Int(minMeterHeightFeet))–\(Int(maxMeterHeightFeet)) ft range.")
        }
    )

    private static let meterAndPanelSameWall = EligibilityRule(
        id: "meter-panel-same-wall",
        title: "Meter and panel on the same wall",
        requirement: "The meter and the main breaker panel should sit on the same wall.",
        isRequired: true,
        evaluate: { session in
            guard let same = session.placement.meterAndPanelSameWall else {
                return .unknown("Same-wall check needs a wall tap on both the meter and the panel.")
            }
            return same
                ? .pass("The meter and panel wall taps face the same direction and lie on the same wall.")
                : .conflict("The meter and panel wall taps are not on the same wall.")
        }
    )

    private static let transferSwitchSpace = EligibilityRule(
        id: "transfer-switch-space",
        title: "Transfer switch beside the meter",
        requirement: "Leave a 13 in wide by about 3 ft tall space on the wall beside the meter, with 30 in of clearance out from the wall.",
        isRequired: true,
        evaluate: { session in
            if let observed = session.placement.transferSwitchClearanceObserved {
                return observed
                    ? .pass("The wall beside the meter was measured clear for a transfer switch (13 in wide, about 3 ft tall, 30 in out from the wall).")
                    : .conflict("The wall beside the meter was measured as blocked for the transfer switch.")
            }
            if session.placement.transferSwitchSpaceAttested == true {
                return RuleOutcome(status: .pass, usedMeasuredEvidence: false, explanation: "The user attested transfer-switch space beside the meter is available. Not a measurement.")
            }
            return .unknown("Space for a transfer switch beside the meter was not measured. Without a mesh scan it stays unknown.")
        }
    )

    private static let frontWorkingSpace = EligibilityRule(
        id: "front-working-space",
        title: "30 × 36 in front working space",
        requirement: "Confirm approximately 30 × 36 in of clear working space in front of the equipment.",
        isRequired: true,
        evaluate: { session in
            guard let clear = session.placement.frontWorkingSpaceIsClear else {
                return .unknown("Clearance in the 30 × 36 in working space was not measured from the scan.")
            }
            return clear
                ? .pass("The 30 × 36 in working space was measured clear.")
                : .conflict("The 30 × 36 in working space was measured as blocked.")
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
