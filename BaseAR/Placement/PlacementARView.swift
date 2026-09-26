import ARKit
import RealityKit
import SwiftUI

enum PlacementTarget: String, CaseIterable, Identifiable {
    case battery
    case meter
    case panel
    case gasMeter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .meter: "Meter"
        case .panel: "Panel"
        case .gasMeter: "Gas"
        }
    }

}

/// One prompt at a time. The camera stays up; the bottom bar only shows the current action.
private enum WalkStep: Equatable {
    case battery
    case meter
    case measure(PlacementMeasurementKind)
    case gas
    case panel
    case workingSpace
    case footprint
    case transfer
    case sameWall
    case finish

    var title: String {
        switch self {
        case .battery: "Place battery"
        case .meter: "Mark the meter"
        case .panel: "Mark the panel"
        case .measure(let kind):
            switch kind {
            case .batteryToMeter: "Distance to meter"
            case .batteryToWall: "Distance to wall"
            case .batteryToGasMeter: "Distance to gas"
            case .meterHeight: "Meter height"
            }
        case .gas: "Gas meter"
        case .workingSpace: "Working space"
        case .footprint: "Clear pad"
        case .transfer: "Transfer switch"
        case .sameWall: "Same wall"
        case .finish: "Save"
        }
    }

    static func firstIncomplete(in scene: PlacementSceneSnapshot, gasNotVisible: Bool) -> WalkStep {
        if scene.batteryPosition == nil { return .battery }
        if scene.meterPosition == nil { return .meter }
        if scene.panelPosition == nil { return .panel }
        if !scene.confirmed(.batteryToMeter) { return .measure(.batteryToMeter) }
        if !scene.confirmed(.batteryToWall) { return .measure(.batteryToWall) }
        if scene.gasMeterPosition == nil && !gasNotVisible { return .gas }
        if scene.gasMeterPosition != nil && !scene.confirmed(.batteryToGasMeter) {
            return .measure(.batteryToGasMeter)
        }
        if !scene.confirmed(.meterHeight) { return .measure(.meterHeight) }
        if scene.workingSpacePosition == nil { return .workingSpace }
        return .finish
    }
}

private extension PlacementSceneSnapshot {
    func confirmed(_ kind: PlacementMeasurementKind) -> Bool {
        confirmedMeasurements.contains { $0.kind == kind }
    }
}

struct PlacementARView: View {
    var store: SurveyStore
    var onContinue: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var step: WalkStep
    /// Kind last used for a measure step, so leaving that step does not wipe its draft.
    @State private var heldKind: PlacementMeasurementKind
    @State private var remeasure = false
    @State private var yawRadians: Float
    @State private var scene: PlacementSceneSnapshot
    /// Updated many times a second while measuring. Kept off this view so those updates do not cancel button taps.
    @State private var liveReadout = LiveDistanceReadout()
    @State private var screenshotToken: UUID? = nil
    /// Set while a save waits for its screenshot. Cleared when it advances, so the view can save again after Back.
    @State private var pendingSave: UUID? = nil
    @State private var statusMessage: String? = nil
    @State private var isVisible = false
    @State private var hasStartedAR: Bool
    @State private var coachingIsActive = false

    init(store: SurveyStore, onContinue: @escaping () -> Void) {
        self.store = store
        self.onContinue = onContinue
        let existing = store.placementController
        let snapshot = existing?.scene ?? PlacementSceneSnapshot()
        let progressed = WalkStep.firstIncomplete(in: snapshot, gasNotVisible: store.gasMeterNotVisible)
        let initialStep = (existing?.hasChosenWalkStep == true) ? (existing?.walkStep ?? progressed) : progressed
        _scene = State(initialValue: snapshot)
        _step = State(initialValue: initialStep)
        _heldKind = State(initialValue: {
            if case .measure(let kind) = initialStep { return kind }
            return .batteryToMeter
        }())
        _yawRadians = State(initialValue: existing?.yawRadians ?? 0)
        _hasStartedAR = State(initialValue: existing != nil)
    }

    private var isSaving: Bool { pendingSave != nil }

    private var arSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    private var liveAssessment: SurveyAssessment {
        if scene.hasPlacedContent {
            return store.assessment(applying: scene)
        }
        return SurveyAssessment(
            results: store.session.ruleResults,
            placementTone: store.session.placementTone,
            missingInformation: store.session.missingInformation
        )
    }

    var body: some View {
        Group {
            if arSupported {
                if hasStartedAR {
                    arScreen
                } else {
                    preflightScreen
                }
            } else {
                unsupportedScreen
            }
        }
        .navigationTitle(hasStartedAR && arSupported ? step.title : "Placement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            guard arSupported, hasStartedAR else { return }
            isVisible = true
            let controller = store.requirePlacementController()
            controller.resume()
            scene = controller.scene
            yawRadians = controller.yawRadians
        }
        .onDisappear {
            isVisible = false
            pendingSave = nil
            commitLiveScene()
            store.placementController?.pauseIfIdle()
        }
        .onChange(of: scenePhase) { _, phase in
            guard isVisible, arSupported, hasStartedAR else { return }
            if phase == .active {
                store.placementController?.resume()
            } else if phase == .background {
                store.placementController?.pauseIfIdle()
            }
        }
        .onChange(of: step) { old, new in
            store.placementController?.walkStep = new
            store.placementController?.hasChosenWalkStep = true
            remeasure = false
            statusMessage = nil
            liveReadout.text = nil
            if case .measure(let kind) = new {
                heldKind = kind
            } else if case .measure(let kind) = old {
                heldKind = kind
            }
        }
    }

