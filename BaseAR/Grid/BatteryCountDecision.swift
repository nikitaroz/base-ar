import Foundation

/// Pure math helpers, exposed so future features (payback estimator, monthly report tile,
/// retail-rate-adjusted savings) can call the same functions with different inputs.
enum GridEconomics {
    static let baseCoreCapacityKWh: Double = 39.2

    static func capacity(cores: Int) -> Double {
        Double(max(cores, 0)) * baseCoreCapacityKWh
    }

    /// Hours of backup at a given continuous load. Simple division — round-trip losses not modelled.
    static func hoursOfBackup(capacityKWh: Double, loadKW: Double) -> Double {
        loadKW > 0 ? capacityKWh / loadKW : 0
    }

    /// Gross wholesale arbitrage for one full charge/discharge cycle at the day's spread.
    /// USD = kWh × ($/MWh spread) / 1000.
    static func dailyArbitrageUSD(capacityKWh: Double, cheapUSDPerMWh: Double, expensiveUSDPerMWh: Double) -> Double {
        capacityKWh * max(expensiveUSDPerMWh - cheapUSDPerMWh, 0) / 1000
    }

    /// Rough annualized range. Low bound: 250 productive days (spread big enough to profit).
    /// High bound: 365 days. The gap reflects that not every day cycles fully at wholesale.
    static func annualizedArbitrageUSD(daily: Double) -> (low: Double, high: Double) {
        (daily * 250, daily * 365)
    }
}

/// Rendered strings + captured snapshot for the "one or two Base Cores" decision card.
/// Pure logic, no SwiftUI. Generic in N Cores so future product tiers just change the UI.
struct BatteryCountDecision: Sendable, Equatable {
    let title: String                              // "One or two Base Cores"
    let capacityLine: String                       // "1 Core = 39.2 kWh · 2 Cores = 78.4 kWh · 3 Cores = 117.6 kWh"
    let backupLine: String                         // "At 3 kW household draw, ~13 h for one, ~26 h for two."
    let arbitrageLine: String?                     // nil when zone did not resolve
    let valueLine: String                          // qualitative wrap-up
    let panelLine: String                          // mirrors BaseRuleSet.solarOrTwoBatteries
    let priceSourceLine: String?                   // nil when zone did not resolve
    let disclaimerLine: String?                    // shown when any dollar or hour number is shown
    let capturedGridContext: GridContext?

    static func make(
        plannedCount: Int?,
        hasSolar: Bool?,
        panelBusRatingAmps: Int?,
        propertyIdentifier: String,
        sample: ERCOTSampleDay = GridService.sampleDay,
        assumedHouseholdLoadKW: Double = 3.0
    ) -> BatteryCountDecision {
        let zone = GridService.zone(for: propertyIdentifier)
        let zonePrice = zone.flatMap { sample.prices[$0] }

        // Capacity line — always shown, always exact.
        let capacityLine = "1 Core = 39.2 kWh · 2 Cores = 78.4 kWh · 3 Cores = 117.6 kWh"

        // Backup line — pure division, assumption stated in the copy.
        let hoursOne = Int((GridEconomics.hoursOfBackup(capacityKWh: GridEconomics.capacity(cores: 1), loadKW: assumedHouseholdLoadKW)).rounded())
        let hoursTwo = Int((GridEconomics.hoursOfBackup(capacityKWh: GridEconomics.capacity(cores: 2), loadKW: assumedHouseholdLoadKW)).rounded())
        let backupLine = "At a steady \(loadFormatted(assumedHouseholdLoadKW)) kW household draw, that's about ~\(hoursOne) h backup for one Core, ~\(hoursTwo) h for two."

        // Arbitrage line — only when we have prices.
        let (arbitrageLine, disclaimerLine) = arbitrageAndDisclaimer(zonePrice: zonePrice)

        // Value line — qualitative wrap-up.
        let valueLine = "Each additional Core doubles the peak-hour grid relief and roughly doubles the backup duration."

        // Panel line — mirrors BaseRuleSet.solarOrTwoBatteries so card and rule can't drift.
        let panelLine = panelLineText(plannedCount: plannedCount, hasSolar: hasSolar, panelBusRatingAmps: panelBusRatingAmps)

        // Price source line — same trigger as arbitrage line.
        let priceSourceLine = priceSourceLineText(zone: zone, zonePrice: zonePrice, sampleDate: sample.date)

        // Captured context for survey.json — only when zone resolved.
        let captured = capturedContext(
            zone: zone,
            zonePrice: zonePrice,
            sampleDate: sample.date,
            chosenCount: plannedCount ?? 0,
            assumedHouseholdLoadKW: assumedHouseholdLoadKW
        )

        return BatteryCountDecision(
            title: "One or two Base Cores",
            capacityLine: capacityLine,
            backupLine: backupLine,
            arbitrageLine: arbitrageLine,
            valueLine: valueLine,
            panelLine: panelLine,
            priceSourceLine: priceSourceLine,
            disclaimerLine: disclaimerLine,
            capturedGridContext: captured
        )
    }

    // MARK: - Composition helpers

