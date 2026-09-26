import SwiftUI

struct ReviewView: View {
    var store: SurveyStore
    var onStartOver: () -> Void

    @State private var showShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                disclaimer
                toneCard
                propertySection
                electricalSection
                placementSection
                checksSection
                missingSection
                shareSection
            }
            .padding()
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.exportForSharing()
        }
        .sheet(isPresented: $showShare) {
            ActivityShareSheet(urls: store.exportURLs)
        }
    }

    private var disclaimer: some View {
        Text(store.session.prototypeDisclaimer)
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private var toneCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ToneStyle.title(store.session.placementTone))
                .font(.headline)
            Text("Green means every required check passed on measured evidence. Amber means a required check is still unknown. Red means a measured conflict. Footprint clearance and transfer-switch space are not measured in this build, so a placement with no conflict stays amber.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ToneStyle.color(store.session.placementTone).opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    private var propertySection: some View {
        GroupBox("Property") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Name", value: display(store.session.contactName))
                LabeledContent("Email", value: display(store.session.email))
                LabeledContent("Phone", value: display(store.session.phone))
                LabeledContent("Own or rent", value: ownershipText)
                TextField(
                    "Property address or identifier",
                    text: Binding(
                        get: { store.session.propertyIdentifier },
                        set: { store.setPropertyIdentifier($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                locationSummary
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var locationSummary: some View {
        if let fix = store.session.propertyLocation {
            PropertyLocationMap(fix: fix)
            Text(fix.timestamp.formatted(date: .abbreviated, time: .standard))
            Text(String(format: "Reported horizontal accuracy: %.1f m", fix.horizontalAccuracyMeters))
            Text(store.session.propertyLocationDisclaimer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("Location was not available. No property fix was saved.")
                .foregroundStyle(.secondary)
            Text(store.session.propertyLocationDisclaimer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var electricalSection: some View {
        GroupBox("Electrical evidence") {
            VStack(alignment: .leading, spacing: 10) {
                evidenceImage(store.meterImage, label: "Round electric meter")
                evidenceImage(store.breakerImage, label: "Main disconnect or breaker")
                LabeledContent("Meter number", value: display(store.session.electrical.meterNumber))
                LabeledContent("Main breaker", value: breakerText)
                LabeledContent("Solar", value: yesNo(store.session.electrical.hasSolar))
                LabeledContent("Portable generator", value: yesNo(store.session.electrical.hasPortableGenerator))
                LabeledContent("Standby generator", value: yesNo(store.session.electrical.hasStandbyGenerator))
                LabeledContent("Existing whole-home battery", value: yesNo(store.session.electrical.hasExistingWholeHomeBattery))
                LabeledContent("Planned batteries", value: batteryCountText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var placementSection: some View {
        GroupBox("AR placement") {
            VStack(alignment: .leading, spacing: 8) {
                evidenceImage(store.placementImage, label: "Placement screenshot")
                LabeledContent("LiDAR mesh", value: store.session.placement.lidarMeshAvailable ? "Used" : "Not available")
                LabeledContent("Battery placed", value: store.session.placement.batteryPlaced ? "Yes" : "No")
                LabeledContent("Meter distance", value: feet(store.session.placement.distanceToMeterFeet))
                LabeledContent("Wall clearance", value: feet(store.session.placement.distanceToWallFeet))
                LabeledContent("Gas meter distance", value: feet(store.session.placement.distanceToGasMeterFeet))
                Text("GPS above is the phone's property fix, not where the battery was placed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var checksSection: some View {
        GroupBox("Checks") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.session.ruleResults) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle()
                                .fill(statusColor(result.status))
                                .frame(width: 10, height: 10)
                            Text(result.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(ToneStyle.statusTitle(result.status))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(statusColor(result.status))
                        }
                        Text(result.requirement)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(result.explanation)
                            .font(.footnote)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var missingSection: some View {
        GroupBox("Still missing") {
            VStack(alignment: .leading, spacing: 6) {
                if store.session.missingInformation.isEmpty {
                    Text("Nothing else is missing for this prototype.")
                } else {
                    ForEach(store.session.missingInformation, id: \.self) { item in
                        Text("• \(item)")
                            .font(.subheadline)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lastExportError = store.lastExportError {
                Text(lastExportError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if !store.exportURLs.isEmpty {
                Text("Saved on this iPhone as survey.json, with any photos beside it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                store.exportForSharing()
                showShare = store.lastExportError == nil && !store.exportURLs.isEmpty
            } label: {
                Text("Share survey")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button("Start over", role: .destructive, action: onStartOver)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var breakerText: String {
        if let amps = store.session.electrical.mainBreakerAmperage {
            return "\(amps) A"
        }
        return "Not confirmed"
    }

    private var ownershipText: String {
        switch store.session.homeownership {
        case nil: "Not answered"
        case .own: "Own"
        case .rent: "Rent"
        }
    }

    private func yesNo(_ value: Bool?) -> String {
        switch value {
        case nil: "Not answered"
        case false: "No"
        case true: "Yes"
        }
    }

    private var batteryCountText: String {
        if let count = store.session.electrical.plannedBatteryCount {
            return "\(count)"
        }
        return "Not captured"
    }

    private func display(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Not entered" : trimmed
    }

    private func feet(_ value: Double?) -> String {
        guard let value else { return "Not measured" }
        return String(format: "%.1f ft", value)
    }

    private func statusColor(_ status: CheckStatus) -> Color {
        switch status {
        case .pass: .green
        case .conflict: .red
        case .unknown: ToneStyle.color(.incomplete)
        }
    }

    @ViewBuilder
    private func evidenceImage(_ image: UIImage?, label: String) -> some View {
        if let image {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(label)
            }
        } else {
            Text("\(label): not saved")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    var urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
