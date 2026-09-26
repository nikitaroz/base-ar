import SwiftUI

struct ReviewView: View {
    var store: SurveyStore
    var onEdit: (HubRoute) -> Void
    var onStartOver: () -> Void

    @State private var showShare = false
    @State private var confirmStartOver = false
    @State private var propertyExpanded = false
    @State private var electricalExpanded = false
    @State private var placementExpanded = false
    @State private var checksExpanded = false
    @State private var jevClient = TypeSafeJevClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                disclaimer
                readinessCard
                guidedEvidence
                if !nextActions.isEmpty {
                    nextActionsCard
                }
                TypeSafeJevAdvisoryView(session: store.session, client: jevClient)
                details
                jsonPreviewSection
                shareSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Start over", systemImage: "arrow.counterclockwise", role: .destructive) {
                        confirmStartOver = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Survey options")
            }
        }
        .alert("Start over?", isPresented: $confirmStartOver) {
            Button("Cancel", role: .cancel) {}
            Button("Delete survey", role: .destructive, action: onStartOver)
        } message: {
            Text("This deletes the current answers, photos, placement, and local survey file. This can’t be undone.")
        }
        .task {
            store.exportForSharing()
        }
        .sheet(isPresented: $showShare) {
            ActivityShareSheet(urls: store.exportURLs)
        }
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(store.session.prototypeDisclaimer)
            } icon: {
                Image(systemName: "info.circle.fill")
            }
            .font(.footnote)
            Text(ToneStyle.title(store.session.placementTone))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToneStyle.color(store.session.placementTone))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private var guidedEvidence: some View {
        GroupBox("Guided capture and human review") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Photo completion is not installation approval. Meter replacement, connection topology, program eligibility and local clearances still need qualified review.")
                    .font(.footnote)
                LabeledContent("Utility (self-reported)", value: store.session.guidedProgress?.program.title ?? "Unknown")
                ForEach(SurveyStep.allCases.filter { $0 != .review }) { step in
                    let issues = SurveyWorkflow.issues(for: step, session: store.session)
                    if !issues.isEmpty || store.session.guidedProgress?.deferred[step.rawValue] != nil {
                        Button("Revisit: \(step.title)") {
                            store.setGuidedStep(step)
                            onEdit(.guide)
                        }
                        if let reason = store.session.guidedProgress?.deferred[step.rawValue] {
                            Text("Needs review: \(reason)").font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }
                ForEach(ContextPhoto.allCases) { slot in
                    if let image = store.contextImage(slot) {
                        DisclosureGroup(slot.title) {
                            evidenceImage(image, label: slot.title)
                            Text(store.session.guidedProgress?.contextPhotos[slot.rawValue]?.accepted == true ? "User checked photo quality" : "Photo quality not confirmed")
                                .font(.caption)
                        }
                    }
                }
                Button("Open all guided steps") { onEdit(.guide) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(readinessTitle, systemImage: readinessSymbol)
                .font(.title3.bold())
                .foregroundStyle(readinessColor)
            Text(readinessMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var nextActionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Next actions")
                .font(.headline)
                .padding(.bottom, 8)
            ForEach(nextActions) { action in
                Button {
                    onEdit(action.route)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: action.symbol)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .foregroundStyle(.primary)
                            Text("\(action.count) missing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if action.id != nextActions.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Survey details")
                .font(.headline)

            detailCard(title: "Property", symbol: "house.fill", isExpanded: $propertyExpanded) {
                propertyDetails
                editButton("Edit home information", route: .home)
            }

            detailCard(title: "Electrical evidence", symbol: "bolt.fill", isExpanded: $electricalExpanded) {
                electricalDetails
                HStack {
                    editButton("Edit meter", route: .meter)
                    editButton("Edit breaker", route: .breaker)
                }
            }

            detailCard(title: "Site measurements", symbol: "arkit", isExpanded: $placementExpanded) {
                placementDetails
                editButton("Edit site measurements", route: .placement)
            }

            detailCard(title: "Eligibility checks", symbol: "checklist", isExpanded: $checksExpanded) {
                checksDetails
            }
        }
    }

    private func detailCard<Content: View>(
        title: String,
        symbol: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                content()
            }
            .padding(.top, 8)
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var propertyDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Name", value: display(store.session.contactName))
            LabeledContent("Email", value: display(store.session.email))
            LabeledContent("Phone", value: display(store.session.phone))
            LabeledContent("Address", value: display(store.session.propertyIdentifier))
            LabeledContent("Own or rent", value: ownershipText)
            if let fix = store.session.propertyLocation {
                PropertyLocationMap(fix: fix)
                LabeledContent("Captured", value: fix.timestamp.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Accuracy", value: String(format: "%.1f m", fix.horizontalAccuracyMeters))
                Text(store.session.propertyLocationDisclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Property location not captured")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var electricalDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            evidenceImage(store.meterImage, label: "Round electric meter")
            evidenceImage(store.breakerImage, label: "Main disconnect or breaker")
            LabeledContent("Meter number", value: display(store.session.electrical.meterNumber))
            if let source = store.session.electrical.meterNumberSource {
                LabeledContent("Meter number source", value: source == .ocr ? "OCR" : "Manual")
            }
            LabeledContent("Main breaker", value: breakerText)
            LabeledContent("Solar", value: yesNo(store.session.electrical.hasSolar))
            LabeledContent("Portable generator", value: yesNo(store.session.electrical.hasPortableGenerator))
            LabeledContent("Standby generator", value: yesNo(store.session.electrical.hasStandbyGenerator))
            LabeledContent("Existing whole-home battery", value: yesNo(store.session.electrical.hasExistingWholeHomeBattery))
            LabeledContent("Planned batteries", value: batteryCountText)
        }
    }

    private var placementDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let capture = store.session.placement.captureIdentity {
                LabeledContent("Capture", value: capture.capturedAt.formatted(date: .abbreviated, time: .standard))
                Text("Saved observation, revision \(capture.revision). Not a restored live AR session.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("No version-matched placement capture. Any previous image or measurements are draft evidence; rescan and save together.")
                    .font(.footnote).foregroundStyle(.orange)
            }
            evidenceImage(store.placementImage, label: "Placement screenshot")
            LabeledContent("Battery placed", value: store.session.placement.batteryPlaced ? "Yes" : "No")
            LabeledContent("Electric meter marked", value: store.session.placement.meterMarked ? "Yes" : "No")
            LabeledContent("Panel marked", value: store.session.placement.panelMarked ? "Yes" : "No")
            LabeledContent("Gas meter", value: gasMeterText)
            LabeledContent("Meter distance", value: feet(store.session.placement.distanceToMeterFeet))
            LabeledContent("Wall clearance", value: feet(store.session.placement.distanceToWallFeet))
            LabeledContent("Gas meter distance", value: feet(store.session.placement.distanceToGasMeterFeet))
            LabeledContent("Meter height", value: feet(store.session.placement.meterHeightFeet))
            LabeledContent("3 × 3 ft footprint clear", value: attestationText(measured: store.session.placement.footprintIsClear, attested: store.session.placement.footprintClearAttested))
            LabeledContent("30 × 36 in working space clear", value: observation(store.session.placement.frontWorkingSpaceIsClear))
            LabeledContent("Transfer-switch space", value: attestationText(measured: store.session.placement.transferSwitchClearanceObserved, attested: store.session.placement.transferSwitchSpaceAttested))
            LabeledContent("Meter and panel share wall", value: sameWallText(store.session.placement.meterAndPanelSameWall))
            LabeledContent("Measurement surfaces", value: measurementMethods)
            Text("GPS is the phone’s property fix, not the battery position. AR measurements are preliminary estimates.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var checksDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.session.ruleResults) { result in
                DisclosureGroup {
                    Text(result.explanation)
                        .font(.footnote)
                        .padding(.top, 4)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(result.title, systemImage: statusSymbol(result.status))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(ToneStyle.statusTitle(result.status))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(statusColor(result.status))
                        }
                        Text(result.requirement)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if result.id != store.session.ruleResults.last?.id {
                    Divider()
                }
            }
        }
    }

    private func editButton(_ title: String, route: HubRoute) -> some View {
        Button(title) {
            onEdit(route)
        }
        .buttonStyle(.bordered)
    }

    private var jsonPreviewSection: some View {
        GroupBox("survey.json") {
            if let preview = jsonPreview {
                ScrollView {
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 240)
            } else {
                Text("Preview will appear here after the survey is saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var jsonPreview: String? {
        guard let url = store.exportURLs.first(where: { $0.pathExtension == "json" }),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lastExportError = store.lastExportError {
                Label(lastExportError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                store.exportForSharing()
                showShare = store.lastExportError == nil && !store.exportURLs.isEmpty
            } label: {
                Label("Share survey", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Shares the current responses, photos, and missing-item list. The survey is also saved locally as survey.json.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var readinessTitle: String {
        if missingCount == 0 { return "Ready to share" }
        return "\(missingCount) item\(missingCount == 1 ? "" : "s") still needed"
    }

    private var readinessMessage: String {
        if store.session.ruleResults.contains(where: { $0.status == .conflict }) {
            return "Captured evidence includes a conflict. Review the flagged checks and missing information."
        }
        if missingCount == 0 {
            return "All requested information is captured. This remains a preliminary survey for engineer review."
        }
        return "Use the next actions below to finish the survey. You can still share the current draft."
    }

    private var readinessSymbol: String {
        if store.session.ruleResults.contains(where: { $0.status == .conflict }) {
            return "exclamationmark.triangle.fill"
        }
        return missingCount == 0 ? "checkmark.circle.fill" : "questionmark.circle.fill"
    }

    private var readinessColor: Color {
        if store.session.ruleResults.contains(where: { $0.status == .conflict }) { return .red }
        return missingCount == 0 ? .green : ToneStyle.color(.incomplete)
    }

    private var missingCount: Int { store.session.missingInformation.count }

    private var nextActions: [ReviewAction] {
        [
            ReviewAction(route: .home, title: "Home and personal info", symbol: "house.fill", count: homeMissingCount),
            ReviewAction(route: .meter, title: "Electrical meter", symbol: "gauge.with.dots.needle.33percent", count: meterMissingCount),
            ReviewAction(route: .breaker, title: "Breaker box", symbol: "bolt.fill", count: breakerMissingCount),
            ReviewAction(route: .placement, title: "Site measurements", symbol: "arkit", count: placementMissingCount)
        ].filter { $0.count > 0 }
    }

    private var homeMissingCount: Int {
        let session = store.session
        return [
            session.contactName.isBlank,
            session.email.isBlank,
            session.phone.isBlank,
            session.propertyIdentifier.isBlank,
            session.homeownership == nil,
            session.electrical.hasSolar == nil,
            session.electrical.hasPortableGenerator == nil,
            session.electrical.hasStandbyGenerator == nil,
            session.electrical.hasExistingWholeHomeBattery == nil,
            session.electrical.plannedBatteryCount == nil,
            session.propertyLocation == nil
        ].filter { $0 }.count
    }

    private var meterMissingCount: Int {
        [
            store.session.electrical.meterPhotoFilename == nil,
            (store.session.electrical.meterNumber ?? "").isBlank
        ].filter { $0 }.count
    }

    private var breakerMissingCount: Int {
        [
            store.session.electrical.breakerPhotoFilename == nil,
            store.session.electrical.mainBreakerAmperage == nil
        ].filter { $0 }.count
    }

    private var placementMissingCount: Int {
        // Guided photo/program issues have their own actionable cards above.
        let baselineCount = store.session.missingInformation.filter {
            !$0.hasPrefix("Guided:") && !$0.hasPrefix("Deferred:")
        }.count
        return max(0, baselineCount - homeMissingCount - meterMissingCount - breakerMissingCount)
    }

    private var breakerText: String {
        store.session.electrical.mainBreakerAmperage.map { "\($0) A" } ?? "Not confirmed"
    }

    private var ownershipText: String {
        switch store.session.homeownership {
        case nil: "Not answered"
        case .own: "Own"
        case .rent: "Rent"
        }
    }

    private var batteryCountText: String {
        store.session.electrical.plannedBatteryCount.map(String.init) ?? "Not captured"
    }

    private var gasMeterText: String {
        if store.session.placement.gasMeterMarked { return "Marked" }
        if store.gasMeterNotVisible { return "Not visible" }
        return "Not answered"
    }

    private var measurementMethods: String {
        let methods = Set(store.session.placement.confirmedMeasurements.map(\.captureMethod.title)).sorted()
        return methods.isEmpty ? "No confirmed measurements" : methods.joined(separator: ", ")
    }

    private func yesNo(_ value: Bool?) -> String {
        switch value {
        case nil: "Not answered"
        case false: "No"
        case true: "Yes"
        }
    }

    private func display(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Not entered" : trimmed
    }

    private func feet(_ value: Double?) -> String {
        guard let value else { return "Not measured" }
        return String(format: "%.1f ft", value)
    }

    private func attestationText(measured: Bool?, attested: Bool?) -> String {
        if measured != nil, store.session.placement.observationIdentity == nil {
            return "Legacy observation; rescan needed"
        }
        if let measured { return measured ? "Measured clear" : "Measured blocked" }
        if attested == true { return "Attested clear (not measured)" }
        return "Not measured or attested"
    }

    private func sameWallText(_ value: Bool?) -> String {
        switch value {
        case nil: "Not measured"
        case true?: "Yes"
        case false?: "No"
        }
    }

    private func observation(_ value: Bool?) -> String {
        switch value {
        case true: "Yes"
        case false: "No"
        case nil: "Not confirmed"
        }
    }

    private func statusColor(_ status: CheckStatus) -> Color {
        switch status {
        case .pass: .green
        case .conflict: .red
        case .unknown: ToneStyle.color(.incomplete)
        }
    }

    private func statusSymbol(_ status: CheckStatus) -> String {
        switch status {
        case .pass: "checkmark.circle.fill"
        case .conflict: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle.fill"
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
            Label("\(label) not saved", systemImage: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ReviewAction: Identifiable {
    var route: HubRoute
    var title: String
    var symbol: String
    var count: Int

    var id: HubRoute { route }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    var urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