    private static func arbitrageAndDisclaimer(zonePrice: ZonePrice?) -> (String?, String?) {
        guard let zonePrice else { return (nil, nil) }
        let capacity1 = GridEconomics.capacity(cores: 1)
        let capacity2 = GridEconomics.capacity(cores: 2)
        let daily1 = GridEconomics.dailyArbitrageUSD(
            capacityKWh: capacity1,
            cheapUSDPerMWh: zonePrice.cheapHourPriceUSDPerMWh,
            expensiveUSDPerMWh: zonePrice.expensiveHourPriceUSDPerMWh
        )
        let daily2 = GridEconomics.dailyArbitrageUSD(
            capacityKWh: capacity2,
            cheapUSDPerMWh: zonePrice.cheapHourPriceUSDPerMWh,
            expensiveUSDPerMWh: zonePrice.expensiveHourPriceUSDPerMWh
        )
        let annualized2 = GridEconomics.annualizedArbitrageUSD(daily: daily2)
        let arbitrage = "At today's sample $\(intUSD(zonePrice.cheapHourPriceUSDPerMWh)) → $\(intUSD(zonePrice.expensiveHourPriceUSDPerMWh))/MWh spread, one full daily cycle nets ~$\(usd(daily1)) gross · two Cores ~$\(usd(daily2)) · annualized ~$\(roundUSD(annualized2.low))–$\(roundUSD(annualized2.high))."
        let disclaimer = "Estimates assume a full charge/discharge cycle at wholesale rates on the sample day. Actual results depend on your utility rate plan, panel headroom, weather, and household load."
        return (arbitrage, disclaimer)
    }

    private static func panelLineText(plannedCount: Int?, hasSolar: Bool?, panelBusRatingAmps: Int?) -> String {
        // Match BaseRuleSet.solarOrTwoBatteries wording so the card and the rule stay coupled.
        guard let amps = panelBusRatingAmps else {
            return "Two Cores need a confirmed 200 A panel bus rating. The panel label has not been captured yet."
        }
        let needsTwoHundred = (hasSolar == true) || ((plannedCount ?? 0) >= 2)
        if amps >= 200 {
            return "Both counts fit the 200 A panel bus rating you confirmed."
        }
        if needsTwoHundred {
            return "A second Core doubles your peak grid relief, but your confirmed \(amps) A panel needs 200 A to support two Cores or solar-plus-battery."
        }
        return "One Core fits the \(amps) A panel bus rating you confirmed. Two would need 200 A."
    }

    private static func priceSourceLineText(zone: ERCOTLoadZone?, zonePrice: ZonePrice?, sampleDate: Date) -> String? {
        guard let zone, let zonePrice else { return nil }
        let dateText = sampleDateFormatter.string(from: sampleDate)
        return "Source: In \(zone.displayName) on \(dateText), ERCOT's wholesale price ran $\(usd(zonePrice.cheapHourPriceUSDPerMWh))/MWh at \(zonePrice.cheapHourLabel) to $\(usd(zonePrice.expensiveHourPriceUSDPerMWh))/MWh at \(zonePrice.expensiveHourLabel). Public wholesale settlement-point data — retail bills use different rates. Not a Base quote."
    }

    private static func capturedContext(
        zone: ERCOTLoadZone?,
        zonePrice: ZonePrice?,
        sampleDate: Date,
        chosenCount: Int,
        assumedHouseholdLoadKW: Double
    ) -> GridContext? {
        guard let zone, let zonePrice else { return nil }
        let capacityKWh = GridEconomics.capacity(cores: chosenCount)
        let daily = GridEconomics.dailyArbitrageUSD(
            capacityKWh: capacityKWh,
            cheapUSDPerMWh: zonePrice.cheapHourPriceUSDPerMWh,
            expensiveUSDPerMWh: zonePrice.expensiveHourPriceUSDPerMWh
        )
        let annualized = GridEconomics.annualizedArbitrageUSD(daily: daily)
        let hoursBackup = GridEconomics.hoursOfBackup(capacityKWh: capacityKWh, loadKW: assumedHouseholdLoadKW)
        return GridContext(
            loadZone: zone,
            sampleDate: sampleDate,
            cheapHourPriceUSDPerMWh: zonePrice.cheapHourPriceUSDPerMWh,
            expensiveHourPriceUSDPerMWh: zonePrice.expensiveHourPriceUSDPerMWh,
            cheapHourLabel: zonePrice.cheapHourLabel,
            expensiveHourLabel: zonePrice.expensiveHourLabel,
            chosenCount: chosenCount,
            capacityKWh: capacityKWh,
            dailyArbitrageUSD: daily,
            annualizedArbitrageLowUSD: annualized.low,
            annualizedArbitrageHighUSD: annualized.high,
            assumedHouseholdLoadKW: assumedHouseholdLoadKW,
            hoursOfBackupAtAssumedLoad: hoursBackup
        )
    }

    // MARK: - Number formatting

    private static func usd(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func intUSD(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private static func roundUSD(_ value: Double) -> String {
        let rounded = (value / 10).rounded() * 10
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: rounded)) ?? String(Int(rounded))
    }

    private static func loadFormatted(_ value: Double) -> String {
        // Trim trailing .0 so "3" reads better than "3.0".
        let rounded = (value * 10).rounded() / 10
        if rounded == floor(rounded) { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    private static let sampleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}
