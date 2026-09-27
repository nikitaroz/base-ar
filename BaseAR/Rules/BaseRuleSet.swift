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
    /// Not a published Base limit: Base publishes only the 6 ft maximum. Kept until the team decides whether to drop it.
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
        windowClearance,
        equipmentAccess,
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
            // A scan's read of the handle is a suggestion until the user confirms it.
            if session.electrical.mainBreakerAmperageSource == .ocr {
                return .unknown("Read by scan as \(amps)A. Check it against the main breaker and confirm it.")
            }
            if austinMainBreakerRange.contains(amps) {
                // Typed, or a scan read the user confirmed: their reading of the label, not a measurement, the same
                // as the panel bus rating. It passes as attested, so with this rule required the best tone a survey
                // can reach is teal (`.attested`), never green, until the app measures the breaker itself.
                return RuleOutcome(status: .pass, usedMeasuredEvidence: false, explanation: "You confirmed the main breaker is \(amps)A, inside 150–200A. Your reading of the breaker, not a measurement.")
            }
            return .conflict("Confirmed main breaker is \(amps)A, outside the 150–200A Austin range.")
        }
    )

    private static let solarOrTwoBatteries = EligibilityRule(
        id: "solar-or-two-batteries",
        title: "Solar or two batteries",
        requirement: "Solar, or two batteries, requires a 200A panel.",
        isRequired: true,
        // Decided only from the panel's bus rating. Main-breaker amperage is a different number and never stands in for it.
        evaluate: { session in
            let electrical = session.electrical
            let busRating = electrical.panelBusRatingAmps
            if electrical.needsPanelBusRating {
                let reason = electrical.hasSolar == true ? "Solar was reported" : "Two batteries are planned"
                guard let busRating else {
                    return .unknown("\(reason). Main-breaker amperage is not the panel bus rating; confirm the panel's bus rating from the panel label.")
                }
                if busRating >= panelAmpsForSolarOrTwoBatteries {
                    // Typed from the panel label: the user's reading, not a measurement.
                    return RuleOutcome(status: .pass, usedMeasuredEvidence: false, explanation: "\(reason) and the bus rating typed from the panel label is \(busRating)A, which meets the 200A requirement.")
                }
                return .conflict("\(reason) and the panel label's bus rating is \(busRating)A. This case needs a 200A panel.")
            }
            if electrical.hasSolar == false, let count = electrical.plannedBatteryCount, count < 2 {
                // Decided from the homeowner's answers alone: attested, never a measurement.
                return RuleOutcome(status: .pass, usedMeasuredEvidence: false, explanation: "You reported no solar and fewer than two batteries, so the 200A panel requirement is not triggered. Your answer, not a measurement.")
            }
            if let busRating, busRating >= panelAmpsForSolarOrTwoBatteries {
                return RuleOutcome(status: .pass, usedMeasuredEvidence: false, explanation: "The bus rating typed from the panel label is \(busRating)A, which meets the 200A requirement whether or not solar or two batteries apply.")
            }
            return .unknown("Solar or planned battery count is still missing, so the 200A panel requirement cannot be decided. Main-breaker amperage is not the panel bus rating.")
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

    private static let windowClearance = EligibilityRule(
        id: "not-in-front-of-window",
        title: "Not in front of a window",
        requirement: "The battery cannot be placed in front of a window.",
        isRequired: true,
        evaluate: { session in
            guard session.placement.batteryPlaced else {
                return .unknown("The battery has not been placed.")
            }
            guard let clear = session.placement.clearOfWindows else {
                return .unknown("The wall behind the battery has not been scanned, so a window there was not checked.")
            }
            return clear
                ? .pass("The scanned wall behind the cabinet has no window in front of the battery.")
                : .conflict("A detected window overlaps the cabinet, so the battery is in front of a window.")
        }
    )

    private static let equipmentAccess = EligibilityRule(
        id: "meter-panel-access",
        title: "Not in front of the meter or panel",
        requirement: "Keep the \(Int(workingSpaceWidthInches)) × \(Int(workingSpaceDepthInches)) in working space in front of the meter and the panel free of the battery.",
        isRequired: true,
        evaluate: { session in
            guard session.placement.batteryPlaced else {
                return .unknown("The battery has not been placed.")
            }
            guard let clear = session.placement.keepsEquipmentAccess else {
                return .unknown("The meter and the panel both need to be found in the Live Survey to check the battery stays out of their working space.")
            }
            return clear
                ? .pass("The battery stays out of the working space in front of the meter and the panel.")
                : .conflict("The battery stands in the working space in front of the meter or the panel.")
        }
    )

    private static let gasMeterClearance = EligibilityRule(
        id: "gas-meter-clearance",
        title: "At least 3 ft from a gas meter",
        requirement: "The battery must be at least 3 ft from a gas meter.",
        isRequired: true,
        evaluate: { session in
            if session.placement.distanceToGasMeterFeet == nil, session.placement.gasMeterNotPresent {
                // The user's answer, not a measurement, so the best this home can reach is "attested".
                return RuleOutcome(status: .pass, usedMeasuredEvidence: false, explanation: "The user reported no visible gas meter. This is not a measured clearance or proof that no gas equipment is present.")
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
                return .unknown("Meter height was not measured. In the Live Survey, find the meter and point down at the ground below it.")
            }
            guard height.isFinite else {
                return .unknown("Meter height was not a valid measurement, so the height range was not checked.")
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
                return .unknown("The meter and the panel both need to be found on the wall in the Live Survey.")
            }
            return same
                ? .pass("The meter and panel marks face the same direction and lie on the same wall.")
                : .conflict("The meter and panel marks are not on the same wall.")
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
    guard let feet, feet.isFinite, feet > 0 else { return .unknown(missing) }
    let formatted = String(format: "%.1f ft", feet)
    return passes(feet) ? .pass(passText(formatted)) : .conflict(conflictText(formatted))
}
