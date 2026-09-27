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
                #if DEBUG
                TestToolsCard()
                #endif
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
            Text("This clears the meter and panel marks, the site check, the scan photos, and numbers only the scan read. Your Home Info and typed numbers stay.")
        }
        .task {
            await exportIfChanged()
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
            Text(ToneStyle.title(readinessTone))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToneStyle.color(readinessTone))
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
            if store.isExporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving the survey files…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
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
                    detail: "The Live Survey looks for it again. The site check runs again too.",
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
                    detail: "Clears the marks and the site check",
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
            if store.session.electrical.mainBreakerAmperage == nil,
               store.panelImage != nil || store.session.electrical.panelPhotoFilename != nil {
                // The panel was captured but no number beside MAIN was read (a stab or bus rating never counts).
                Button {
                    onEdit(.electrical)
                } label: {
                    Label {
                        Text("The scan saw the panel but no main-breaker number. Type it from the big breaker at the top.")
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    } icon: {
                        Image(systemName: "keyboard")
                            .foregroundStyle(ToneStyle.color(.incomplete))
                    }
                    .font(.footnote)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Electrical to type the main breaker size.")
            }
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
            siteCheckCard
            LabeledContent("Electric meter marked", value: store.session.placement.meterMarked ? "Yes" : "No")
            LabeledContent("Panel marked", value: store.session.placement.panelMarked ? "Yes" : "No")
            LabeledContent("Gas meter", value: gasMeterText)
            if gasShownNotRecognized {
                gasShownCheck
            }
            LabeledContent("Spot to meter", value: feet(store.session.placement.distanceToMeterFeet))
            LabeledContent("Spot to wall", value: feet(store.session.placement.distanceToWallFeet))
            LabeledContent("Spot to gas meter", value: feet(store.session.placement.distanceToGasMeterFeet))
            LabeledContent("Meter height", value: feet(store.session.placement.meterHeightFeet))
            LabeledContent("3 × 3 ft spot clear", value: attestationText(measured: store.session.placement.footprintIsClear, attested: store.session.placement.footprintClearAttested))
            LabeledContent("Spot not in front of a window", value: observation(store.session.placement.clearOfWindows))
            LabeledContent("Spot clear of meter and panel access", value: observation(store.session.placement.keepsEquipmentAccess))
            LabeledContent("30 × 36 in working space clear", value: observation(store.session.placement.frontWorkingSpaceIsClear))
            LabeledContent("Transfer-switch space", value: attestationText(measured: store.session.placement.transferSwitchClearanceObserved, attested: store.session.placement.transferSwitchSpaceAttested))
            LabeledContent("Meter and panel share wall", value: sameWallText(store.session.placement.meterAndPanelShareWall))
            LabeledContent("Measurement surfaces", value: measurementMethods)
            Text("GPS is the phone’s property fix, not the spot. Scan measurements are preliminary estimates.")
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

    /// The site check the Live Survey ran by itself after the look-around, in plain words, with the spot's own checks.
    private var siteCheckCard: some View {
        let check = siteCheck
        let tone = siteCheckTone(check)
        return VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Site check")
            } icon: {
                Image(systemName: ToneStyle.symbol(tone))
                    .foregroundStyle(ToneStyle.color(tone))
            }
            .font(.subheadline.weight(.semibold))
            Text(siteCheckText(check))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if case .found = check {
                ForEach(padRules) { rule in
                    padRuleRow(rule)
                }
            }
            #if DEBUG
            if let rejections = store.session.placement.batterySpot?.rejections, !rejections.isEmpty {
                DisclosureGroup("Spots the scan ruled out (debug)") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(rejections.enumerated()), id: \.offset) { _, reason in
                            Text(reason)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private var siteCheck: SiteCheck { SiteCheck.of(store.session) }

    /// Found on measured ground reads green; found on an answer reads teal; a blocked site is red; not yet known is amber.
    private func siteCheckTone(_ check: SiteCheck) -> PlacementTone {
        switch check {
        case .found(let measured): measured ? .clear : .attested
        case .noClearSpot: .conflict
        case .notRun, .noMeter, .notEnoughScanned: .incomplete
        }
    }

    /// "A spot that meets Base's spacing rules was found beside the meter.", or why not. Never battery wording.
    private func siteCheckText(_ check: SiteCheck) -> String {
        let placement = store.session.placement
        switch check {
        case .found:
            var spotDetail = ""
            if let along = placement.distanceToMeterFeet ?? placement.batterySpot?.alongWallFeet.map(abs) {
                spotDetail = String(format: " It is about %.1f ft along the wall from the meter", along)
                if let towardPanel = placement.batterySpot?.towardPanel {
                    spotDetail += towardPanel ? ", on the panel side" : ", on the other side"
                }
                spotDetail += "."
            }
            if let wall = placement.distanceToWallFeet {
                spotDetail += " \(max(0, Int((wall * 12).rounded()))) in from the wall."
            }
            return "A spot that meets Base’s spacing rules was found beside the meter." + spotDetail
        case .notEnoughScanned:
            return "Not enough of the ground was scanned beside the meter. Open the Live Survey and look around the meter again."
        case .noClearSpot:
            let count = placement.batterySpot?.candidatesTried ?? 0
            let checked = count > 0 ? " The scan checked \(count) spot\(count == 1 ? "" : "s") beside the meter." : ""
            return "No clear 3 × 3 ft spot was found." + checked + " An engineer will look at the photos."
        case .noMeter:
            return "No meter was found on the scan, so the site check did not run."
        case .notRun:
            return "The site check runs by itself when the Live Survey finishes the look-around."
        }
    }

    /// The checks that judge the pad itself, in the order an installer reads them.
    private static let padRuleIDs = [
        "planning-footprint",
        "wall-distance",
        "not-in-front-of-window",
        "meter-panel-access",
        "gas-meter-clearance",
        "meter-distance"
    ]

    private var padRules: [RuleResult] {
        Self.padRuleIDs.compactMap { id in store.session.ruleResults.first { $0.id == id } }
    }

    /// One pad check: symbol, title, and status in words, so the result never rests on color alone. A pass that
    /// rests on an answer or a spot the user showed reads as attested (teal), not measured.
    private func padRuleRow(_ rule: RuleResult) -> some View {
        let tone = padRuleTone(rule)
        return HStack(spacing: 8) {
            Image(systemName: ToneStyle.symbol(tone))
                .foregroundStyle(ToneStyle.color(tone))
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(rule.title)
                .font(.footnote)
            Spacer(minLength: 8)
            Text(padRuleStatus(tone))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToneStyle.color(tone))
        }
        .accessibilityElement(children: .combine)
    }

    private func padRuleTone(_ rule: RuleResult) -> PlacementTone {
        switch rule.status {
        case .pass: rule.usedMeasuredEvidence ? .clear : .attested
        case .conflict: .conflict
        case .unknown: .incomplete
        }
    }

    private func padRuleStatus(_ tone: PlacementTone) -> String {
        switch tone {
        case .clear: "Pass"
        case .attested: "Pass, your answer"
        case .incomplete: "Unknown"
        case .conflict: "Conflict"
        }
    }

    /// A spot the user showed as the gas meter. The scan did not recognize it, so its clearance is attested.
    private var gasShownNotRecognized: Bool {
        let placement = store.session.placement
        return placement.gasMeterMarked && placement.gasMeterMarkSource != .recognized
    }

    /// The photo of the spot shown as the gas meter, and a way to say it was not one.
    private var gasShownCheck: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = store.gasImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Spot shown as the gas meter (photo from the Live Survey)")
            } else {
                Label("Gas meter photo not saved", systemImage: "photo.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Not the gas meter", systemImage: "xmark.circle") {
                store.rejectGasMark()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Drops this spot. The gas check stays unknown until the Live Survey is shown a gas meter.")
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
                            Label {
                                Text(result.title)
                            } icon: {
                                Image(systemName: ToneStyle.symbol(checkTone(result)))
                                    .foregroundStyle(ToneStyle.color(checkTone(result)))
                            }
                            .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(checkStatusTitle(result))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ToneStyle.color(checkTone(result)))
                                .multilineTextAlignment(.trailing)
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

    // MARK: Export

    /// True when the survey changed since Review's last export, or that export failed or never ran.
    private var needsExport: Bool {
        ReviewExportLedger.lastToken != ReviewExportToken(store) || store.exportURLs.isEmpty
            || store.lastExportError != nil
    }

    /// Review's automatic export: once per survey revision, not on every appearance. The export reads the whole
    /// scan's mesh on the main thread, so it waits for the step switch to finish drawing, and is skipped when
    /// Review is left before then.
    private func exportIfChanged() async {
        guard needsExport else { return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled, needsExport else { return }
        await runExport()
    }

    /// The token is taken before the export, so a change made while it runs makes the next appearance export again.
    private func runExport() async {
        ReviewExportLedger.lastToken = ReviewExportToken(store)
        await store.exportForSharing()
        if store.lastExportError != nil {
            ReviewExportLedger.lastToken = nil
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
                    // The export Review already made is reused when nothing changed since; otherwise it runs again.
                    if needsExport {
                        await runExport()
                    }
                    showShare = store.lastExportError == nil && !store.exportURLs.isEmpty
                }
            } label: {
                if store.isExporting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Preparing survey…")
                    }
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
        if siteCheck == .noClearSpot { return .conflict }
        if missingCount > 0, tone == .clear || tone == .attested { return .incomplete }
        return tone
    }

    private var readinessTitle: String {
        switch readinessTone {
        case .clear: "Ready to share"
        case .attested: "Ready to share"
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
            "All requested information is captured and every required check passed on measured evidence. This is a prototype survey for engineer review, not approval."
        case .attested:
            "All requested information is captured and every required check passed. Some passes rest on your answers or numbers the scan read, not measurements (teal). This is a prototype survey for engineer review, not approval."
        case .incomplete:
            missingCount == 0
                ? "Some required checks are still unknown. Open Eligibility checks to see which. You can still share the current draft."
                : "Use What’s missing below to finish the survey. You can still share the current draft."
        case .conflict:
            siteCheck == .noClearSpot
                ? "No clear 3 × 3 ft spot was found beside the meter. Open Site measurements for details. You can still share the survey for engineer review."
                : "Captured evidence includes a conflict. Review the flagged checks and missing information."
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

    /// Fresh from the session, the same items the step bar counts, so a step never shows done while one is listed.
    private var missingItems: [MissingItem] { store.missingItems }

    private var missingCount: Int { missingItems.count }

    private var nextActions: [ReviewAction] {
        let missing = missingItems
        func count(_ step: MissingItem.Step) -> Int { missing.filter { $0.step == step }.count }
        return [
            ReviewAction(route: .home, title: "Home Info", symbol: "house.fill", count: count(.home)),
            ReviewAction(route: .electrical, title: "Electrical numbers", symbol: "bolt.fill", count: count(.electrical)),
            ReviewAction(route: .placement, title: "Live Survey", symbol: "arkit", count: count(.scan))
        ].filter { $0.count > 0 }
    }

    private var breakerText: String {
        let electrical = store.session.electrical
        guard let amps = electrical.mainBreakerAmperage else { return "Not confirmed" }
        guard electrical.mainBreakerAmperageSource == .ocr else { return "\(amps) A" }
        switch electrical.mainBreakerAmperageBasis {
        case .mainRow?: return "\(amps) A (read from the MAIN label)"
        case .mainNeighbor?: return "\(amps) A (read beside MAIN)"
        case .largestHandle?: return "\(amps) A (read from the largest breaker)"
        case nil: return "\(amps) A (read by scan)"
        }
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

    /// A spot shown on the scan is not a recognized gas meter, so it says to check the photo; "none" is the
    /// homeowner's answer and says so.
    private var gasMeterText: String {
        let placement = store.session.placement
        if placement.gasMeterMarked {
            return placement.gasMeterMarkSource == .recognized ? "Recognized on the scan" : "Shown on the scan: check the photo"
        }
        if store.gasMeterNotVisible || store.session.electrical.gasMeterAnswer == .no {
            return "None (your answer, not measured)"
        }
        switch placement.gasStepOutcome {
        case .rejectedInReview?: return "Not shown (you said the spot was not a gas meter)"
        case .timedOut?: return "Not shown on the scan"
        default: return store.session.electrical.gasMeterAnswer == nil ? "Not answered" : "Not shown on the scan yet"
        }
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

    /// Green only for a pass on measured evidence. A pass that rests on a typed number, an answer, or a number the
    /// scan read and the user confirmed is teal: ready, but attested.
    private func checkTone(_ result: RuleResult) -> PlacementTone {
        switch result.status {
        case .pass: result.usedMeasuredEvidence ? .clear : .attested
        case .conflict: .conflict
        case .unknown: .incomplete
        }
    }

    private func checkStatusTitle(_ result: RuleResult) -> String {
        guard result.status == .pass, !result.usedMeasuredEvidence else { return ToneStyle.statusTitle(result.status) }
        let scanRead = result.id == "austin-main-breaker" && store.session.electrical.mainBreakerAmperageBasis != nil
        return scanRead ? "Pass, read by scan" : "Pass, your answer"
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

#if DEBUG
/// Test builds only: the frame recorder saves camera frames and gate readings for tuning. Off by default.
private struct TestToolsCard: View {
    @AppStorage(FrameRecorder.enabledDefaultsKey) private var on = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Test tools", systemImage: "hammer.fill")
                .font(.headline)
            Toggle("Save test frames on this phone", isOn: $on)
            Text("Starts the next time the Live Survey opens. Files app › On My iPhone › Base Site Survey › FrameLog.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
#endif

/// What Review's export wrote: the survey (without the fields the export itself fills in or that are derived from
/// the rest), the live scan's marks, and how much scan it held. Equal tokens mean the files on disk are current.
private struct ReviewExportToken: Equatable {
    var session: SurveySession
    var scene: PlacementSceneSnapshot?
    var keyframeCount: Int
    var hasMesh: Bool

    @MainActor
    init(_ store: SurveyStore) {
        var session = store.session
        session.placement.pointCloudFilename = nil
        session.placement.captureManifestPath = nil
        session.placement.capturedFrameCount = nil
        session.ruleResults = []
        session.missingInformation = []
        session.placementTone = .incomplete
        self.session = session
        let controller = store.placementController
        scene = controller?.scene
        keyframeCount = controller?.keyframes.count ?? 0
        hasMesh = controller?.hasExportableMesh ?? false
    }
}

/// Outlives ReviewView: the step switch rebuilds Review each time it opens. A new survey has a new session id,
/// so its token never matches the last survey's.
@MainActor
private enum ReviewExportLedger {
    static var lastToken: ReviewExportToken?
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