    private var arScreen: some View {
        let tone = liveAssessment.placementTone
        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if let controller = store.placementController {
                    PlacementARRepresentable(
                        controller: controller,
                        mode: placementMode,
                        measurementMode: isMeasuring,
                        measurementKind: boundKind,
                        editingWorkingSpace: step == .workingSpace,
                        inputEnabled: inputEnabled,
                        aimEnabled: aimEnabled,
                        tapEnabled: tapEnabled,
                        yawRadians: yawRadians,
                        tone: tone,
                        screenshotToken: screenshotToken,
                        onSceneChange: acceptScene,
                        onYawChange: { yawRadians = $0 },
                        onLiveFeet: acceptLiveFeet,
                        onScreenshot: handleScreenshot,
                        onFailure: { statusMessage = $0 },
                        onCoachingActiveChange: { coachingIsActive = $0 }
                    )
                }
                if !coachingIsActive {
                    progressHeader
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
            if !coachingIsActive {
                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
    }

    private var preflightScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "arkit")
                .font(.system(size: 48))
                .accessibilityHidden(true)
            Text("Preview the battery outside")
                .font(.title.bold())
            VStack(alignment: .leading, spacing: 14) {
                Label("Stand where the battery will go.", systemImage: "sun.max")
                Label("Aim the dot, then tap +.", systemImage: "plus.circle")
                Label("Each step asks for one thing.", systemImage: "list.number")
            }
            .foregroundStyle(.secondary)
            Spacer()
            Button {
                hasStartedAR = true
                isVisible = true
                let controller = store.requirePlacementController()
                controller.resume()
                scene = controller.scene
                yawRadians = controller.yawRadians
            } label: {
                Label("Start camera", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("The preview and measurements are preliminary and require engineer review.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var progressHeader: some View {
        VStack(spacing: 6) {
            Text("\(progressIndex + 1) of \(progressSteps.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(progressSteps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= progressIndex ? Color.primary : Color.primary.opacity(0.25))
                        .frame(width: index == progressIndex ? 16 : 7, height: 4)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Text(instruction)
                .font(.body)
                .multilineTextAlignment(.center)
            distanceReadout
            if step == .finish {
                Text(distanceLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            stepControls
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var stepControls: some View {
        switch step {
        case .footprint, .transfer, .sameWall:
            answerRow
        case .workingSpace where scene.workingSpacePosition != nil:
            answerRow
        case .finish:
            finishControls
        default:
            aimControls
        }
    }

    private var aimControls: some View {
        VStack(spacing: 8) {
            HStack {
                if step != .battery {
                    Button("Back", action: goBack)
                        .buttonStyle(.bordered)
                        .frame(minWidth: 72, minHeight: 44)
                } else {
                    Color.clear.frame(width: 72, height: 44)
                        .allowsHitTesting(false)
                }
                Spacer()
                VStack(spacing: 4) {
                    Button(action: primaryAction) {
                        Image(systemName: primaryIsAdvance ? "checkmark" : "plus")
                            .font(.title2.weight(.semibold))
                            .frame(width: 68, height: 68)
                            .background(Color.primary, in: Circle())
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .accessibilityLabel(primaryIsAdvance ? "Next" : "Place point")
                    Text(primaryIsAdvance ? "Next" : "Place")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if canUndoPoint {
                    Button("Undo") { store.placementController?.undoMeasurementPoint() }
                        .buttonStyle(.bordered)
                        .frame(minWidth: 72, minHeight: 44)
                } else {
                    Color.clear.frame(width: 72, height: 44)
                        .allowsHitTesting(false)
                }
            }
            if let secondaryTitle {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
    }

    private var answerRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                answerButton("Yes", true)
                answerButton("No", false)
                answerButton("Not sure", nil)
            }
            if step != .battery {
                Button("Back", action: goBack)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
    }

    private func answerButton(_ title: String, _ value: Bool?) -> some View {
        Button {
            answer(value)
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var finishControls: some View {
        VStack(spacing: 8) {
            attestationToggles
            Button {
                saveAndReview()
            } label: {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Save and review")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSaving || scene.batteryPosition == nil)
            Button("Skip for now") {
                commitLiveScene()
                onContinue()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button("Back", action: goBack)
                .buttonStyle(.bordered)
                .controlSize(.large)
            Text("Green only when every required check has measured evidence and passes. Teal means a pass relied on an attestation, not a measurement. This is not installation approval.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var attestationToggles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("I visually confirmed the 3 ft × 3 ft footprint is clear", isOn: footprintAttestBinding)
                .font(.footnote)
            Toggle("I visually confirmed transfer-switch space beside the meter", isOn: transferSwitchAttestBinding)
                .font(.footnote)
            Text("Attestations are your statements, not app measurements.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .disabled(scene.batteryPosition == nil && store.session.placement.batteryPosition == nil)
    }

    private var footprintAttestBinding: Binding<Bool> {
        Binding(
            get: { store.session.placement.footprintClearAttested == true },
            set: { store.setFootprintClearAttested($0) }
        )
    }

    private var transferSwitchAttestBinding: Binding<Bool> {
        Binding(
            get: { store.session.placement.transferSwitchSpaceAttested == true },
            set: { store.setTransferSwitchSpaceAttested($0) }
        )
    }

    private var unsupportedScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            ContentUnavailableView(
                "Placement preview isn’t available on this device",
                systemImage: "arkit",
                description: Text("Use a physical iPhone to place the battery and capture measurements. You can complete the other survey sections here.")
            )
            Button("Return to survey") {
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            Button("Review missing items") {
                onContinue()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var distanceLine: String {
        let measured = store.measurements(for: scene)
        return [
            feetLabel("Meter", measured.distanceToMeterFeet),
            feetLabel("Wall", measured.distanceToWallFeet),
            feetLabel("Gas", measured.distanceToGasMeterFeet)
        ].joined(separator: "  ·  ")
    }

    private func feetLabel(_ name: String, _ feet: Double?) -> String {
        guard let feet else { return "\(name): —" }
        return String(format: "%@: %.1f ft", name, feet)
    }

    private var progressSteps: [WalkStep] {
        var steps: [WalkStep] = [
            .battery, .meter, .panel,
            .measure(.batteryToMeter),
            .measure(.batteryToWall),
            .gas
        ]
        if scene.gasMeterPosition != nil || step == .measure(.batteryToGasMeter) {
            steps.append(.measure(.batteryToGasMeter))
        }
        steps.append(contentsOf: [
            .measure(.meterHeight),
            .workingSpace,
            .footprint, .transfer, .sameWall,
            .finish
        ])
        return steps
    }

    private var progressIndex: Int {
        progressSteps.firstIndex(of: step) ?? 0
    }

    private var placementMode: PlacementTarget {
        switch step {
        case .meter: .meter
        case .panel: .panel
        case .gas: .gasMeter
        default: .battery
        }
    }

    private var isMeasuring: Bool {
        if case .measure = step { return true }
        return step == .workingSpace
    }

    private var boundKind: PlacementMeasurementKind {
        if case .measure(let kind) = step { return kind }
        return heldKind
    }

    private var inputEnabled: Bool {
        switch step {
        case .footprint, .transfer, .sameWall, .finish: false
        default: true
        }
    }

    /// Taps place or move a mark. Locked measurements ignore taps until Undo.
    private var tapEnabled: Bool {
        switch step {
        case .battery, .meter, .panel, .gas, .workingSpace: true
        case .measure: !showingSavedMeasure && scene.draftMeasurementEnd == nil
        default: false
        }
    }

    /// Center dot stays up while the next action is “aim and tap +”.
    private var aimEnabled: Bool {
        switch step {
        case .battery: scene.batteryPosition == nil
        case .meter: scene.meterPosition == nil && scene.meterWallPosition == nil
        case .panel: scene.panelPosition == nil && scene.panelWallPosition == nil
        case .gas: scene.gasMeterPosition == nil
        case .workingSpace: scene.workingSpacePosition == nil
        case .measure:
            !showingSavedMeasure && scene.draftMeasurementEnd == nil
        default:
            false
        }
    }

    private var showingSavedMeasure: Bool {
        guard case .measure(let kind) = step else { return false }
        if remeasure || scene.draftMeasurementStart != nil { return false }
        return scene.confirmedMeasurements.contains { $0.kind == kind }
    }

    private var primaryIsAdvance: Bool {
        switch step {
        case .battery: scene.batteryPosition != nil
        case .meter: scene.meterPosition != nil || scene.meterWallPosition != nil
        case .panel: scene.panelPosition != nil || scene.panelWallPosition != nil
        case .gas: scene.gasMeterPosition != nil
        case .measure:
            showingSavedMeasure || scene.draftMeasurementEnd != nil
        case .workingSpace:
            false
        default:
            false
        }
    }

    private var canUndoPoint: Bool {
        if case .measure = step { return scene.draftMeasurementStart != nil }
        return false
    }

    private var secondaryTitle: String? {
        switch step {
        case .gas: "No gas meter"
        case .workingSpace where scene.workingSpacePosition == nil: "Skip"
        case .measure where showingSavedMeasure: "Measure again"
        case .measure where scene.draftMeasurementEnd == nil: "Skip"
        default: nil
        }
    }

    private var instruction: String {
        switch step {
        case .battery:
            scene.batteryPosition == nil
                ? "Point the dot at the ground, then tap +."
                : "Drag to move the battery. Twist two fingers to turn it."
        case .meter:
            scene.meterPosition == nil && scene.meterWallPosition == nil
                ? "Point at the ground under the meter, then at the meter on the wall."
                : "Meter marked. Tap the wall if you still need its height, then tap Next."
        case .panel:
            scene.panelPosition == nil && scene.panelWallPosition == nil
                ? "Point at the ground under the breaker panel, then at the panel on the wall."
                : "Panel marked. Tap Next, or tap again to move it."
        case .measure(let kind):
            measureInstruction(kind)
        case .gas:
            scene.gasMeterPosition == nil
                ? "Point the dot at the gas meter, or say there isn’t one."
                : "Gas meter marked."
        case .workingSpace:
            scene.workingSpacePosition == nil
                ? "Point the dot at the ground in front of the meter."
                : "Is this 30 × 36 in space clear? Drag or twist to adjust it."
        case .footprint:
            "Is the 3 × 3 ft pad clear of obstacles?"
        case .transfer:
            "Is there room for a transfer switch beside the meter?"
        case .sameWall:
            "Are the meter and breaker panel on the same wall?"
        case .finish:
            "Save this placement for review."
        }
    }

    private func measureInstruction(_ kind: PlacementMeasurementKind) -> String {
        if showingSavedMeasure {
            return "Already measured. Tap Next, or measure again."
        }
        if scene.draftMeasurementStart == nil {
            switch kind {
            case .batteryToMeter: return "Point the dot at the electric meter, then tap +. Distance is from the battery’s nearest edge."
            case .batteryToWall: return "Point the dot at the nearest wall, then tap +. Distance is from the battery’s nearest edge."
            case .batteryToGasMeter: return "Point the dot at the gas meter, then tap +. Distance is from the battery’s nearest edge."
            case .meterHeight: return "Point the dot at the ground under the meter, then tap +."
            }
        }
        if scene.draftMeasurementEnd == nil {
            return "Now point at the meter face."
        }
        return "Tap Next if this distance looks right."
    }

    @ViewBuilder
    private var distanceReadout: some View {
        if isShowingLiveDistance {
            LiveDistanceText(readout: liveReadout)
        } else if let readout {
            Text(readout)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var isShowingLiveDistance: Bool {
        guard case .measure(let kind) = step, !showingSavedMeasure else { return false }
        return scene.draftMeasurementEnd == nil && (scene.draftMeasurementStart != nil || kind.startsAtBattery)
    }

    private var readout: String? {
        guard case .measure(let kind) = step else { return nil }
        if let start = scene.draftMeasurementStart?.position.simd,
           let end = scene.draftMeasurementEnd?.position.simd {
            return formatFeet(kind.feet(from: start, to: end))
        }
        if showingSavedMeasure, let saved = scene.confirmedMeasurements.first(where: { $0.kind == kind }) {
            return formatFeet(saved.distanceFeet)
        }
        return nil
    }

    /// Plane updates arrive several times a second and would otherwise rebuild the buttons mid-tap.
    private func acceptScene(_ snapshot: PlacementSceneSnapshot) {
        var incoming = snapshot
        var current = scene
        incoming.verticalPlanes = []
        current.verticalPlanes = []
        guard incoming != current else { return }
        scene = snapshot
    }

    private func acceptLiveFeet(_ feet: Double?) {
        let text = feet.map(formatFeet)
        guard liveReadout.text != text else { return }
        liveReadout.text = text
    }

    private func formatFeet(_ feet: Double) -> String {
        let totalInches = Int((feet * 12).rounded())
        let whole = totalInches / 12
        let inches = abs(totalInches) % 12
        if whole == 0 { return "\(inches) in" }
        if inches == 0 { return "\(whole) ft" }
        return "\(whole) ft \(inches) in"
    }

    private func primaryAction() {
        if primaryIsAdvance {
            if case .measure = step, scene.draftMeasurementEnd != nil {
                store.placementController?.confirmMeasurement()
            }
            goForward()
        } else {
            statusMessage = nil
            store.placementController?.commitAim()
        }
    }

    private func secondaryAction() {
        switch step {
        case .gas:
            store.setGasMeterNotVisible(true)
            store.placementController?.clearGasMarker()
            step = .measure(.meterHeight)
        case .measure where showingSavedMeasure:
            remeasure = true
            store.placementController?.resetMeasurementDraft()
        case .measure, .workingSpace:
            goForward()
        default:
            break
        }
    }

    private func answer(_ value: Bool?) {
        switch step {
        case .workingSpace:
            store.placementController?.setWorkingSpaceClear(value)
        case .footprint:
            store.placementController?.setFootprintClear(value)
        case .transfer:
            store.placementController?.setTransferSwitchClear(value)
        case .sameWall:
            store.placementController?.setSameWall(value)
        default:
            break
        }
        goForward()
    }

    private func goForward() {
        switch step {
        case .battery: step = .meter
        case .meter: step = .panel
        case .panel: step = .measure(.batteryToMeter)
        case .measure(.batteryToMeter): step = .measure(.batteryToWall)
        case .measure(.batteryToWall): step = .gas
        case .gas:
            if scene.gasMeterPosition != nil {
                store.setGasMeterNotVisible(false)
                step = .measure(.batteryToGasMeter)
            } else {
                step = .measure(.meterHeight)
            }
        case .measure(.batteryToGasMeter): step = .measure(.meterHeight)
        case .measure(.meterHeight): step = .workingSpace
        case .workingSpace: step = .footprint
        case .footprint: step = .transfer
        case .transfer: step = .sameWall
        case .sameWall: step = .finish
        case .finish: break
        }
    }

    private func goBack() {
        switch step {
        case .battery: break
        case .meter: step = .battery
        case .panel: step = .meter
        case .measure(.batteryToMeter): step = .panel
        case .measure(.batteryToWall): step = .measure(.batteryToMeter)
        case .gas: step = .measure(.batteryToWall)
        case .measure(.batteryToGasMeter): step = .gas
        case .measure(.meterHeight):
            step = scene.gasMeterPosition != nil ? .measure(.batteryToGasMeter) : .gas
        case .workingSpace: step = .measure(.meterHeight)
        case .footprint: step = .workingSpace
        case .transfer: step = .footprint
        case .sameWall: step = .transfer
        case .finish: step = .sameWall
        }
    }

    private func saveAndReview() {
        guard !isSaving else { return }
        guard scene.batteryPosition != nil else { return }
        var committed = store.placementController?.scene ?? scene
        committed.batteryYawRadians = yawRadians
        store.commitPlacement(committed)
        let token = UUID()
        pendingSave = token
        screenshotToken = token
        statusMessage = nil
        Task {
            try? await Task.sleep(for: .seconds(5))
            failScreenshot(token)
        }
    }

    /// Keeps review and export in step with the scene when the user leaves without Save.
    private func commitLiveScene() {
        guard let live = store.placementController?.scene, live.hasPlacedContent else { return }
        store.commitPlacement(live)
    }

    private func handleScreenshot(_ image: UIImage?) {
        if let image {
            store.attachPlacementScreenshot(image)
            advance(pendingSave)
        } else {
            failScreenshot(pendingSave)
        }
    }

    private func advance(_ token: UUID?) {
        guard let token, token == pendingSave else { return }
        pendingSave = nil
        onContinue()
    }

    private func failScreenshot(_ token: UUID?) {
        guard let token, token == pendingSave else { return }
        pendingSave = nil
        screenshotToken = nil
        statusMessage = "Placement screenshot did not capture. Tap Save again."
    }
}

@MainActor
@Observable
private final class LiveDistanceReadout {
    var text: String?
}

private struct LiveDistanceText: View {
    var readout: LiveDistanceReadout

    var body: some View {
        if let text = readout.text {
            Text(text)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

private struct PlacementARRepresentable: UIViewRepresentable {
    var controller: PlacementSceneController
    var mode: PlacementTarget
    var measurementMode: Bool
    var measurementKind: PlacementMeasurementKind
    var editingWorkingSpace: Bool
    var inputEnabled: Bool
    var aimEnabled: Bool
    var tapEnabled: Bool
    var yawRadians: Float
    var tone: PlacementTone
    var screenshotToken: UUID?
    var onSceneChange: (PlacementSceneSnapshot) -> Void
    var onYawChange: (Float) -> Void
    var onLiveFeet: (Double?) -> Void
    var onScreenshot: (UIImage?) -> Void
    var onFailure: (String) -> Void
    var onCoachingActiveChange: (Bool) -> Void

    func makeUIView(context: Context) -> ARView {
        controller.prepareIfNeeded()
        return controller.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        controller.bind(
            mode: mode,
            measurementMode: measurementMode,
            measurementKind: measurementKind,
            editingWorkingSpace: editingWorkingSpace,
            inputEnabled: inputEnabled,
            aimEnabled: aimEnabled,
            tapEnabled: tapEnabled,
            yawRadians: yawRadians,
            tone: tone,
            screenshotToken: screenshotToken,
            onSceneChange: onSceneChange,
            onYawChange: onYawChange,
            onLiveFeet: onLiveFeet,
            onScreenshot: onScreenshot,
            onFailure: onFailure,
            onCoachingActiveChange: onCoachingActiveChange
        )
    }
}

/// Owns the AR session for one survey. The placement screen can disappear without dropping marks,
/// because a new session would not share the old world coordinates.
@MainActor
final class PlacementSceneController: NSObject, ARSessionDelegate, ARCoachingOverlayViewDelegate {
    let arView = ARView(frame: .zero)
    private(set) var scene = PlacementSceneSnapshot()
    var yawRadians: Float = 0
    fileprivate var walkStep: WalkStep = .battery
    fileprivate var hasChosenWalkStep = false

    private var mode: PlacementTarget = .battery
    private var measurementMode = false
    private var measurementKind: PlacementMeasurementKind = .batteryToMeter
    private var editingWorkingSpace = false
    private var inputEnabled = true
    private var aimEnabled = false
    private var tapEnabled = false
    private var coachingActive = false
    private var configuration: ARWorldTrackingConfiguration?
    private var isPrepared = false
    private var screenshotInFlight = false
    private var pauseRequested = false
    private var onSceneChange: ((PlacementSceneSnapshot) -> Void)?
    private var onYawChange: ((Float) -> Void)?
    private var onScreenshot: ((UIImage?) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var onCoachingActiveChange: ((Bool) -> Void)?
    private var onLiveFeet: ((Double?) -> Void)?
    private var root: AnchorEntity?
        var measurementMarkers: [ModelEntity] = []
        var measurementEndpoints: [MeasurementEndpoint] = []
        var measurementLine: ModelEntity?
        var draggedMeasurementIndex: Int?
        var measurementIsConfirmed = false
        var workingSpaceOverlay: ModelEntity?
        var batteryRig: Entity?
        var batteryBody: ModelEntity?
        var footprintPad: ModelEntity?
        var meterMarker: ModelEntity?
        var meterWallMarker: ModelEntity?
        var meterWallHit: (position: SIMD3<Float>, normal: SIMD3<Float>)?
        var panelMarker: ModelEntity?
        var panelWallMarker: ModelEntity?
        var panelWallHit: (position: SIMD3<Float>, normal: SIMD3<Float>)?
        var gasMarker: ModelEntity?
        var planes: [UUID: PlaneSample] = [:]
        /// Sub-sampled world-space mesh vertices, keyed by ARMeshAnchor identifier so removals stay cheap.
        var meshSamples: [UUID: [SIMD3<Float>]] = [:]
        var lidarMeshAvailable = false
        var appliedYaw: Float = 0
        var rotationStartYaw: Float = 0
        var appliedTone: PlacementTone?
        var lastScreenshotToken: UUID?
        var lastPlaneEmit = Date.distantPast
        var aimLink: CADisplayLink?
        var reticle: ModelEntity?
        var liveLine: ModelEntity?
        var lastLiveFeet: Double?
        let aimDot = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 14))

        func prepareIfNeeded() {
            guard !isPrepared else { return }
            isPrepared = true
            arView.automaticallyConfigureSession = false
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.environmentTexturing = .automatic
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                configuration.sceneReconstruction = .mesh
                lidarMeshAvailable = true
                arView.environment.sceneUnderstanding.options.insert(.occlusion)
            }
            self.configuration = configuration
            arView.session.delegate = self

            let coaching = ARCoachingOverlayView()
            coaching.session = arView.session
            coaching.goal = .horizontalPlane
            coaching.activatesAutomatically = true
            coaching.delegate = self
            coaching.frame = arView.bounds
            coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            arView.addSubview(coaching)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            tap.require(toFail: rotation)
            arView.addGestureRecognizer(tap)
            arView.addGestureRecognizer(pan)
            arView.addGestureRecognizer(rotation)

            let anchor = AnchorEntity(world: .zero)
            arView.scene.addAnchor(anchor)
            root = anchor

            aimDot.layer.cornerRadius = 7
            aimDot.backgroundColor = .white
            aimDot.layer.shadowColor = UIColor.black.cgColor
            aimDot.layer.shadowOpacity = 0.45
            aimDot.layer.shadowRadius = 2
            aimDot.layer.shadowOffset = .zero
            aimDot.isUserInteractionEnabled = false
            aimDot.isHidden = true
            arView.addSubview(aimDot)
            emit()
        }

        func bind(
            mode: PlacementTarget,
            measurementMode: Bool,
            measurementKind: PlacementMeasurementKind,
            editingWorkingSpace: Bool,
            inputEnabled: Bool,
            aimEnabled: Bool,
            tapEnabled: Bool,
            yawRadians: Float,
            tone: PlacementTone,
            screenshotToken: UUID?,
            onSceneChange: @escaping (PlacementSceneSnapshot) -> Void,
            onYawChange: @escaping (Float) -> Void,
            onLiveFeet: @escaping (Double?) -> Void,
            onScreenshot: @escaping (UIImage?) -> Void,
            onFailure: @escaping (String) -> Void,
            onCoachingActiveChange: @escaping (Bool) -> Void
        ) {
            self.mode = mode
            if self.measurementKind != measurementKind {
                self.measurementKind = measurementKind
                resetMeasurementDraft()
            }
            self.measurementMode = measurementMode
            self.editingWorkingSpace = editingWorkingSpace
            self.inputEnabled = inputEnabled
            self.aimEnabled = aimEnabled
            self.tapEnabled = tapEnabled
            self.onSceneChange = onSceneChange
            self.onYawChange = onYawChange
            self.onLiveFeet = onLiveFeet
            self.onScreenshot = onScreenshot
            self.onFailure = onFailure
            self.onCoachingActiveChange = onCoachingActiveChange
            if !aimEnabled {
                reticle?.isEnabled = false
                aimDot.isHidden = true
                hideLiveLine()
            }
            if abs(appliedYaw - yawRadians) > 0.0001 {
                self.yawRadians = yawRadians
                appliedYaw = yawRadians
                applyYaw()
                emit()
            }
            if appliedTone != tone {
                appliedTone = tone
                applyTone()
            }
            if let screenshotToken, screenshotToken != lastScreenshotToken {
                lastScreenshotToken = screenshotToken
                takeScreenshot()
            }
        }

        func resume() {
            pauseRequested = false
            prepareIfNeeded()
            guard let configuration else { return }
            arView.session.run(configuration, options: [])
            startAiming()
        }

        func pauseIfIdle() {
            guard isPrepared else { return }
            guard !screenshotInFlight else {
                pauseRequested = true
                return
            }
            pauseRequested = false
            // Any in-flight rotation gesture is invalidated by pausing the session.
            rotationStartYaw = appliedYaw
            stopAiming()
            arView.session.pause()
        }

        func stop() {
            stopAiming()
            onSceneChange = nil
            onYawChange = nil
            onScreenshot = nil
            onFailure = nil
            onLiveFeet = nil
            onCoachingActiveChange = nil
            screenshotInFlight = false
            pauseRequested = false
            if isPrepared {
                arView.session.pause()
                arView.session.delegate = nil
            }
            arView.removeFromSuperview()
        }

        nonisolated func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
            Task { @MainActor in
                self.coachingActive = true
                self.aimDot.isHidden = true
                self.onCoachingActiveChange?(true)
            }
        }

        nonisolated func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
            Task { @MainActor in
                self.coachingActive = false
                self.onCoachingActiveChange?(false)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, inputEnabled, tapEnabled else { return }
            let point = gesture.location(in: arView)
            if measurementMode {
                if editingWorkingSpace {
                    guard let hit = raycastPoint(at: point, alignment: .horizontal) else { return }
                    placeWorkingSpace(at: hit.position.simd)
                } else {
                    addMeasurementPoint(at: point)
                }
                emit()
                return
            }
            var didPlace = false
            switch mode {
            case .battery:
                if let position = groundPosition(in: arView, at: point) {
                    placeBattery(at: position)
                    didPlace = true
                }
            case .meter, .panel:
                // Two-stage: try a wall hit first (user tilting at the meter/panel on a vertical plane); fall back to a ground hit.
                if let wallHit = wallHit(in: arView, at: point) {
                    placeWallMarker(kind: mode, hit: wallHit)
                    didPlace = true
                } else if let position = groundPosition(in: arView, at: point) {
                    placeMarker(kind: mode, at: position)
                    didPlace = true
                }
            case .gasMeter:
                if let position = groundPosition(in: arView, at: point) {
                    placeMarker(kind: .gasMeter, at: position)
                    didPlace = true
                }
            }
            if didPlace { emit() }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard inputEnabled else { return }
            if measurementMode {
                if editingWorkingSpace {
                    if let hit = raycastPoint(at: gesture.location(in: arView), alignment: .horizontal) {
                        placeWorkingSpace(at: hit.position.simd)
                        emitPlanesIfNeeded()
                    }
                } else {
                    dragMeasurementPoint(gesture)
                }
                if gesture.state == .ended || gesture.state == .cancelled { emitGestureEnded() }
                return
            }
            guard mode == .battery, batteryRig != nil else { return }
            let finished = gesture.state == .ended || gesture.state == .cancelled
            if let position = groundPosition(in: arView, at: gesture.location(in: arView)) {
                batteryRig?.position = position
            } else if !finished {
                return
            }
            if finished {
                emitGestureEnded()
            } else {
                emitPlanesIfNeeded()
            }
        }

        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard inputEnabled else { return }
            if measurementMode {
                guard editingWorkingSpace, workingSpaceOverlay != nil else { return }
                switch gesture.state {
                case .began: rotationStartYaw = scene.workingSpaceYawRadians
                case .changed, .ended, .cancelled:
                    scene.workingSpaceYawRadians = rotationStartYaw - Float(gesture.rotation)
                    applyWorkingSpaceYaw()
                    emitPlanesIfNeeded()
                default: break
                }
                return
            }
            guard mode == .battery, batteryRig != nil else { return }
            switch gesture.state {
            case .began:
                rotationStartYaw = appliedYaw
            case .changed, .ended:
                // Gesture rotation is clockwise-positive on screen; yaw about +Y is counterclockwise-positive from above.
                let yaw = rotationStartYaw - Float(gesture.rotation)
                yawRadians = yaw
                appliedYaw = yaw
                applyYaw()
                onYawChange?(yaw)
                if gesture.state == .changed {
                    emitPlanesIfNeeded()
                } else {
                    emitGestureEnded()
                }
            case .cancelled:
                // System cancels happen on scenePhase changes or interruptions; roll back the partial rotation.
                yawRadians = rotationStartYaw
                appliedYaw = rotationStartYaw
                applyYaw()
                onYawChange?(rotationStartYaw)
                emitGestureEnded()
            default:
                break
            }
        }

        func applyYaw() {
            batteryRig?.orientation = simd_quatf(angle: appliedYaw, axis: SIMD3(0, 1, 0))
        }

        func applyTone() {
            guard let tone = appliedTone else { return }
            let color = ToneStyle.uiColor(tone)
            batteryBody?.model?.materials = [SimpleMaterial(color: color, isMetallic: false)]
            footprintPad?.model?.materials = [UnlitMaterial(color: color.withAlphaComponent(0.35))]
        }

        func takeScreenshot() {
            screenshotInFlight = true
            arView.snapshot(saveToHDR: false) { [weak self] image in
                Task { @MainActor in
                    self?.finishScreenshot(image)
                }
            }
        }

        private func finishScreenshot(_ image: UIImage?) {
            screenshotInFlight = false
            onScreenshot?(image)
            if pauseRequested {
                pauseIfIdle()
            }
        }

        func emit() {
            let snapshot = makeSnapshot()
            scene = snapshot
            let change = onSceneChange
            Task { @MainActor in
                change?(snapshot)
            }
        }

        nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            upsertPlanes(from: anchors)
            upsertMesh(from: anchors)
        }

        nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            upsertPlanes(from: anchors)
            upsertMesh(from: anchors)
        }

        /// LiDAR mesh anchors update many times a second; skip the hop to the main actor when no wall changed.
        private nonisolated func upsertPlanes(from anchors: [ARAnchor]) {
            let samples = Self.planeSamples(from: anchors)
            guard !samples.isEmpty else { return }
            Task { @MainActor in
                self.upsert(samples)
            }
        }

        private nonisolated func upsertMesh(from anchors: [ARAnchor]) {
            let samples = Self.meshSamples(from: anchors)
            guard !samples.isEmpty else { return }
            Task { @MainActor in
                self.upsertMesh(samples)
            }
        }

        nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            let ids = anchors.map(\.identifier)
            Task { @MainActor in
                for id in ids {
                    self.planes.removeValue(forKey: id)
                    self.meshSamples.removeValue(forKey: id)
                }
                self.emitPlanesIfNeeded()
            }
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            let message = error.localizedDescription
            Task { @MainActor in
                self.onFailure?(message)
            }
        }

        private func upsert(_ samples: [PlaneSample]) {
            for sample in samples {
                planes[sample.id] = sample
            }
            emitPlanesIfNeeded()
        }

        private func upsertMesh(_ samples: [(id: UUID, points: [SIMD3<Float>])]) {
            for sample in samples {
                meshSamples[sample.id] = sample.points
            }
            emitPlanesIfNeeded()
        }

        private func emitPlanesIfNeeded() {
            guard batteryRig != nil else { return }
            let now = Date()
            guard now.timeIntervalSince(lastPlaneEmit) > 0.4 else { return }
            lastPlaneEmit = now
            emit()
        }

        private func emitGestureEnded() {
            lastPlaneEmit = Date()
            emit()
        }

        private func placeBattery(at position: SIMD3<Float>) {
            if batteryRig == nil {
                let rig = Entity()
                let padMesh = MeshResource.generateBox(
                    width: BatteryGeometry.footprintMeters,
                    height: 0.012,
                    depth: BatteryGeometry.footprintMeters
                )
                let pad = ModelEntity(mesh: padMesh, materials: [UnlitMaterial(color: UIColor.systemOrange.withAlphaComponent(0.35))])
                pad.position.y = 0.006

                let bodyMesh = MeshResource.generateBox(
                    width: BatteryGeometry.widthMeters,
                    height: BatteryGeometry.heightMeters,
                    depth: BatteryGeometry.depthMeters
                )
                let body = ModelEntity(mesh: bodyMesh, materials: [SimpleMaterial(color: .systemOrange, isMetallic: false)])
                body.position.y = 0.012 + BatteryGeometry.heightMeters / 2

                let markMesh = MeshResource.generateBox(width: 0.08, height: 0.08, depth: 0.02)
                let mark = ModelEntity(mesh: markMesh, materials: [UnlitMaterial(color: .darkGray)])
                mark.position = SIMD3(
                    0,
                    BatteryGeometry.heightMeters * 0.72,
                    BatteryGeometry.depthMeters / 2 + 0.01
                )

                rig.addChild(pad)
                rig.addChild(body)
                rig.addChild(mark)
                root?.addChild(rig)
                batteryRig = rig
                footprintPad = pad
                batteryBody = body
                applyTone()
            }
            batteryRig?.position = position
            applyYaw()
        }

        private func placeMarker(kind: PlacementTarget, at position: SIMD3<Float>) {
            let existing: ModelEntity?
            switch kind {
            case .meter: existing = meterMarker
            case .panel: existing = panelMarker
            case .gasMeter: existing = gasMarker
            case .battery: existing = nil
            }
            let lift: Float = kind == .meter ? 0.14 : 0
            if let existing {
                existing.position = SIMD3(position.x, position.y + lift, position.z)
                return
            }
            let marker: ModelEntity
            switch kind {
            case .meter:
                let mesh = MeshResource.generateBox(width: 0.14, height: 0.28, depth: 0.14)
                marker = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)])
            case .panel:
                let mesh = MeshResource.generateBox(width: 0.14, height: 0.28, depth: 0.14)
                marker = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .systemIndigo, isMetallic: false)])
            case .gasMeter:
                let mesh = MeshResource.generateSphere(radius: 0.08)
                marker = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .systemPurple, isMetallic: false)])
            case .battery:
                return
            }
            marker.position = SIMD3(position.x, position.y + lift, position.z)
            root?.addChild(marker)
            switch kind {
            case .meter: meterMarker = marker
            case .panel: panelMarker = marker
            case .gasMeter: gasMarker = marker
            case .battery: break
            }
        }

        private func placeWallMarker(kind: PlacementTarget, hit: (position: SIMD3<Float>, normal: SIMD3<Float>)) {
            let color: UIColor
            switch kind {
            case .meter: color = .systemBlue
            case .panel: color = .systemIndigo
            default: return
            }
            let existing: ModelEntity?
            switch kind {
            case .meter: existing = meterWallMarker
            case .panel: existing = panelWallMarker
            default: existing = nil
            }
            let marker: ModelEntity
            if let existing {
                marker = existing
            } else {
                // Small disc on the wall so the user sees where their tap landed.
                let mesh = MeshResource.generateBox(width: 0.10, height: 0.10, depth: 0.02)
                marker = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: color, isMetallic: false)])
                root?.addChild(marker)
                switch kind {
                case .meter: meterWallMarker = marker
                case .panel: panelWallMarker = marker
                default: break
                }
            }
            marker.position = hit.position
            // Rotate the disc so its short axis points along the wall's outward normal.
            marker.orientation = simd_quatf(from: SIMD3(0, 0, 1), to: hit.normal)
            switch kind {
            case .meter: meterWallHit = hit
            case .panel: panelWallHit = hit
            default: break
            }
        }

        func commitAim() {
            guard inputEnabled else { return }
            let point = CGPoint(x: arView.bounds.midX, y: max(arView.bounds.height * 0.42, 1))
            if measurementMode {
                if editingWorkingSpace {
                    guard let hit = raycastPoint(at: point, alignment: .horizontal) else {
                        onFailure?("Point the dot at the ground and try again.")
                        return
                    }
                    placeWorkingSpace(at: hit.position.simd)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    emit()
                    return
                }
                let before = measurementEndpoints.count
                addMeasurementPoint(at: point)
                guard measurementEndpoints.count != before else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                emit()
                return
            }
            if mode == .meter || mode == .panel, let wall = wallHit(in: arView, at: point) {
                placeWallMarker(kind: mode, hit: wall)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                emit()
                return
            }
            guard let position = markerPosition(at: point) else {
                onFailure?(mode == .gasMeter
                    ? "Point the dot at the gas meter and try again."
                    : "Point the dot at the ground and try again.")
                return
            }
            switch mode {
            case .battery:
                placeBattery(at: position)
            case .meter, .panel:
                placeMarker(kind: mode, at: position)
            case .gasMeter:
                placeMarker(kind: .gasMeter, at: position)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            emit()
        }

        func clearGasMarker() {
            gasMarker?.removeFromParent()
            gasMarker = nil
            scene.gasMeterPosition = nil
            scene.confirmedMeasurements.removeAll { $0.kind == .batteryToGasMeter }
            emit()
        }

        func startAiming() {
            guard aimLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tickAim))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 12, maximum: 20, preferred: 15)
            link.add(to: .main, forMode: .common)
            aimLink = link
        }

        func stopAiming() {
            aimLink?.invalidate()
            aimLink = nil
            reticle?.isEnabled = false
            aimDot.isHidden = true
            hideLiveLine()
        }

        @objc func tickAim() {
            let showDot = aimEnabled && !coachingActive && arView.bounds.width > 1
            guard showDot else {
                aimDot.isHidden = true
                reticle?.isEnabled = false
                hideLiveLine()
                publishLiveFeet(nil)
                return
            }
            let point = CGPoint(x: arView.bounds.midX, y: arView.bounds.height * 0.42)
            aimDot.center = point
            aimDot.isHidden = false
            let alignment: ARRaycastQuery.TargetAlignment =
                (measurementMode && !editingWorkingSpace) || (!measurementMode && mode == .gasMeter) ? .any : .horizontal
            guard let endpoint = raycastPoint(at: point, alignment: alignment) else {
                reticle?.isEnabled = false
                hideLiveLine()
                publishLiveFeet(nil)
                return
            }
            let position = endpoint.position.simd
            placeReticle(at: position)
            let start: SIMD3<Float>
            if measurementMode, !editingWorkingSpace, measurementEndpoints.count == 1 {
                start = measurementEndpoints[0].position.simd
            } else if measurementMode, !editingWorkingSpace, measurementEndpoints.isEmpty,
                      measurementKind.startsAtBattery, let battery = batteryRig?.position(relativeTo: nil) {
                start = BatteryGeometry.nearestBasePoint(origin: battery, yaw: appliedYaw, toward: position)
            } else {
                hideLiveLine()
                publishLiveFeet(nil)
                return
            }
            updateLiveLine(from: start, to: position)
            publishLiveFeet(measurementKind.feet(from: start, to: position))
        }

        func placeReticle(at position: SIMD3<Float>) {
            if reticle == nil {
                let dot = ModelEntity(
                    mesh: .generateSphere(radius: 0.02),
                    materials: [UnlitMaterial(color: .white)]
                )
                root?.addChild(dot)
                reticle = dot
            }
            reticle?.isEnabled = true
            let camera = arView.cameraTransform.translation
            let offset = camera - position
            let length = simd_length(offset)
            if length > 0.05 {
                reticle?.position = position + (offset / length) * 0.03
            } else {
                reticle?.position = position
            }
        }

        func updateLiveLine(from start: SIMD3<Float>, to end: SIMD3<Float>) {
            let delta = end - start
            let length = simd_length(delta)
            guard length > 0.02 else {
                liveLine?.isEnabled = false
                return
            }
            if liveLine == nil {
                let line = ModelEntity(
                    mesh: .generateBox(width: 0.012, height: 1, depth: 0.012),
                    materials: [UnlitMaterial(color: .systemYellow)]
                )
                root?.addChild(line)
                liveLine = line
            }
            liveLine?.isEnabled = true
            liveLine?.scale = SIMD3(1, length, 1)
            liveLine?.position = (start + end) / 2
            liveLine?.orientation = Self.lineOrientation(delta / length)
        }

        private static func lineOrientation(_ direction: SIMD3<Float>) -> simd_quatf {
            let up = SIMD3<Float>(0, 1, 0)
            if abs(simd_dot(direction, up)) > 0.999 {
                return simd_quatf(angle: direction.y >= 0 ? 0 : .pi, axis: SIMD3(1, 0, 0))
            }
            return simd_quatf(from: up, to: direction)
        }

        func hideLiveLine() {
            liveLine?.isEnabled = false
        }

        func publishLiveFeet(_ feet: Double?) {
            switch (lastLiveFeet, feet) {
            case (nil, nil):
                return
            case let (previous?, next?) where abs(previous - next) < 0.03:
                return
            default:
                lastLiveFeet = feet
                onLiveFeet?(feet)
            }
        }

        func undoMeasurementPoint() {
            guard !measurementEndpoints.isEmpty else { return }
            if measurementKind.startsAtBattery {
                resetMeasurementDraft()
                return
            }
            measurementEndpoints.removeLast()
            measurementMarkers.removeLast().removeFromParent()
            measurementIsConfirmed = false
            rebuildMeasurementLine()
            emit()
        }

        func resetMeasurementDraft() {
            measurementEndpoints.removeAll()
            measurementMarkers.forEach { $0.removeFromParent() }
            measurementMarkers.removeAll()
            measurementLine?.removeFromParent()
            measurementLine = nil
            draggedMeasurementIndex = nil
            measurementIsConfirmed = false
            hideLiveLine()
            emit()
        }

        func confirmMeasurement() {
            guard measurementEndpoints.count == 2 else { return }
            let distanceFeet = measurementKind.feet(
                from: measurementEndpoints[0].position.simd,
                to: measurementEndpoints[1].position.simd
            )
            let method: MeasurementCaptureMethod
            if measurementEndpoints.contains(where: { $0.captureMethod == .estimatedPlane }) {
                method = .estimatedPlane
            } else {
                method = .existingPlane
            }
            let confirmed = ConfirmedPlacementMeasurement(
                kind: measurementKind,
                start: measurementEndpoints[0],
                end: measurementEndpoints[1],
                distanceFeet: distanceFeet,
                captureMethod: method,
                confirmedAt: Date()
            )
            scene.confirmedMeasurements.removeAll { $0.kind == measurementKind }
            scene.confirmedMeasurements.append(confirmed)
            measurementIsConfirmed = true
            applyMeasurementColor(.systemGreen)
            emit()
        }

        func rotateWorkingSpace(by radians: Float) {
            guard workingSpaceOverlay != nil else { return }
            scene.workingSpaceYawRadians += radians
            applyWorkingSpaceYaw()
            emit()
        }

        func setFootprintClear(_ value: Bool?) { scene.footprintIsClear = value; emit() }
        func setWorkingSpaceClear(_ value: Bool?) { scene.frontWorkingSpaceIsClear = value; emit() }
        func setTransferSwitchClear(_ value: Bool?) { scene.transferSwitchClearanceObserved = value; emit() }
        func setSameWall(_ value: Bool?) { scene.meterAndPanelShareWall = value; emit() }

        private func addMeasurementPoint(at point: CGPoint) {
            if measurementEndpoints.count == 2 { resetMeasurementDraft() }
            guard let endpoint = raycastPoint(at: point, alignment: .any) else {
                onFailure?("No surface found there. Move your phone slowly and try again.")
                return
            }
            measurementIsConfirmed = false
            if measurementEndpoints.isEmpty, measurementKind.startsAtBattery {
                guard let start = batteryEndpoint(toward: endpoint) else {
                    onFailure?("Place the battery first.")
                    return
                }
                appendMeasurementMarker(start)
            }
            appendMeasurementMarker(endpoint)
            if measurementEndpoints.count == 2 {
                hideLiveLine()
            }
            rebuildMeasurementLine()
        }

        private func appendMeasurementMarker(_ endpoint: MeasurementEndpoint) {
            let marker = ModelEntity(
                mesh: .generateSphere(radius: 0.025),
                materials: [SimpleMaterial(color: .systemOrange, isMetallic: false)]
            )
            marker.position = endpoint.position.simd
            root?.addChild(marker)
            measurementEndpoints.append(endpoint)
            measurementMarkers.append(marker)
        }

        /// The raycast cannot hit the virtual battery, so its end is the base edge nearest the target.
        private func batteryEndpoint(toward target: MeasurementEndpoint) -> MeasurementEndpoint? {
            guard let battery = batteryRig?.position(relativeTo: nil) else { return nil }
            let point = BatteryGeometry.nearestBasePoint(origin: battery, yaw: appliedYaw, toward: target.position.simd)
            return MeasurementEndpoint(position: PlacementAnchor(point), captureMethod: target.captureMethod)
        }

        private func dragMeasurementPoint(_ gesture: UIPanGestureRecognizer) {
            let screenPoint = gesture.location(in: arView)
            if gesture.state == .began {
                draggedMeasurementIndex = measurementMarkers.enumerated().min { lhs, rhs in
                    let left = arView.project(lhs.element.position(relativeTo: nil)).map { hypot($0.x - screenPoint.x, $0.y - screenPoint.y) } ?? .greatestFiniteMagnitude
                    let right = arView.project(rhs.element.position(relativeTo: nil)).map { hypot($0.x - screenPoint.x, $0.y - screenPoint.y) } ?? .greatestFiniteMagnitude
                    return left < right
                }?.offset
                if measurementKind.startsAtBattery, measurementEndpoints.count == 2 {
                    draggedMeasurementIndex = 1
                }
            }
            guard let index = draggedMeasurementIndex,
                  measurementEndpoints.indices.contains(index),
                  let endpoint = raycastPoint(at: screenPoint, alignment: .any) else { return }
            measurementEndpoints[index] = endpoint
            measurementMarkers[index].position = endpoint.position.simd
            if measurementKind.startsAtBattery, index == 1, let start = batteryEndpoint(toward: endpoint) {
                measurementEndpoints[0] = start
                measurementMarkers[0].position = start.position.simd
            }
            measurementIsConfirmed = false
            applyMeasurementColor(.systemOrange)
            rebuildMeasurementLine()
            if gesture.state == .ended || gesture.state == .cancelled { draggedMeasurementIndex = nil }
        }

        private func rebuildMeasurementLine() {
            measurementLine?.removeFromParent()
            measurementLine = nil
            guard measurementEndpoints.count == 2 else { return }
            let start = measurementEndpoints[0].position.simd
            let end = measurementEndpoints[1].position.simd
            let delta = end - start
            let length = simd_length(delta)
            guard length > 0.001 else { return }
            let line = ModelEntity(
                mesh: .generateBox(width: 0.016, height: length, depth: 0.016),
                materials: [SimpleMaterial(color: measurementIsConfirmed ? .systemGreen : .systemOrange, isMetallic: false)]
            )
            line.position = (start + end) / 2
            line.orientation = Self.lineOrientation(delta / length)
            root?.addChild(line)
            measurementLine = line
        }

        private func applyMeasurementColor(_ color: UIColor) {
            let material = SimpleMaterial(color: color, isMetallic: false)
            measurementMarkers.forEach { $0.model?.materials = [material] }
            measurementLine?.model?.materials = [material]
        }

        private func placeWorkingSpace(at position: SIMD3<Float>) {
            if workingSpaceOverlay == nil {
                let mesh = MeshResource.generateBox(
                    width: BatteryGeometry.workingSpaceWidthMeters,
                    height: 0.01,
                    depth: BatteryGeometry.workingSpaceDepthMeters
                )
                let overlay = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: UIColor.systemTeal.withAlphaComponent(0.4))])
                root?.addChild(overlay)
                workingSpaceOverlay = overlay
            }
            workingSpaceOverlay?.position = SIMD3(position.x, position.y + 0.005, position.z)
            scene.workingSpacePosition = PlacementAnchor(position)
            applyWorkingSpaceYaw()
        }

        private func applyWorkingSpaceYaw() {
            workingSpaceOverlay?.orientation = simd_quatf(angle: scene.workingSpaceYawRadians, axis: SIMD3(0, 1, 0))
        }

        private func raycastPoint(at point: CGPoint, alignment: ARRaycastQuery.TargetAlignment) -> MeasurementEndpoint? {
            if let hit = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: alignment).first {
                let column = hit.worldTransform.columns.3
                return MeasurementEndpoint(position: PlacementAnchor(SIMD3(column.x, column.y, column.z)), captureMethod: .existingPlane)
            }
            guard let hit = arView.raycast(from: point, allowing: .estimatedPlane, alignment: alignment).first else { return nil }
            let column = hit.worldTransform.columns.3
            return MeasurementEndpoint(
                position: PlacementAnchor(SIMD3(column.x, column.y, column.z)),
                captureMethod: .estimatedPlane
            )
        }

