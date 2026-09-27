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
        siteSpot,
        transferSwitchSpace,
        meterHeight,
        frontWorkingSpace,
        meterAndPanelShareWall
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

    /// The site check replaces the battery-position rules (pad, meter distance, wall distance, window, working-space
    /// access, gas clearance): the Live Survey places no battery. It asks once, from the finished mesh, whether a spot
    /// that meets all of them exists beside the meter. Found is measured; the gas part rests on how the gas meter was
    /// shown or answered, so a spot beside a gas meter the scan did not recognize, or "No gas meter" on Home Info,
    /// passes as attested (teal), never measured.
    static let siteSpotRuleID = "site-spot"

    private static let siteSpot = EligibilityRule(
        id: siteSpotRuleID,
        title: "Clear spot beside the meter",
        requirement: "A clear \(Int(footprintSideFeet)) ft × \(Int(footprintSideFeet)) ft ground spot within \(Int(maxWallDistanceFeet)) ft of the meter wall, within \(Int(maxMeterDistanceFeet)) ft of the meter, at least \(Int(minGasMeterDistanceFeet)) ft from a gas meter, not in front of a window, and out of the meter's and panel's working space.",
        isRequired: true,
        evaluate: { session in
            let placement = session.placement
            guard let spot = placement.batterySpot else {
                return .unknown("The site check runs when the Live Survey's look-around finishes.")
            }
            switch spot.status {
            case .noMeter:
                return .unknown("No meter was found on the wall, so the ground beside it was not checked.")
            case .noWall:
                return .unknown("Not enough of the ground and wall beside the meter was scanned to find a spot that meets Base's spacing rules.")
            case .allRejected:
                let reasons = siteSpotReasons(spot.rejections)
                return .conflict("Every scanned spot beside the meter breaks one of Base's spacing rules" + (reasons.isEmpty ? "." : ": \(reasons)."))
            case .placed:
                let found = "A spot that meets Base's spacing rules was found beside the meter."
                if placement.gasMeterPosition != nil {
                    // The scan does not recognize gas meters yet: a spot the user showed is their showing.
                    if placement.gasMeterMarkSource == .recognized {
                        return .pass(found + " It is at least \(Int(minGasMeterDistanceFeet)) ft from the gas meter.")
                    }
                    return RuleOutcome(status: .pass, usedMeasuredEvidence: false, explanation: found + " It is at least \(Int(minGasMeterDistanceFeet)) ft from the spot you showed as the gas meter. The scan did not recognize it; check the gas photo.")
                }
                if placement.gasMeterNotPresent {
                    return RuleOutcome(status: .pass, usedMeasuredEvidence: false, explanation: found + " You reported no gas meter, so the \(Int(minGasMeterDistanceFeet)) ft gas clearance rests on your answer.")
                }
                return .unknown(found + " The gas meter was not shown, so its \(Int(minGasMeterDistanceFeet)) ft clearance was not checked.")
            }
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

    private static let meterAndPanelShareWall = EligibilityRule(
        id: "meter-panel-same-wall",
        title: "Meter and panel on the same wall",
        requirement: "The meter and the main breaker panel should sit on the same wall (either side counts).",
        isRequired: true,
        evaluate: { session in
            guard let same = session.placement.meterAndPanelShareWall else {
                return .unknown("The meter and the panel both need to be found on the wall in the Live Survey.")
            }
            return same
                ? .pass("The meter and panel marks lie on the same wall.")
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
            if session.placement.lidarMeshAvailable {
                return .unknown("Not enough of the wall beside the meter was scanned to check space for a transfer switch.")
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

/// The distinct reasons in a site check's "+0.9 m: pad blocked" rejections, in first-seen order.
private func siteSpotReasons(_ rejections: [String]) -> String {
    var seen: [String] = []
    for rejection in rejections {
        let reason = rejection.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? rejection
        if !reason.isEmpty, !seen.contains(reason) { seen.append(reason) }
    }
    return seen.joined(separator: ", ")
}
