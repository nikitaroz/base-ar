import SwiftUI

struct ReviewView: View {
    var store: SurveyStore
    var onEdit: (HubRoute) -> Void
    var onStartOver: () -> Void

    @State private var showShare = false
    @State private var confirmStartOver = false
    @State private var confirmScanRestart = false
    @State private var propertyExpanded = false
    @State private var electricalExpanded = false
    @State private var placementExpanded = false
    @State private var checksExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                disclaimer
                readinessCard
                whatsMissingCard
                details
                TypeSafeJevAdvisoryView(session: store.session)
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
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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
        .alert("Start the scan over?", isPresented: $confirmScanRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Start over", role: .destructive) {
                store.restartLiveSurvey()
                onEdit(.placement)
            }
        } message: {
            Text("This clears the meter and panel marks, the battery spot, the scan photos, and numbers only the scan read. Your Home Info and typed numbers stay.")
        }
        .task {
            await store.exportForSharing()
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

    /// Missing items by step, then the fixes that used to live in the camera's menu.
    private var whatsMissingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What’s missing")
                .font(.headline)
                .padding(.bottom, 8)
            if nextActions.isEmpty {
                Label("Nothing is missing.", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
            ForEach(nextActions) { action in
                reviewRow(
                    title: action.title,
                    detail: "\(action.count) missing",
                    symbol: action.symbol
                ) {
                    onEdit(action.route)
                }
                if action.id != nextActions.last?.id {
                    Divider()
                }
            }
            Text("Fix something")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 16)
                .padding(.bottom, 4)
            if store.session.electrical.meterNumberSource == .ocr {
                reviewRow(
                    title: "Check the meter number",
                    detail: "Read by scan — check it matches the meter",
                    symbol: "text.viewfinder"
                ) {
                    onEdit(.electrical)
                }
                Divider()
            }
            if store.session.electrical.mainBreakerAmperageSource == .ocr {
                reviewRow(
                    title: "Check the main breaker",
                    detail: "Read by scan — check it matches the main breaker",
                    symbol: "text.viewfinder"
                ) {
                    onEdit(.electrical)
                }
                Divider()
            }
            if meterLocked {
                reviewRow(
                    title: "Redo the meter",
                    detail: "The Live Survey looks for it again. The battery spot goes too.",
                    symbol: "arrow.counterclockwise"
                ) {
                    store.redoLiveSurveyItem(.electricMeter)
                    onEdit(.placement)
                }
                Divider()
            }
            if panelLocked {
                reviewRow(
                    title: "Redo the panel",
                    detail: "The Live Survey looks for it again.",
                    symbol: "arrow.counterclockwise"
                ) {
                    store.redoLiveSurveyItem(.breakerPanel)
                    onEdit(.placement)
                }
                Divider()
            }
            reviewRow(
                title: "Type the electrical numbers",
                detail: "Meter number, main breaker, and panel rating",
                symbol: "keyboard"
            ) {
                onEdit(.electrical)
            }
            if scanHasContent {
                Divider()
                reviewRow(
                    title: "Start the scan over",
                    detail: "Clears the marks and the battery spot",
                    symbol: "arrow.uturn.backward"
                ) {
                    confirmScanRestart = true
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func reviewRow(
        title: String,
        detail: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
    }

    /// "Read by scan — check it" for a number the Live Survey read: open Electrical to fix it, or say it matches.
    /// Until then it is a suggestion, and a check that uses it stays unknown.
    private func scanReadCheck(_ what: String, confirm: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button {
                onEdit(.electrical)
            } label: {
                Label {
                    Text(SurveyStore.scanReadNote)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "text.viewfinder")
                        .foregroundStyle(ToneStyle.color(.incomplete))
                }
                .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Electrical to check or correct the \(what).")
            Spacer(minLength: 0)
            Button("Looks right", systemImage: "checkmark", action: confirm)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Says the \(what) matches what you see. It then counts as your answer, not a measurement.")
        }
    }

    /// Saved or only on the live scan: Review can show while the scan holds marks it has not saved.
    private var meterLocked: Bool {
        store.session.placement.meterMarked || store.liveMeterMarked
    }

    private var panelLocked: Bool {
        store.session.placement.panelMarked || store.livePanelMarked
    }

    private var scanHasContent: Bool {
        let placement = store.session.placement
        return meterLocked || panelLocked || placement.batteryPlaced || placement.gasMeterMarked
            || store.placementController?.scene.hasPlacedContent == true
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Survey details")
                .font(.headline)

            detailCard(title: "Property", symbol: "house.fill", isExpanded: $propertyExpanded) {
                propertyDetails
                editButton("Edit Home Info", route: .home)
            }

            detailCard(title: "Electrical evidence", symbol: "bolt.fill", isExpanded: $electricalExpanded) {
                electricalDetails
                editButton("Edit electrical", route: .electrical)
            }

            detailCard(title: "Site measurements", symbol: "arkit", isExpanded: $placementExpanded) {
                placementDetails
                editButton("Open the Live Survey", route: .placement)
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
        .tint(.primary)
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
            evidenceImage(
                store.meterImage,
                label: store.meterPhotoIsScanCrop ? "Round electric meter (photo from the Live Survey)" : "Round electric meter"
            )
            LabeledContent("Meter number", value: display(store.session.electrical.meterNumber))
            switch store.session.electrical.meterNumberSource {
            case .ocr?:
                // A scan's read is a suggestion until the homeowner checks it against the meter.
                scanReadCheck("meter number") { store.confirmScannedMeterNumber() }
            case .manual?:
                LabeledContent("Meter number source", value: "Typed")
            case nil:
                EmptyView()
            }
            if store.panelImage != nil || store.session.placement.panelMarked || store.livePanelMarked {
                evidenceImage(store.panelImage, label: "Breaker panel (photo from the Live Survey)")
            }
            LabeledContent("Main breaker", value: breakerText)
            if store.session.electrical.mainBreakerAmperageSource == .ocr {
                // Never the panel bus rating: only the number beside "MAIN" is read, and the user confirms it.
                scanReadCheck("main breaker") { store.confirmScannedMainBreaker() }
            }
            if store.session.electrical.needsPanelBusRating || store.session.electrical.panelBusRatingAmps != nil {
                LabeledContent("Panel bus rating", value: store.session.electrical.panelBusRatingAmps.map { "\($0) A" } ?? "Not entered")
            }
            LabeledContent("Solar", value: yesNo(store.session.electrical.hasSolar))
            LabeledContent("Portable generator", value: yesNo(store.session.electrical.hasPortableGenerator))
            LabeledContent("Standby generator", value: yesNo(store.session.electrical.hasStandbyGenerator))
            LabeledContent("Existing whole-home battery", value: yesNo(store.session.electrical.hasExistingWholeHomeBattery))
            LabeledContent("Planned batteries", value: batteryCountText)
            LabeledContent("Gas meter outside", value: gasAnswerText)
            BatteryCountDecisionSummary(decision: BatteryCountDecision.make(
                plannedCount: store.session.electrical.plannedBatteryCount,
                hasSolar: store.session.electrical.hasSolar,
                panelBusRatingAmps: store.session.electrical.panelBusRatingAmps,
                propertyIdentifier: store.session.propertyIdentifier
            ))
        }
    }

    private var placementDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Battery placed", value: store.session.placement.batteryPlaced ? "Yes" : "No")
            LabeledContent("Electric meter marked", value: store.session.placement.meterMarked ? "Yes" : "No")
            LabeledContent("Panel marked", value: store.session.placement.panelMarked ? "Yes" : "No")
            LabeledContent("Gas meter", value: gasMeterText)
            LabeledContent("Meter distance", value: feet(store.session.placement.distanceToMeterFeet))
            LabeledContent("Wall clearance", value: feet(store.session.placement.distanceToWallFeet))
            LabeledContent("Gas meter distance", value: feet(store.session.placement.distanceToGasMeterFeet))
            LabeledContent("Meter height", value: feet(store.session.placement.meterHeightFeet))
            LabeledContent("3 × 3 ft footprint clear", value: attestationText(measured: store.session.placement.footprintIsClear, attested: store.session.placement.footprintClearAttested))
            LabeledContent("Not in front of a window", value: observation(store.session.placement.clearOfWindows))
            LabeledContent("Clear of meter and panel access", value: observation(store.session.placement.keepsEquipmentAccess))
            LabeledContent("30 × 36 in working space clear", value: observation(store.session.placement.frontWorkingSpaceIsClear))
            LabeledContent("Transfer-switch space", value: attestationText(measured: store.session.placement.transferSwitchClearanceObserved, attested: store.session.placement.transferSwitchSpaceAttested))
            LabeledContent("Meter and panel share wall", value: sameWallText(store.session.placement.meterAndPanelShareWall))
            LabeledContent("Measurement surfaces", value: measurementMethods)
            Text("GPS is the phone’s property fix, not the battery position. AR measurements are preliminary estimates.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if store.placementController?.hasExportableMesh == true {
                Text("Share includes scene.ply: the LiDAR mesh in meters, in the AR world. Open it in MeshLab, CloudCompare, or Blender. Surfaces carry the camera's colors (light gray where the camera never saw them), and each face is labeled wall, floor, window, and so on. The measurements are drawn in: green passes, red conflicts, amber unknown.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let frames = store.placementController?.keyframes.count, frames > 0 {
                Text("Share includes a capture folder: \(frames) upright scan photos with LiDAR depth, in the same coordinates as scene.ply. capture/frames.json lists each camera pose and its intrinsics.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lastExportError = store.lastExportError {
                Label(lastExportError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                Task {
                    await store.exportForSharing()
                    showShare = store.lastExportError == nil && !store.exportURLs.isEmpty
                }
            } label: {
                if store.isExporting {
                    Label("Preparing survey…", systemImage: "hourglass")
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Share survey", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isExporting)
            .controlSize(.large)
            Text(store.placementController?.hasExportableMesh == true
                ? "Shares one zipped folder with survey.json, the photos, scene.ply, and the scan capture. The survey is also saved locally."
                : "Shares one zipped folder with survey.json and the photos. The survey is also saved locally. A LiDAR mesh (scene.ply) and scan capture are added after the placement scan.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    /// The placement tone drives the card, so it can't read green while a check is amber or red.
    /// Missing answers hold a passing tone at amber too.
    private var readinessTone: PlacementTone {
        let tone = store.session.placementTone
        if missingCount > 0, tone == .clear || tone == .attested { return .incomplete }
        return tone
    }

    private var readinessTitle: String {
        switch readinessTone {
        case .clear: "Ready to share"
        case .attested: "Ready to share, with attestations"
        case .incomplete:
            missingCount == 0
                ? ToneStyle.title(.incomplete)
                : "\(missingCount) item\(missingCount == 1 ? "" : "s") still needed"
        case .conflict: ToneStyle.title(.conflict)
        }
    }

    private var readinessMessage: String {
        switch readinessTone {
        case .clear:
            "All requested information is captured and every required check passed on measured evidence. This remains a preliminary survey for engineer review, not approval."
        case .attested:
            "All requested information is captured. Every required check passed, but at least one pass relies on your statement, not a measurement. This remains a preliminary survey for engineer review."
        case .incomplete:
            missingCount == 0
                ? "Some required checks are still unknown. Open Eligibility checks to see which. You can still share the current draft."
                : "Use What’s missing below to finish the survey. You can still share the current draft."
        case .conflict:
            "Captured evidence includes a conflict. Review the flagged checks and missing information."
        }
    }

    private var readinessSymbol: String {
        switch readinessTone {
        case .clear: "checkmark.circle.fill"
        case .attested: "checkmark.circle"
        case .incomplete: "questionmark.circle.fill"
        case .conflict: "exclamationmark.triangle.fill"
        }
    }

    private var readinessColor: Color { ToneStyle.color(readinessTone) }

    private var missingCount: Int { store.session.missingInformation.count }

    private var nextActions: [ReviewAction] {
        [
            ReviewAction(route: .home, title: "Home Info", symbol: "house.fill", count: homeMissingCount),
            ReviewAction(route: .electrical, title: "Electrical numbers", symbol: "bolt.fill", count: electricalMissingCount),
            ReviewAction(route: .placement, title: "Live Survey", symbol: "arkit", count: placementMissingCount)
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
            !session.gasMeterQuestionAnswered,
            session.propertyLocation == nil
        ].filter { $0 }.count
    }

    private var electricalMissingCount: Int {
        [
            store.session.electrical.meterPhotoFilename == nil,
            (store.session.electrical.meterNumber ?? "").isBlank,
            store.session.electrical.meterNumberSource == .ocr && !(store.session.electrical.meterNumber ?? "").isBlank,
            store.session.electrical.mainBreakerAmperage == nil,
            store.session.electrical.mainBreakerAmperage != nil && store.session.electrical.mainBreakerAmperageSource == .ocr,
            store.session.electrical.needsPanelBusRating && store.session.electrical.panelBusRatingAmps == nil
        ].filter { $0 }.count
    }

    private var placementMissingCount: Int {
        max(0, missingCount - homeMissingCount - electricalMissingCount)
    }

    private var breakerText: String {
        guard let amps = store.session.electrical.mainBreakerAmperage else { return "Not confirmed" }
        return store.session.electrical.mainBreakerAmperageSource == .ocr ? "\(amps) A (read by scan)" : "\(amps) A"
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

    /// A marked gas meter is measured; "none" is the homeowner's answer and says so.
    private var gasMeterText: String {
        if store.session.placement.gasMeterMarked { return "Marked on the scan" }
        if store.gasMeterNotVisible || store.session.electrical.gasMeterAnswer == .no {
            return "None (your answer, not measured)"
        }
        return store.session.electrical.gasMeterAnswer == nil ? "Not answered" : "Not found on the scan yet"
    }

    private var gasAnswerText: String {
        switch store.session.electrical.gasMeterAnswer {
        case .yes?: "Yes"
        case .no?: "No"
        case .notSure?: "Not sure"
        case nil: "Not answered"
        }
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
        case .pass: ToneStyle.color(.clear)
        case .conflict: ToneStyle.color(.conflict)
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

// MARK: - Fix-its

/// Review's "Redo the meter", "Redo the panel", and "Start the scan over": the Live Survey's own fixes, run from
/// outside the camera. Each saves the scene as it now is, so Review stops listing a mark the scan dropped.
extension SurveyStore {
    /// Drops that lock and keeps the same spot from relocking right away, so the Live Survey asks for it again.
    /// Redoing the meter drops the battery and look-around too, and a meter photo that was only the scan's crop.
    func redoLiveSurveyItem(_ kind: EquipmentKind) {
        guard let controller = placementController else { return }
        controller.rejectLock(kind)
        if kind == .electricMeter {
            dropScanMeterPhoto()
        }
        commitPlacement(controller.scene)
    }

    /// Clears the scan's marks, battery, look-around, and skipped steps, and the placement evidence and scan photos
    /// that came from them. The Home Info gas answer stays, so "No" still skips the gas step.
    func restartLiveSurvey() {
        placementController?.restartScan()
        resetPlacementEvidence()
        dropScanMeterPhoto()
        if session.electrical.gasMeterAnswer != .no {
            setGasMeterNotVisible(false)
        }
    }
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