        /// Battery and electric-meter marks sit on the ground. The gas meter is marked where the user aims at it.
        private func markerPosition(at point: CGPoint) -> SIMD3<Float>? {
            if mode == .gasMeter {
                return raycastPoint(at: point, alignment: .any)?.position.simd
            }
            return groundPosition(in: arView, at: point)
        }

        private func groundPosition(in arView: ARView, at point: CGPoint) -> SIMD3<Float>? {
            let hit = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first
                ?? arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first
            guard let hit else { return nil }
            let column = hit.worldTransform.columns.3
            return SIMD3(column.x, column.y, column.z)
        }

        private func wallHit(in arView: ARView, at point: CGPoint) -> (position: SIMD3<Float>, normal: SIMD3<Float>)? {
            // Prefer real plane geometry so the meter/panel snaps to the actual detected wall.
            guard let hit = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .vertical).first else {
                return nil
            }
            let column = hit.worldTransform.columns.3
            let position = SIMD3<Float>(column.x, column.y, column.z)
            var normal = SIMD3<Float>(0, 0, 1)
            if let planeAnchor = hit.anchor as? ARPlaneAnchor {
                // The plane's local +Y in world space is the outward normal for a vertical ARPlaneAnchor.
                let up = planeAnchor.transform * SIMD4<Float>(0, 1, 0, 0)
                normal = SIMD3(up.x, up.y, up.z)
                let len = simd_length(normal)
                if len > 0.0001 { normal /= len }
            }
            return (position, normal)
        }

        private func makeSnapshot() -> PlacementSceneSnapshot {
            var snapshot = scene
            snapshot.lidarMeshAvailable = lidarMeshAvailable
            snapshot.verticalPlanes = Array(planes.values)
            snapshot.batteryYawRadians = appliedYaw
            if let batteryRig {
                snapshot.batteryPosition = PlacementAnchor(batteryRig.position(relativeTo: nil))
            }
            if let meterMarker {
                snapshot.meterPosition = PlacementAnchor(grounded(meterMarker.position(relativeTo: nil)))
            }
            if let meterWallHit {
                snapshot.meterWallPosition = PlacementAnchor(meterWallHit.position)
                snapshot.meterWallNormal = PlacementAnchor(meterWallHit.normal)
                // Fall back to projecting the wall X/Z as the ground position when the user only tapped the wall.
                if snapshot.meterPosition == nil {
                    snapshot.meterPosition = PlacementAnchor(SIMD3(meterWallHit.position.x, meterWallHit.position.y, meterWallHit.position.z))
                }
            }
            if let panelMarker {
                snapshot.panelPosition = PlacementAnchor(grounded(panelMarker.position(relativeTo: nil)))
            }
            if let panelWallHit {
                snapshot.panelWallPosition = PlacementAnchor(panelWallHit.position)
                snapshot.panelWallNormal = PlacementAnchor(panelWallHit.normal)
                if snapshot.panelPosition == nil {
                    snapshot.panelPosition = PlacementAnchor(SIMD3(panelWallHit.position.x, panelWallHit.position.y, panelWallHit.position.z))
                }
            }
            if let gasMarker {
                snapshot.gasMeterPosition = PlacementAnchor(gasMarker.position(relativeTo: nil))
            }
            snapshot.draftMeasurementStart = measurementEndpoints.first
            snapshot.draftMeasurementEnd = measurementEndpoints.count > 1 ? measurementEndpoints[1] : nil
            if let workingSpaceOverlay {
                snapshot.workingSpacePosition = PlacementAnchor(workingSpaceOverlay.position(relativeTo: nil))
            }
            if snapshot.batteryPosition != nil {
                snapshot.meshPointsNearBattery = meshPointsNearBattery(radiusMeters: 3)
            }
            return snapshot
        }

        /// Filter the whole mesh point cloud to those within a small bounding cylinder around the battery.
        /// Keeps the snapshot small (bounded by device room size) and skips the far walls entirely.
        private func meshPointsNearBattery(radiusMeters: Float) -> [PlacementAnchor] {
            guard let batteryRig else { return [] }
            let battery = batteryRig.position(relativeTo: nil)
            let radiusSquared = radiusMeters * radiusMeters
            var result: [PlacementAnchor] = []
            for (_, points) in meshSamples {
                for point in points {
                    let dx = point.x - battery.x
                    let dz = point.z - battery.z
                    if dx * dx + dz * dz <= radiusSquared {
                        result.append(PlacementAnchor(point))
                    }
                }
            }
            return result
        }

        private func grounded(_ position: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(position.x, position.y - 0.14, position.z)
        }

        /// Sub-sample vertices from every ARMeshAnchor to world space. Skips non-mesh anchors and empty geometries.
        /// Sampling `sampleStride` vertices keeps the point cloud small enough for per-frame checks; grass and curbs still register.
        private nonisolated static func meshSamples(from anchors: [ARAnchor], sampleStride: Int = 24) -> [(id: UUID, points: [SIMD3<Float>])] {
            anchors.compactMap { anchor in
                guard let mesh = anchor as? ARMeshAnchor else { return nil }
                let geometry = mesh.geometry
                let vertices = geometry.vertices
                let vertexCount = vertices.count
                guard vertexCount > 0 else { return nil }
                let stride = vertices.stride
                let offset = vertices.offset
                let basePointer = vertices.buffer.contents().advanced(by: offset)
                let transform = mesh.transform
                let floatSize = MemoryLayout<Float>.size
                var points: [SIMD3<Float>] = []
                points.reserveCapacity(vertexCount / sampleStride + 1)
                var index = 0
                while index < vertexCount {
                    let vertexPointer = basePointer.advanced(by: index * stride)
                    let x = vertexPointer.load(as: Float.self)
                    let y = vertexPointer.advanced(by: floatSize).load(as: Float.self)
                    let z = vertexPointer.advanced(by: floatSize * 2).load(as: Float.self)
                    let world = transform * SIMD4<Float>(x, y, z, 1)
                    points.append(SIMD3(world.x, world.y, world.z))
                    index += sampleStride
                }
                return (mesh.identifier, points)
            }
        }

        private nonisolated static func planeSamples(from anchors: [ARAnchor]) -> [PlaneSample] {
            anchors.compactMap { anchor in
                guard let plane = anchor as? ARPlaneAnchor, plane.alignment == .vertical else { return nil }
                // The patch is offset by `center` and its extent is turned by `rotationOnYAxis`, both in anchor space.
                let transform = plane.transform
                let extentRotation = simd_quatf(angle: plane.planeExtent.rotationOnYAxis, axis: SIMD3(0, 1, 0))
                func world(_ v: SIMD3<Float>, w: Float) -> SIMD3<Float> {
                    let p = transform * SIMD4(v.x, v.y, v.z, w)
                    return SIMD3(p.x, p.y, p.z)
                }
                return PlaneSample(
                    id: plane.identifier,
                    center: world(plane.center, w: 1),
                    xAxis: world(extentRotation.act(SIMD3(1, 0, 0)), w: 0),
                    normal: world(SIMD3(0, 1, 0), w: 0),
                    zAxis: world(extentRotation.act(SIMD3(0, 0, 1)), w: 0),
                    width: plane.planeExtent.width,
                    length: plane.planeExtent.height
                )
            }
        }
}
