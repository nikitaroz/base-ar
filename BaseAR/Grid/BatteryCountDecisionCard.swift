import SwiftUI

/// Full decision card for the Home form and onboarding — six-line ladder from capacity to disclaimer.
struct BatteryCountDecisionCard: View {
    let decision: BatteryCountDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(decision.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(decision.capacityLine)
                .font(.subheadline)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(decision.backupLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let arbitrageLine = decision.arbitrageLine {
                Text(arbitrageLine)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(decision.valueLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(decision.panelLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let priceSourceLine = decision.priceSourceLine {
                Text(priceSourceLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let disclaimerLine = decision.disclaimerLine {
                Text(disclaimerLine)
                    .font(.footnote.italic())
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [
            decision.title,
            decision.capacityLine,
            decision.backupLine,
            decision.arbitrageLine,
            decision.valueLine,
            decision.panelLine,
            decision.priceSourceLine,
            decision.disclaimerLine
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }
}

/// Compact two-line summary for the Review screen — no card chrome, sits inline with LabeledContent rows.
struct BatteryCountDecisionSummary: View {
    let decision: BatteryCountDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shortLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let priceLine {
                Text(priceLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var shortLine: String {
        // Capacity summary + short panel status. Panel wording follows the full card's copy.
        let capacityText: String
        if let count = decision.capturedGridContext?.chosenCount, count > 0 {
            capacityText = String(format: "%.1f kWh", decision.capturedGridContext?.capacityKWh ?? 0)
        } else {
            capacityText = "1–2 Cores"
        }
        return "\(capacityText) · \(shortPanelStatus)"
    }

    private var shortPanelStatus: String {
        let panel = decision.panelLine
        if panel.contains("Both counts fit") { return "panel fits both counts." }
        if panel.contains("needs 200 A to support") { return "panel needs 200 A to support two." }
        if panel.contains("has not been captured") { return "panel bus rating not captured." }
        if panel.contains("Two would need 200 A") { return "one Core fits panel; two would need 200 A." }
        return "see Home tile for panel status."
    }

    private var priceLine: String? {
        guard let context = decision.capturedGridContext else { return nil }
        return "\(context.loadZone.rawValue) wholesale $\(intFromDouble(context.cheapHourPriceUSDPerMWh))–$\(intFromDouble(context.expensiveHourPriceUSDPerMWh))/MWh on \(reviewDateFormatter.string(from: context.sampleDate))."
    }

    private func intFromDouble(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private let reviewDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}
