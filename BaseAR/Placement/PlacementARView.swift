import ARKit
import os
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

/// Scan the meter and panel, then gas, and place the battery last so fit is judged from that spot.
private enum WalkStep: Equatable {
    case scan
    case gas
    case battery
    case finish

    var title: String {
        switch self {
        case .scan: "Scan equipment"
        case .gas: "Gas meter"
        case .battery: "Place battery"
        case .finish: "Save"
        }
    }

    static func firstIncomplete(in scene: PlacementSceneSnapshot, gasNotVisible: Bool) -> WalkStep {
        let meterReady = scene.meterPosition != nil || scene.meterWallPosition != nil
        let panelReady = scene.panelPosition != nil || scene.panelWallPosition != nil
        if !meterReady || !panelReady { return .scan }
        if scene.gasMeterPosition == nil && !gasNotVisible { return .gas }
        if scene.batteryPosition == nil { return .battery }
        return .finish
    }
}

private extension PlacementSceneSnapshot {
    func confirmed(_ kind: PlacementMeasurementKind) -> Bool {
        confirmedMeasurements.contains { $0.kind == kind }
    }
}

private struct PlacementSaveRequest {
    let snapshot: PlacementSceneSnapshot
    let identity: PlacementCaptureIdentity
}

struct PlacementARView: View {
    var store: SurveyStore
    var onContinue: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var step: WalkStep
    /// Manual tap for whichever of the meter or panel the scan missed.
    @State private var manualMark: PlacementTarget?
    @State private var yawRadians: Float
    @State private var scene: PlacementSceneSnapshot
    /// Updated many times a second while measuring. Kept off this view so those updates do not cancel button taps.
    @State private var liveReadout = LiveDistanceReadout()
    @State private var screenshotToken: UUID? = nil
    /// Set while a save waits for its screenshot. Cleared when it advances, so the view can save again after Back.
    @State private var pendingSave: PlacementSaveRequest? = nil
    /// A successful handoff keeps its durable packet even if AR updates before disappearance.
    @State private var departingAfterCapture = false
    @State private var statusMessage: String? = nil
    @State private var trackingMessage: String? = nil
    @State private var equipmentMessage: String? = nil
    @State private var isVisible = false
    @State private var hasStartedAR: Bool
    @State private var coachingIsActive = false
    /// When false, the AR view stays minimal (chip picker + Measure button). Flip true to reveal the guided walkthrough.
    @State private var measureMode: Bool = true

    init(store: SurveyStore, onContinue: @escaping () -> Void) {
        self.store = store
        self.onContinue = onContinue
        let existing = store.placementController
        let snapshot = existing?.scene ?? PlacementSceneSnapshot()
        let progressed = WalkStep.firstIncomplete(in: snapshot, gasNotVisible: store.gasMeterNotVisible)
        let initialStep = (existing?.hasChosenWalkStep == true) ? (existing?.walkStep ?? progressed) : progressed
        _scene = State(initialValue: snapshot)
        _step = State(initialValue: initialStep)
        _yawRadians = State(initialValue: existing?.yawRadians ?? 0)
        // Skip the preflight screen. iOS shows the camera permission modal on first ARKit run if needed.
        _hasStartedAR = State(initialValue: true)
    }

    private var isSaving: Bool { pendingSave != nil }

    private var arSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    private var liveAssessment: SurveyAssessment {
        // A new/paused live scan must not display an older capture's passing assessment.
        store.assessment(applying: scene)
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
            departingAfterCapture = false
            isVisible = true
            let controller = store.requirePlacementController()
            controller.resume()
            scene = controller.scene
            yawRadians = controller.yawRadians
        }
        .onDisappear {
            isVisible = false
            cancelPendingSave()
            if !departingAfterCapture { commitLiveScene() }
            store.placementController?.pauseIfIdle()
        }
        .onChange(of: scenePhase) { _, phase in
            guard isVisible, arSupported, hasStartedAR else { return }
            if phase == .active {
                store.placementController?.resume()
            } else {
                cancelPendingSave()
                store.placementController?.pauseIfIdle()
            }
        }
        .onChange(of: store.session.selectedBatteryModelId) { _, _ in
            departingAfterCapture = false
            cancelPendingSave()
        }
        .onChange(of: step) { _, new in
            departingAfterCapture = false
            store.placementController?.walkStep = new
            store.placementController?.hasChosenWalkStep = true
            statusMessage = nil
            liveReadout.text = nil
            if new != .scan {
                manualMark = nil
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
                        measurementMode: false,
                        measurementKind: .batteryToMeter,
                        editingWorkingSpace: false,
                        inputEnabled: inputEnabled,
                        aimEnabled: aimEnabled,
                        tapEnabled: tapEnabled,
                        scanning: isScanning,
                        yawRadians: yawRadians,
                        tone: tone,
                        screenshotToken: screenshotToken,
                        onSceneChange: acceptScene,
                        onYawChange: {
                            departingAfterCapture = false
                            yawRadians = $0
                        },
                        onLiveFeet: acceptLiveFeet,
                        onScreenshot: handleScreenshot,
                        onFailure: { statusMessage = $0 },
                        onTrackingStatus: { trackingMessage = $0 },
                        onEquipmentStatus: { equipmentMessage = $0 },
                        onCoachingActiveChange: { coachingIsActive = $0 }
                    )
                }
                if !coachingIsActive {
                    VStack(spacing: 8) {
                        modelChipPicker
                        if measureMode {
                            HStack {
                                progressHeader
                                    .allowsHitTesting(false)
                                Spacer()
                                Button("Back") { measureMode = false }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            if !coachingIsActive {
                if measureMode {
                    bottomBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                } else {
                    idleBottomBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private var modelChipPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BatteryCatalog.all) { model in
                    let selected = store.session.selectedBatteryModelId == model.id
                    Button {
                        departingAfterCapture = false
                        cancelPendingSave()
                        store.setSelectedBatteryModel(model.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                                .font(.caption.weight(.semibold))
                            Text("\(formatInch(model.widthInches))×\(formatInch(model.heightInches))×\(formatInch(model.depthInches)) in")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(selected ? Color.primary.opacity(0.15) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            Capsule().strokeBorder(selected ? Color.primary : Color.primary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func formatInch(_ inches: Float) -> String {
        String(format: inches.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", inches)
    }

    private var idleBottomBar: some View {
        HStack(spacing: 12) {
            Button {
                measureMode = true
            } label: {
                Label("Measure", systemImage: "ruler")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button {
                saveAndReview()
            } label: {
                Text("Done")
                    .frame(maxWidth: 100)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var preflightScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "arkit")
                .font(.system(size: 48))
                .accessibilityHidden(true)
            Text("Preview the battery outside")
                .font(.title.bold())
            VStack(alignment: .leading, spacing: 14) {
                Label("Point the camera at the meter and the breaker panel.", systemImage: "viewfinder")
                Label("Mark the gas meter, or say there isn’t one.", systemImage: "flame")
                Label("Place the battery last and see if it fits.", systemImage: "plus.circle")
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
            if showsFitReadout {
                Text(distanceLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(meshFitLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let trackingMessage {
                Text(trackingMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            } else if let equipmentMessage {
                Text(equipmentMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
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
        case .scan where manualMark == nil:
            scanControls
        case .finish:
            finishControls
        default:
            aimControls
        }
    }

    private var aimControls: some View {
        VStack(spacing: 8) {
            HStack {
                if step != .scan || manualMark != nil {
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

    private var scanControls: some View {
        VStack(spacing: 8) {
            Button("Next", action: goForward)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            if let missedTarget {
                Button(missedTarget == .meter ? "Mark meter yourself" : "Mark panel yourself") {
                    manualMark = missedTarget
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if meterIsMarked || panelIsMarked {
                HStack(spacing: 8) {
                    if meterIsMarked {
                        Button("Clear meter") { store.placementController?.clearEquipmentLock(.meter) }
                            .buttonStyle(.bordered)
                    }
                    if panelIsMarked {
                        Button("Clear panel") { store.placementController?.clearEquipmentLock(.panel) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
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
            .disabled(isSaving || scene.batteryPosition == nil || !scene.trackingIsNormal)
            Button("Skip for now") {
                cancelPendingSave()
                commitLiveScene()
                onContinue()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button("Back", action: goBack)
                .buttonStyle(.bordered)
                .controlSize(.large)
            Text("This is a preliminary survey, not an install measurement. Green only when every required check has measured evidence and passes. Teal means a pass relied on an attestation, not a measurement.")
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
            set: {
                departingAfterCapture = false
                store.setFootprintClearAttested($0)
            }
        )
    }

    private var transferSwitchAttestBinding: Binding<Bool> {
        Binding(
            get: { store.session.placement.transferSwitchSpaceAttested == true },
            set: {
                departingAfterCapture = false
                store.setTransferSwitchSpaceAttested($0)
            }
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
        [.scan, .gas, .battery, .finish]
    }

    private var showsFitReadout: Bool {
        scene.batteryPosition != nil && (step == .battery || step == .finish)
    }

    private var meshFitLine: String {
        let measured = store.measurements(for: scene)
        return [
            fitWord("Pad", measured.footprintIsClear),
            fitWord("Working space", measured.frontWorkingSpaceIsClear),
            fitWord("Transfer switch", measured.transferSwitchClearanceObserved)
        ].joined(separator: "  ·  ")
    }

    private func fitWord(_ name: String, _ value: Bool?) -> String {
        switch value {
        case true: "\(name) clear"
        case false: "\(name) blocked"
        case nil: "\(name) —"
        }
    }

    private var meterIsMarked: Bool {
        scene.meterPosition != nil || scene.meterWallPosition != nil
    }

    private var panelIsMarked: Bool {
        scene.panelPosition != nil || scene.panelWallPosition != nil
    }

    /// The scan button reopens the old tap only for the target that never locked.
    private var missedTarget: PlacementTarget? {
        if !meterIsMarked { return .meter }
        if !panelIsMarked { return .panel }
        return nil
    }

    private var isScanning: Bool {
        step == .scan && manualMark == nil
    }

    private var progressIndex: Int {
        progressSteps.firstIndex(of: step) ?? 0
    }

    private var placementMode: PlacementTarget {
        if step == .scan, let manualMark { return manualMark }
        if step == .gas { return .gasMeter }
        return .battery
    }

    private var inputEnabled: Bool {
        step != .finish && !isSaving && !departingAfterCapture
    }

    /// Taps place a mark. The scan itself does not use the center dot.
    private var tapEnabled: Bool {
        switch step {
        case .scan: manualMark != nil
        case .gas, .battery: true
        case .finish: false
        }
    }

    /// Center dot stays up while the next action is “aim and tap +”.
    private var aimEnabled: Bool {
        switch step {
        case .scan:
            switch manualMark {
            case .meter: !meterIsMarked
            case .panel: !panelIsMarked
            case nil, .battery, .gasMeter: false
            }
        case .gas: scene.gasMeterPosition == nil
        case .battery: scene.batteryPosition == nil
        case .finish: false
        }
    }

    private var primaryIsAdvance: Bool {
        switch step {
        case .scan:
            switch manualMark {
            case .meter: meterIsMarked
            case .panel: panelIsMarked
            case nil, .battery, .gasMeter: false
            }
        case .gas: scene.gasMeterPosition != nil
        case .battery: scene.batteryPosition != nil
        case .finish: false
        }
    }

    private var canUndoPoint: Bool { false }

    private var secondaryTitle: String? {
        step == .gas ? "No gas meter" : nil
    }

    private var instruction: String {
        switch step {
        case .scan:
            if manualMark == .meter {
                return meterIsMarked
                    ? "Meter marked. Tap Next, or tap again to move it."
                    : "Point at the ground under the meter, then at the meter on the wall."
            }
            if manualMark == .panel {
                return panelIsMarked
                    ? "Panel marked. Tap Next, or tap again to move it."
                    : "Point at the ground under the breaker panel, then at the panel on the wall."
            }
            return scanInstruction
        case .gas:
            return scene.gasMeterPosition == nil
                ? "Point the dot at the gas meter, or say there isn’t one."
                : "Gas meter marked. Its distance is taken from this mark after you place the battery."
        case .battery:
            return scene.batteryPosition == nil
                ? "Point the dot at the ground, then tap +. Distances are measured from this spot."
                : "Drag to move the battery. Twist two fingers to turn it."
        case .finish:
            return "Save this placement for review."
        }
    }

    private var scanInstruction: String {
        switch (meterIsMarked, panelIsMarked) {
        case (false, false): "Point the camera at the electric meter, then the breaker panel."
        case (true, false): "Meter locked. Point at the breaker panel."
        case (false, true): "Panel locked. Point at the electric meter."
        case (true, true): "Meter and panel locked. Tap Next."
        }
    }

    /// Ignore queued snapshots superseded by a newer controller revision.
    private func acceptScene(_ snapshot: PlacementSceneSnapshot) {
        guard isVisible, let live = store.placementController?.scene,
              snapshot.scanID == live.scanID, snapshot.revision == live.revision,
              snapshot.batteryModelID == live.batteryModelID else { return }
        if let request = pendingSave, !matches(request.identity, snapshot) {
            cancelPendingSave()
            statusMessage = "The scan changed during capture. Hold steady and tap Save again."
        }
        guard snapshot != scene else { return }
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
        departingAfterCapture = false
        if primaryIsAdvance {
            goForward()
        } else {
            statusMessage = nil
            store.placementController?.commitAim()
        }
    }

    private func secondaryAction() {
        departingAfterCapture = false
        guard step == .gas else { return }
        store.setGasMeterNotVisible(true)
        store.placementController?.clearGasMarker()
        step = .battery
    }

    private func goForward() {
        switch step {
        case .scan:
            if manualMark != nil {
                manualMark = nil
                return
            }
            step = .gas
        case .gas:
            if scene.gasMeterPosition != nil {
                store.setGasMeterNotVisible(false)
            }
            step = .battery
        case .battery: step = .finish
        case .finish: break
        }
    }

    private func goBack() {
        departingAfterCapture = false
        cancelPendingSave()
        switch step {
        case .scan:
            manualMark = nil
        case .gas: step = .scan
        case .battery: step = .gas
        case .finish: step = .battery
        }
    }

    private func saveAndReview() {
        guard !isSaving, isVisible, scenePhase == .active,
              let controller = store.placementController else { return }
        departingAfterCapture = false
        let snapshot = controller.snapshotForCapture()
        guard snapshot.batteryPosition != nil, snapshot.trackingIsNormal,
              snapshot.batteryModelID == store.session.selectedBatteryModelId else {
            statusMessage = "Wait for tracking and place the battery on a detected surface before saving."
            return
        }
        let token = UUID()
        let identity = PlacementCaptureIdentity(
            captureID: token, scanID: snapshot.scanID, revision: snapshot.revision,
            batteryModelID: snapshot.batteryModelID, capturedAt: Date()
        )
        pendingSave = PlacementSaveRequest(snapshot: snapshot, identity: identity)
        screenshotToken = token
        statusMessage = nil
        Task {
            try? await Task.sleep(for: .seconds(5))
            failScreenshot(token)
        }
    }

    /// Keeps review and export in step with the scene when the user leaves without Save.
    private func commitLiveScene() {
        guard let controller = store.placementController else { return }
        let live = controller.snapshotForCapture()
        store.commitPlacement(live)
    }

    private func matches(_ identity: PlacementCaptureIdentity, _ snapshot: PlacementSceneSnapshot) -> Bool {
        snapshot.trackingIsNormal && identity.scanID == snapshot.scanID
            && identity.revision == snapshot.revision && identity.batteryModelID == snapshot.batteryModelID
    }

    private func handleScreenshot(_ token: UUID, _ image: UIImage?) {
        guard let request = pendingSave, token == request.identity.captureID else { return }
        guard isVisible, scenePhase == .active, let image,
              let controller = store.placementController,
              matches(request.identity, controller.snapshotForCapture()),
              request.identity.batteryModelID == store.session.selectedBatteryModelId else {
            failScreenshot(token)
            return
        }
        guard store.commitPlacementCapture(request.snapshot, image: image, identity: request.identity) else {
            cancelPendingSave()
            statusMessage = "Placement could not be saved on this device. Tap Save to retry."
            return
        }
        departingAfterCapture = true
        cancelPendingSave()
        onContinue()
    }

    private func failScreenshot(_ token: UUID?) {
        guard let token, token == pendingSave?.identity.captureID else { return }
        cancelPendingSave()
        statusMessage = "Placement screenshot did not capture an unchanged scan. Tap Save again."
    }

    private func cancelPendingSave() {
        pendingSave = nil
        screenshotToken = nil
        store.placementController?.cancelScreenshot()
    }
}

@MainActor
@Observable
private final class LiveDistanceReadout {
    var text: String?
}

private struct EquipmentLock {
    struct Sample {
        var point: SIMD3<Float>
        var normal: SIMD3<Float>
        var normalIsMeasured: Bool = true
    }

    var samples: [Sample] = []
    var locked = false

    /// Three hits whose positions all sit within about 15 cm become one lock at their center.
    mutating func absorb(_ sample: Sample) -> Sample? {
        guard !locked else { return nil }
        if samples.contains(where: { simd_distance($0.point, sample.point) > 0.15 }) {
            samples = [sample]
            return nil
        }
        samples.append(sample)
        guard samples.count >= 3 else { return nil }
        locked = true
        let count = Float(samples.count)
        let point = samples.reduce(SIMD3<Float>.zero) { $0 + $1.point } / count
        let normalSum = samples.reduce(SIMD3<Float>.zero) { $0 + $1.normal }
        let length = simd_length(normalSum)
        let normal = length > 0.001 ? normalSum / length : sample.normal
        return Sample(point: point, normal: normal, normalIsMeasured: samples.allSatisfy(\.normalIsMeasured))
    }
}

private final class EquipmentBoxOverlay: UIView {
    struct Item {
        var rect: CGRect
        var color: UIColor
        var title: String
    }

    var items: [Item] = [] {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        for item in items {
            let path = UIBezierPath(roundedRect: item.rect, cornerRadius: 8)
            item.color.setStroke()
            path.lineWidth = 3
            path.stroke()
            let text = item.title as NSString
            text.draw(
                at: CGPoint(x: item.rect.minX + 6, y: max(item.rect.minY - 18, 4)),
                withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 13),
                    .foregroundColor: item.color
                ]
            )
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
    var scanning: Bool
    var yawRadians: Float
    var tone: PlacementTone
    var screenshotToken: UUID?
    var onSceneChange: (PlacementSceneSnapshot) -> Void
    var onYawChange: (Float) -> Void
    var onLiveFeet: (Double?) -> Void
    var onScreenshot: @MainActor (UUID, UIImage?) -> Void
    var onFailure: (String) -> Void
    var onTrackingStatus: (String?) -> Void
    var onEquipmentStatus: (String?) -> Void
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
            scanning: scanning,
            yawRadians: yawRadians,
            tone: tone,
            screenshotToken: screenshotToken,
            onSceneChange: onSceneChange,
            onYawChange: onYawChange,
            onLiveFeet: onLiveFeet,
            onScreenshot: onScreenshot,
            onFailure: onFailure,
            onTrackingStatus: onTrackingStatus,
            onEquipmentStatus: onEquipmentStatus,
            onCoachingActiveChange: onCoachingActiveChange
        )
    }
}

private struct MeshDrawBuffers: Sendable {
    var positions: [SIMD3<Float>]
    var wall: [UInt32]
    var floor: [UInt32]
    var other: [UInt32]
}

private struct ClassifiedMeshUpdate: Sendable {
    var id: UUID
    var samples: [ClassifiedMeshSample]
    var draw: MeshDrawBuffers?
}

/// Owns the AR session for one survey. The placement screen can disappear without dropping marks,
/// because a new session would not share the old world coordinates.
@MainActor
final class PlacementSceneController: NSObject, ARSessionDelegate, ARCoachingOverlayViewDelegate {
    let arView = ARView(frame: .zero)
    private(set) var scene = PlacementSceneSnapshot()
    var yawRadians: Float = 0
    fileprivate var walkStep: WalkStep = .scan
    fileprivate var hasChosenWalkStep = false

    private var mode: PlacementTarget = .battery
    private var measurementMode = false
    private var measurementKind: PlacementMeasurementKind = .batteryToMeter
    private var editingWorkingSpace = false
    private var inputEnabled = true
    private var aimEnabled = false
    private var tapEnabled = false
    private var scanningEquipment = false
    private var coachingActive = false
    private var configuration: ARWorldTrackingConfiguration?
    private var isPrepared = false
    private var screenshotInFlight: UUID?
    private var isRunning = false
    private var lastEmittedSnapshot: PlacementSceneSnapshot?
    /// Guards queued AR delegate work across pause, interruption, and resume.
    private let callbackEpoch = OSAllocatedUnfairLock<UUID>(initialState: UUID())
    private var onSceneChange: ((PlacementSceneSnapshot) -> Void)?
    private var onYawChange: ((Float) -> Void)?
    private var onScreenshot: (@MainActor (UUID, UIImage?) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var onTrackingStatus: ((String?) -> Void)?
    private var onEquipmentStatus: ((String?) -> Void)?
    private var lastEquipmentMessage: String?
    private var lastEquipmentGeneration: UInt64?
    private var onCoachingActiveChange: ((Bool) -> Void)?
    private var onLiveFeet: ((Double?) -> Void)?
    private var root: AnchorEntity?
        var measurementMarkers: [ModelEntity] = []
        var measurementEndpoints: [MeasurementEndpoint] = []
        var measurementLine: ModelEntity?
        var draggedMeasurementIndex: Int?
        var measurementIsConfirmed = false
        var workingSpaceOverlay: ModelEntity?
        private var workingSpaceIsDerived = false
        var batteryRig: Entity?
        var batteryBody: ModelEntity?
        var batteryFaceMark: ModelEntity?
        var footprintPad: ModelEntity?
        var activeModel: BatteryModel = BatteryCatalog.baseCore
        /// Turned true after the first auto-place attempt succeeds or is decisively skipped so we do not spam.
        var didAttemptAutoPlace = false
        var meterMarker: ModelEntity?
        var meterWallMarker: ModelEntity?
        var meterWallHit: (position: SIMD3<Float>, normal: SIMD3<Float>)?
        private var meterWallNormalIsMeasured = false
        var panelMarker: ModelEntity?
        var panelWallMarker: ModelEntity?
        var panelWallHit: (position: SIMD3<Float>, normal: SIMD3<Float>)?
        private var panelWallNormalIsMeasured = false
        var gasMarker: ModelEntity?
        var planes: [UUID: PlaneSample] = [:]
        /// Classified face samples, keyed by ARMeshAnchor identifier so removals stay cheap.
        var meshSamples: [UUID: [ClassifiedMeshSample]] = [:]
        var meshVisuals: [UUID: AnchorEntity] = [:]
        fileprivate var pendingMeshDraws: [UUID: MeshDrawBuffers] = [:]
        var lastMeshDraw = Date.distantPast
        var transferBox: ModelEntity?
        var trackingBlockedMessage: String? = "Tracking is starting. Hold still a moment before placing a point."
        private let trackingNotice = OSAllocatedUnfairLock<String?>(initialState: "Tracking is starting. Hold still a moment before placing a point.")
        nonisolated let equipmentBridge = EquipmentScanBridge()
        private let boxOverlay = EquipmentBoxOverlay(frame: .zero)
        private var meterGroundPosition: SIMD3<Float>?
        private var panelGroundPosition: SIMD3<Float>?
        private var meterLock = EquipmentLock()
        private var panelLock = EquipmentLock()
        private var reportedScanLoadError = false
        let placementMeasurer = CorePlacementMeasurer()
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
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                configuration.sceneReconstruction = .meshWithClassification
                lidarMeshAvailable = true
                arView.environment.sceneUnderstanding.options.insert(.occlusion)
            } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                configuration.sceneReconstruction = .mesh
                arView.environment.sceneUnderstanding.options.insert(.occlusion)
            }
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                configuration.frameSemantics.insert(.smoothedSceneDepth)
            } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            self.configuration = configuration
            arView.session.delegate = self

            boxOverlay.frame = arView.bounds
            boxOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            arView.addSubview(boxOverlay)

            let coaching = ARCoachingOverlayView()
            coaching.session = arView.session
            coaching.goal = .tracking
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
            scanning: Bool,
            yawRadians: Float,
            tone: PlacementTone,
            screenshotToken: UUID?,
            onSceneChange: @escaping (PlacementSceneSnapshot) -> Void,
            onYawChange: @escaping (Float) -> Void,
            onLiveFeet: @escaping (Double?) -> Void,
            onScreenshot: @escaping @MainActor (UUID, UIImage?) -> Void,
            onFailure: @escaping (String) -> Void,
            onTrackingStatus: @escaping (String?) -> Void,
            onEquipmentStatus: @escaping (String?) -> Void,
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
            let startedScanning = scanning && !scanningEquipment
            scanningEquipment = scanning
            equipmentBridge.setEnabled(isRunning && scene.trackingIsNormal && scanning && !coachingActive)
            if !scanning {
                boxOverlay.items = []
            }
            self.onSceneChange = onSceneChange
            self.onYawChange = onYawChange
            self.onLiveFeet = onLiveFeet
            self.onScreenshot = onScreenshot
            self.onFailure = onFailure
            self.onTrackingStatus = onTrackingStatus
            self.onEquipmentStatus = onEquipmentStatus
            self.onCoachingActiveChange = onCoachingActiveChange
            if startedScanning, !reportedScanLoadError, let loadError = equipmentBridge.detector.loadError {
                reportedScanLoadError = true
                self.onFailure?("Equipment scan isn’t available (\(loadError)). Mark the meter and panel yourself.")
            }
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
                takeScreenshot(token: screenshotToken)
            } else if screenshotToken == nil {
                cancelScreenshot()
            }
        }

        func resume() {
            prepareIfNeeded()
            guard !isRunning else { return }
            guard let configuration else { return }
            callbackEpoch.withLock { $0 = UUID() }
            isRunning = true
            setTrackingMessage("Tracking is starting. Hold still a moment before placing a point.")
            arView.session.run(configuration, options: [])
            startAiming()
        }

        func pauseIfIdle() {
            guard isPrepared else { return }
            equipmentBridge.trackingInterrupted()
            cancelScreenshot()
            isRunning = false
            callbackEpoch.withLock { $0 = UUID() }
            equipmentBridge.setEnabled(false)
            setTrackingMessage("Tracking is paused. Resume the scan before saving.")
            // Any in-flight rotation gesture is invalidated by pausing the session.
            rotationStartYaw = appliedYaw
            stopAiming()
            arView.session.pause()
        }

        func stop() {
            pauseIfIdle()
            stopAiming()
            onSceneChange = nil
            onYawChange = nil
            onScreenshot = nil
            onFailure = nil
            onTrackingStatus = nil
            onEquipmentStatus = nil
            onLiveFeet = nil
            onCoachingActiveChange = nil
            cancelScreenshot()
            // This controller must not reuse world coordinates after being stopped.
            scene.scanID = UUID()
            scene.trackingIsNormal = false
            if isPrepared {
                arView.session.pause()
                arView.session.delegate = nil
            }
            arView.removeFromSuperview()
        }

        nonisolated func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
            let epoch = callbackEpoch.withLock { $0 }
            Task { @MainActor in
                guard self.isRunning, self.callbackEpoch.withLock({ $0 }) == epoch else { return }
                self.coachingActive = true
                self.aimDot.isHidden = true
                self.equipmentBridge.setEnabled(false)
                self.onCoachingActiveChange?(true)
            }
        }

        nonisolated func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
            let epoch = callbackEpoch.withLock { $0 }
            Task { @MainActor in
                guard self.isRunning, self.callbackEpoch.withLock({ $0 }) == epoch else { return }
                self.coachingActive = false
                self.equipmentBridge.setEnabled(self.scanningEquipment && self.scene.trackingIsNormal)
                self.onCoachingActiveChange?(false)
            }
        }

        nonisolated func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
            equipmentBridge.trackingInterrupted()
            // Do not reset world tracking underneath existing evidence.
            let epoch = callbackEpoch.withLock { $0 }
            Task { @MainActor in
                guard self.callbackEpoch.withLock({ $0 }) == epoch else { return }
                self.pauseIfIdle()
                self.onFailure?("Tracking needs a new scan. Start a new survey rather than reuse these world positions.")
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, inputEnabled, tapEnabled else { return }
            guard trackingAllowsConfirmation(report: true) else { return }
            let point = gesture.location(in: arView)
            if measurementMode {
                if measurementKind == .batteryToWall { return }
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
            guard trackingAllowsConfirmation(report: false) else { return }
            if measurementMode {
                if measurementKind == .batteryToWall { return }
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
            guard inputEnabled, trackingAllowsConfirmation(report: false) else { return }
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

        func cancelScreenshot() {
            screenshotInFlight = nil
        }

        private func takeScreenshot(token: UUID) {
            let snapshot = snapshotForCapture()
            let epoch = callbackEpoch.withLock { $0 }
            let completion = onScreenshot
            guard isRunning, snapshot.trackingIsNormal else {
                Task { @MainActor in completion?(token, nil) }
                return
            }
            screenshotInFlight = token
            arView.snapshot(saveToHDR: false) { [weak self] image in
                Task { @MainActor in
                    guard let self, self.screenshotInFlight == token,
                          self.callbackEpoch.withLock({ $0 }) == epoch else { return }
                    let live = self.snapshotForCapture()
                    // Use the callback that originated the request, never a newly bound screen.
                    let valid = self.isRunning && live.trackingIsNormal
                        && live.scanID == snapshot.scanID && live.revision == snapshot.revision
                        && live.batteryModelID == snapshot.batteryModelID
                    self.screenshotInFlight = nil
                    completion?(token, valid ? image : nil)
                }
            }
        }

        /// Flush buffered geometry before requesting or accepting an image.
        func snapshotForCapture() -> PlacementSceneSnapshot {
            emit()
            return scene
        }

        func emit() {
            placeDerivedWorkingSpace()
            var snapshot = makeSnapshot()
            if let previous = lastEmittedSnapshot {
                let batteryChanged = previous.batteryPosition != snapshot.batteryPosition
                    || previous.batteryYawRadians != snapshot.batteryYawRadians
                    || previous.batteryModelID != snapshot.batteryModelID
                let meterChanged = previous.meterPosition != snapshot.meterPosition
                    || previous.meterWallPosition != snapshot.meterWallPosition
                    || previous.meterWallNormal != snapshot.meterWallNormal
                let gasChanged = previous.gasMeterPosition != snapshot.gasMeterPosition
                snapshot.confirmedMeasurements.removeAll {
                    (batteryChanged && $0.kind.startsAtBattery)
                        || (meterChanged && ($0.kind == .batteryToMeter || $0.kind == .meterHeight))
                        || (gasChanged && $0.kind == .batteryToGasMeter)
                }
                guard snapshot != previous else {
                    scene = snapshot
                    return
                }
                if previous.revision == UInt64.max {
                    snapshot.scanID = UUID()
                    snapshot.revision = 0
                } else {
                    snapshot.revision = previous.revision + 1
                }
            }
            scene = snapshot
            lastEmittedSnapshot = snapshot
            updateTransferBox(snapshot)
            let change = onSceneChange
            let epoch = callbackEpoch.withLock { $0 }
            let emittedSnapshot = snapshot
            Task { @MainActor [weak self] in
                guard let self, self.callbackEpoch.withLock({ $0 }) == epoch,
                      self.scene.scanID == emittedSnapshot.scanID,
                      self.scene.revision == emittedSnapshot.revision else { return }
                change?(emittedSnapshot)
            }
        }

        nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let epoch = callbackEpoch.withLock { $0 }
            equipmentBridge.consider(frame)
            let message = Self.trackingMessage(for: frame.camera.trackingState)
            let changed = trackingNotice.withLock { current -> Bool in
                guard current != message else { return false }
                current = message
                return true
            }
            guard changed else { return }
            Task { @MainActor in
                guard self.isRunning, self.callbackEpoch.withLock({ $0 }) == epoch,
                      self.trackingNotice.withLock({ $0 }) == message else { return }
                self.setTrackingMessage(message)
            }
        }

        private func setTrackingMessage(_ message: String?) {
            trackingNotice.withLock { $0 = message }
            trackingBlockedMessage = message
            if message != nil { cancelScreenshot() }
            scene.trackingIsNormal = isRunning && message == nil
            equipmentBridge.setEnabled(isRunning && message == nil && scanningEquipment && !coachingActive)
            onTrackingStatus?(message)
            emit()
        }

        nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            upsertPlanes(from: anchors)
            upsertMesh(from: anchors)
            maybeAutoPlace(from: anchors)
        }

        nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            upsertPlanes(from: anchors)
            upsertMesh(from: anchors)
            maybeAutoPlace(from: anchors)
        }

        private nonisolated func maybeAutoPlace(from anchors: [ARAnchor]) {
            let epoch = callbackEpoch.withLock { $0 }
            let hasHorizontal = anchors.contains { anchor in
                (anchor as? ARPlaneAnchor)?.alignment == .horizontal
            }
            guard hasHorizontal else { return }
            Task { @MainActor in
                guard self.isRunning, self.callbackEpoch.withLock({ $0 }) == epoch else { return }
                self.autoPlaceIfPossible()
            }
        }

        /// LiDAR mesh anchors update many times a second; skip the hop to the main actor when no wall changed.
        private nonisolated func upsertPlanes(from anchors: [ARAnchor]) {
            let epoch = callbackEpoch.withLock { $0 }
            let samples = Self.planeSamples(from: anchors)
            guard !samples.isEmpty else { return }
            Task { @MainActor in
                guard self.isRunning, self.callbackEpoch.withLock({ $0 }) == epoch else { return }
                self.upsert(samples)
            }
        }

        private nonisolated func upsertMesh(from anchors: [ARAnchor]) {
            let epoch = callbackEpoch.withLock { $0 }
            let samples = Self.classifiedMeshes(from: anchors)
            guard !samples.isEmpty else { return }
            Task { @MainActor in
                guard self.isRunning, self.callbackEpoch.withLock({ $0 }) == epoch else { return }
                self.upsertMesh(samples)
            }
        }

        nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            let epoch = callbackEpoch.withLock { $0 }
            let ids = anchors.map(\.identifier)
            Task { @MainActor in
                guard self.isRunning, self.callbackEpoch.withLock({ $0 }) == epoch else { return }
                for id in ids {
                    self.planes.removeValue(forKey: id)
                    self.meshSamples.removeValue(forKey: id)
                    self.pendingMeshDraws.removeValue(forKey: id)
                    self.meshVisuals[id]?.removeFromParent()
                    self.meshVisuals.removeValue(forKey: id)
                }
                self.emit()
            }
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            equipmentBridge.trackingInterrupted()
            let message = error.localizedDescription
            let epoch = callbackEpoch.withLock { $0 }
            Task { @MainActor in
                guard self.callbackEpoch.withLock({ $0 }) == epoch else { return }
                self.pauseIfIdle()
                self.onFailure?(message)
            }
        }

        nonisolated func sessionWasInterrupted(_ session: ARSession) {
            equipmentBridge.trackingInterrupted()
            let epoch = callbackEpoch.withLock { $0 }
            Task { @MainActor in
                guard self.callbackEpoch.withLock({ $0 }) == epoch else { return }
                self.pauseIfIdle()
            }
        }

        nonisolated func sessionInterruptionEnded(_ session: ARSession) {
            // The visible view's lifecycle resumes the session. Never auto-resume a departed screen.
            let epoch = callbackEpoch.withLock { $0 }
            Task { @MainActor in
                guard self.callbackEpoch.withLock({ $0 }) == epoch else { return }
                self.onFailure?("The scan was interrupted. Return to placement to resume tracking.")
            }
        }

        private func upsert(_ samples: [PlaneSample]) {
            for sample in samples {
                planes[sample.id] = sample
            }
            emitPlanesIfNeeded()
        }

        private func upsertMesh(_ updates: [ClassifiedMeshUpdate]) {
            for update in updates {
                meshSamples[update.id] = update.samples
                if let draw = update.draw {
                    pendingMeshDraws[update.id] = draw
                }
            }
            let now = Date()
            if now.timeIntervalSince(lastMeshDraw) > 0.4, !pendingMeshDraws.isEmpty {
                lastMeshDraw = now
                let pending = pendingMeshDraws
                pendingMeshDraws.removeAll()
                for (id, draw) in pending {
                    installMeshDraw(id: id, draw: draw)
                }
            }
            emitPlanesIfNeeded()
        }

        private func emitPlanesIfNeeded() {
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
                buildBatteryRig()
            }
            batteryRig?.position = position
            applyYaw()
        }

        /// Rebuilds the battery entity from `activeModel`. Called on first placement and again when the user swaps models.
        private func buildBatteryRig() {
            let rig = batteryRig ?? Entity()
            if batteryRig == nil {
                root?.addChild(rig)
                batteryRig = rig
            } else {
                // Drop the old sub-entities so the mesh comes out at the new size.
                footprintPad?.removeFromParent()
                batteryBody?.removeFromParent()
                batteryFaceMark?.removeFromParent()
            }

            let padMesh = MeshResource.generateBox(
                width: BatteryGeometry.footprintMeters,
                height: 0.012,
                depth: BatteryGeometry.footprintMeters
            )
            let pad = ModelEntity(mesh: padMesh, materials: [UnlitMaterial(color: UIColor.systemOrange.withAlphaComponent(0.35))])
            pad.position.y = 0.006

            let bodyMesh = MeshResource.generateBox(
                width: activeModel.widthMeters,
                height: activeModel.heightMeters,
                depth: activeModel.depthMeters
            )
            let body = ModelEntity(mesh: bodyMesh, materials: [SimpleMaterial(color: .systemOrange, isMetallic: false)])
            body.position.y = 0.012 + activeModel.heightMeters / 2

            let markMesh = MeshResource.generateBox(width: 0.08, height: 0.08, depth: 0.02)
            let mark = ModelEntity(mesh: markMesh, materials: [UnlitMaterial(color: .darkGray)])
            mark.position = SIMD3(
                0,
                activeModel.heightMeters * 0.72,
                activeModel.depthMeters / 2 + 0.01
            )

            rig.addChild(pad)
            rig.addChild(body)
            rig.addChild(mark)
            footprintPad = pad
            batteryBody = body
            batteryFaceMark = mark
            applyTone()
        }

        func setActiveModel(_ model: BatteryModel) {
            guard model != activeModel else { return }
            cancelScreenshot()
            activeModel = model
            if batteryRig != nil {
                buildBatteryRig()
                applyYaw()
            }
            emit()
        }

        /// Automatic placement requires a detected horizontal plane, never a camera-relative guess.
        func autoPlaceIfPossible() {
            guard !didAttemptAutoPlace, batteryRig == nil else { return }
            guard trackingAllowsConfirmation(report: false) else { return }
            let viewCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            guard let placement = groundPosition(in: arView, at: viewCenter) else { return }
            didAttemptAutoPlace = true
            placeBattery(at: placement)
            emit()
        }

        private func placeMarker(kind: PlacementTarget, at position: SIMD3<Float>) {
            if kind == .meter { meterGroundPosition = position }
            if kind == .panel { panelGroundPosition = position }
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
            case .meter:
                meterWallHit = hit
                meterWallNormalIsMeasured = true
                meterGroundPosition = groundUnder(hit.position, normal: hit.normal)
                meterMarker?.removeFromParent()
                meterMarker = nil
                meterLock.locked = true
            case .panel:
                panelWallHit = hit
                panelWallNormalIsMeasured = true
                panelGroundPosition = groundUnder(hit.position, normal: hit.normal)
                panelMarker?.removeFromParent()
                panelMarker = nil
                panelLock.locked = true
            default: break
            }
        }

        func commitAim() {
            guard inputEnabled else { return }
            guard trackingAllowsConfirmation(report: true) else { return }
            if measurementMode, measurementKind == .batteryToWall {
                confirmAutomaticWall()
                return
            }
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
            let interface = arView.window?.windowScene?.interfaceOrientation ?? .portrait
            equipmentBridge.setViewport(arView.bounds.size, orientation: interface)
            updateEquipmentStatus()
            if let packet = equipmentBridge.takeLatest() {
                applyScan(packet)
            }
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
            if measurementMode, measurementKind == .batteryToWall {
                aimDot.isHidden = true
                updateAutomaticWallAim()
                return
            }
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
                start = BatteryGeometry.nearestBasePoint(origin: battery, yaw: appliedYaw, toward: position, model: activeModel)
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
            guard trackingAllowsConfirmation(report: true) else { return }
            guard measurementEndpoints.count == 2 else { return }
            guard !measurementEndpoints.contains(where: { $0.captureMethod == .estimatedPlane }) else {
                onFailure?("Scan a detected surface before confirming this measurement.")
                return
            }
            let distanceFeet = measurementKind.feet(
                from: measurementEndpoints[0].position.simd,
                to: measurementEndpoints[1].position.simd
            )
            let method: MeasurementCaptureMethod = .existingPlane
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

        func flipTransferSwitchSide() {
            scene.transferSwitchOnLeft.toggle()
            emit()
        }

        /// Yes/No answers are not measurements. Clearance comes from the mesh.

        private func addMeasurementPoint(at point: CGPoint) {
            guard trackingAllowsConfirmation(report: true) else { return }
            if measurementKind == .batteryToWall { return }
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
            let point = BatteryGeometry.nearestBasePoint(origin: battery, yaw: appliedYaw, toward: target.position.simd, model: activeModel)
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
            return nil
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
            guard let hit else { return nil }
            let column = hit.worldTransform.columns.3
            return SIMD3(column.x, column.y, column.z)
        }

        func clearEquipmentLock(_ kind: PlacementTarget) {
            switch kind {
            case .meter:
                meterLock = EquipmentLock()
                meterWallHit = nil
                meterWallNormalIsMeasured = false
                meterGroundPosition = nil
                meterMarker?.removeFromParent()
                meterMarker = nil
                meterWallMarker?.removeFromParent()
                meterWallMarker = nil
                scene.meterPosition = nil
                scene.meterWallPosition = nil
                scene.meterWallNormal = nil
            case .panel:
                panelLock = EquipmentLock()
                panelWallHit = nil
                panelWallNormalIsMeasured = false
                panelGroundPosition = nil
                panelMarker?.removeFromParent()
                panelMarker = nil
                panelWallMarker?.removeFromParent()
                panelWallMarker = nil
                scene.panelPosition = nil
                scene.panelWallPosition = nil
                scene.panelWallNormal = nil
            case .battery, .gasMeter:
                return
            }
            emit()
        }

        private func clearTransientEquipmentObservations() {
            boxOverlay.items = []
            if !meterLock.locked { meterLock = EquipmentLock() }
            if !panelLock.locked { panelLock = EquipmentLock() }
        }

        private func publishEquipmentStatus(_ message: String?) {
            guard message != lastEquipmentMessage else { return }
            lastEquipmentMessage = message
            onEquipmentStatus?(message)
        }

        private func updateEquipmentStatus() {
            guard scanningEquipment, isRunning, !coachingActive else {
                clearTransientEquipmentObservations()
                publishEquipmentStatus(nil)
                return
            }
            guard let observation = equipmentBridge.latestObservation else {
                clearTransientEquipmentObservations()
                publishEquipmentStatus(trackingBlockedMessage == nil
                    ? "Waiting for a fresh equipment scan. You can also mark equipment manually." : nil)
                return
            }
            if observation.generation != lastEquipmentGeneration {
                clearTransientEquipmentObservations()
                lastEquipmentGeneration = observation.generation
            }
            switch observation.status {
            case .success:
                publishEquipmentStatus(nil)
            case .noDetections:
                clearTransientEquipmentObservations()
                publishEquipmentStatus("No meter or panel detected in this frame. Reframe or mark it manually.")
            case .modelUnavailable, .inferenceFailed, .frameUnavailable:
                clearTransientEquipmentObservations()
                publishEquipmentStatus("Automatic equipment scanning is unavailable. Mark the meter and panel manually.")
            }
        }

        /// Boxes stay on the camera. A hit counts toward a lock only after it lands on a wall or, failing that, LiDAR depth.
        private func applyScan(_ packet: EquipmentScanFrame) {
            guard isRunning, scanningEquipment, !coachingActive, trackingAllowsConfirmation(report: false) else {
                boxOverlay.items = []
                return
            }
            var best: [EquipmentKind: EquipmentDetection] = [:]
            for detection in packet.detections where detection.confidence >= 0.25 {
                if let existing = best[detection.kind], existing.confidence >= detection.confidence { continue }
                best[detection.kind] = detection
            }
            // A lock requires a continuous run of usable observations, not unrelated
            // hits accumulated across a failure, absence or generation change.
            if best[.electricMeter] == nil, !meterLock.locked { meterLock = EquipmentLock() }
            if best[.breakerPanel] == nil, !panelLock.locked { panelLock = EquipmentLock() }
            var items: [EquipmentBoxOverlay.Item] = []
            var lockedSomething = false
            for detection in best.values {
                let rect = Self.viewRect(for: detection.boundingBox, in: packet)
                let landing = project(detection, in: packet)
                let alreadyLocked = detection.kind == .electricMeter ? meterLock.locked : panelLock.locked
                let color: UIColor
                let title: String
                if alreadyLocked {
                    color = .systemGreen
                    title = detection.kind.title
                } else if landing == nil {
                    color = .white
                    title = "\(detection.kind.title) · not on a wall"
                } else {
                    color = detection.kind == .electricMeter ? .systemBlue : .systemIndigo
                    title = detection.kind.title
                }
                if rect.width > 2, rect.height > 2, rect.origin.x.isFinite, rect.origin.y.isFinite {
                    items.append(EquipmentBoxOverlay.Item(rect: rect, color: color, title: title))
                }
                guard let landing, !alreadyLocked else { continue }
                let sample = EquipmentLock.Sample(
                    point: landing.position, normal: landing.normal, normalIsMeasured: landing.normalIsMeasured
                )
                let settled: EquipmentLock.Sample?
                switch detection.kind {
                case .electricMeter: settled = meterLock.absorb(sample)
                case .breakerPanel: settled = panelLock.absorb(sample)
                }
                if let settled {
                    lockEquipment(detection.kind, at: settled)
                    lockedSomething = true
                }
            }
            boxOverlay.items = items
            if lockedSomething {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                emit()
            }
        }

        private func project(_ detection: EquipmentDetection, in packet: EquipmentScanFrame) -> (position: SIMD3<Float>, normal: SIMD3<Float>, normalIsMeasured: Bool)? {
            let center = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
            let pixel = Self.bufferPixel(visionPoint: center, imageSize: packet.imageSize, orientation: packet.visionOrientation)
            let ray = Self.cameraRay(through: pixel, intrinsics: packet.intrinsics, transform: packet.cameraTransform)
            if let wall = wallHit(origin: ray.origin, direction: ray.direction) {
                return (wall.position, wall.normal, true)
            }
            guard let depth = depthHit(at: pixel, packet: packet, cameraOrigin: ray.origin) else { return nil }
            // Depth locates equipment; a camera-facing direction is not an observed wall normal.
            return (depth.position, depth.normal, false)
        }

        private func depthHit(
            at pixel: CGPoint,
            packet: EquipmentScanFrame,
            cameraOrigin: SIMD3<Float>
        ) -> (position: SIMD3<Float>, normal: SIMD3<Float>)? {
            guard let depth = packet.depth, depth.width > 0, depth.height > 0, packet.imageSize.width > 0 else { return nil }
            let column = min(max(Int((pixel.x / packet.imageSize.width * CGFloat(depth.width)).rounded()), 0), depth.width - 1)
            let row = min(max(Int((pixel.y / packet.imageSize.height * CGFloat(depth.height)).rounded()), 0), depth.height - 1)
            let index = row * depth.width + column
            guard depth.meters.indices.contains(index) else { return nil }
            if let confidence = depth.confidence, confidence.indices.contains(index), confidence[index] == 0 { return nil }
            let meters = depth.meters[index]
            guard meters > 0.15, meters < 8 else { return nil }
            let fx = packet.intrinsics.columns.0.x
            let fy = packet.intrinsics.columns.1.y
            let cx = packet.intrinsics.columns.2.x
            let cy = packet.intrinsics.columns.2.y
            let cameraPoint = SIMD3<Float>(
                (Float(pixel.x) - cx) * meters / fx,
                -((Float(pixel.y) - cy) * meters / fy),
                -meters
            )
            let world4 = packet.cameraTransform * SIMD4(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1)
            let world = SIMD3<Float>(world4.x, world4.y, world4.z)
            var toward = cameraOrigin - world
            toward.y = 0
            let length = simd_length(toward)
            guard length > 0.05 else { return nil }
            return (world, toward / length)
        }

        private func lockEquipment(_ kind: EquipmentKind, at sample: EquipmentLock.Sample) {
            let ground = groundUnder(sample.point, normal: sample.normal)
            switch kind {
            case .electricMeter:
                meterWallMarker?.removeFromParent()
                meterWallMarker = nil
                meterMarker?.removeFromParent()
                meterMarker = nil
                meterWallHit = (sample.point, sample.normal)
                meterWallNormalIsMeasured = sample.normalIsMeasured
                meterGroundPosition = ground
            case .breakerPanel:
                panelWallMarker?.removeFromParent()
                panelWallMarker = nil
                panelMarker?.removeFromParent()
                panelMarker = nil
                panelWallHit = (sample.point, sample.normal)
                panelWallNormalIsMeasured = sample.normalIsMeasured
                panelGroundPosition = ground
            }
        }

        /// Horizontal plane directly under the wall hit. X and Z stay on the hit so meter distance uses that face.
        private func groundUnder(_ point: SIMD3<Float>, normal: SIMD3<Float>) -> SIMD3<Float>? {
            let flat = SIMD3<Float>(normal.x, 0, normal.z)
            let length = simd_length(flat)
            let outward = length > 0.001 ? flat / length : SIMD3<Float>(0, 0, 1)
            let origin = point + outward * 0.12 + SIMD3<Float>(0, 0.05, 0)
            let query = ARRaycastQuery(origin: origin, direction: SIMD3(0, -1, 0), allowing: .existingPlaneGeometry, alignment: .horizontal)
            guard let hit = arView.session.raycast(query).first else { return nil }
            return SIMD3(point.x, hit.worldTransform.columns.3.y, point.z)
        }

        /// The 30 × 36 in slab sits in front of the locked meter (or panel) once the battery exists, so the mesh check has a volume.
        private func placeDerivedWorkingSpace() {
            guard batteryRig != nil else { return }
            let sample: (position: SIMD3<Float>, normal: SIMD3<Float>)?
            let groundY: Float
            if meterWallNormalIsMeasured, let meterWallHit, let meterGroundPosition {
                sample = meterWallHit
                groundY = meterGroundPosition.y
            } else if panelWallNormalIsMeasured, let panelWallHit, let panelGroundPosition {
                sample = panelWallHit
                groundY = panelGroundPosition.y
            } else {
                if workingSpaceIsDerived {
                    workingSpaceOverlay?.removeFromParent()
                    workingSpaceOverlay = nil
                    scene.workingSpacePosition = nil
                    workingSpaceIsDerived = false
                }
                return
            }
            guard let sample else { return }
            let flat = SIMD3<Float>(sample.normal.x, 0, sample.normal.z)
            let length = simd_length(flat)
            guard length > 0.001 else { return }
            let normal = flat / length
            let center = SIMD3<Float>(sample.position.x, groundY, sample.position.z)
                + normal * (BatteryGeometry.workingSpaceDepthMeters / 2)
            scene.workingSpaceYawRadians = atan2(normal.x, normal.z)
            placeWorkingSpace(at: center)
            workingSpaceIsDerived = true
        }

        private static func viewRect(for box: CGRect, in packet: EquipmentScanFrame) -> CGRect {
            let corners = [
                CGPoint(x: box.minX, y: box.minY),
                CGPoint(x: box.maxX, y: box.minY),
                CGPoint(x: box.minX, y: box.maxY),
                CGPoint(x: box.maxX, y: box.maxY)
            ]
            let transformed = corners.map { corner -> CGPoint in
                let buffer = bufferNormalized(visionPoint: corner, orientation: packet.visionOrientation)
                let viewNorm = buffer.applying(packet.displayTransform)
                return CGPoint(x: viewNorm.x * packet.viewSize.width, y: viewNorm.y * packet.viewSize.height)
            }
            let xs = transformed.map(\.x)
            let ys = transformed.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
                return .zero
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        /// Vision's upright point (origin lower left) back into the camera buffer (origin upper left).
        private static func bufferPixel(visionPoint: CGPoint, imageSize: CGSize, orientation: CGImagePropertyOrientation) -> CGPoint {
            let normalized = bufferNormalized(visionPoint: visionPoint, orientation: orientation)
            return CGPoint(x: normalized.x * imageSize.width, y: normalized.y * imageSize.height)
        }

        private static func bufferNormalized(visionPoint: CGPoint, orientation: CGImagePropertyOrientation) -> CGPoint {
            let x = visionPoint.x
            let y = visionPoint.y
            switch orientation {
            case .right: return CGPoint(x: 1 - y, y: 1 - x)
            case .left: return CGPoint(x: y, y: x)
            case .down: return CGPoint(x: 1 - x, y: y)
            default: return CGPoint(x: x, y: 1 - y)
            }
        }

        private static func cameraRay(
            through pixel: CGPoint,
            intrinsics: simd_float3x3,
            transform: simd_float4x4
        ) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
            let fx = intrinsics.columns.0.x
            let fy = intrinsics.columns.1.y
            let cx = intrinsics.columns.2.x
            let cy = intrinsics.columns.2.y
            let cameraDirection = simd_normalize(SIMD3<Float>(
                (Float(pixel.x) - cx) / fx,
                -(Float(pixel.y) - cy) / fy,
                -1
            ))
            let rotation = simd_float3x3(
                SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
            )
            let origin = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            return (origin, rotation * cameraDirection)
        }

        private func wallHit(in arView: ARView, at point: CGPoint) -> (position: SIMD3<Float>, normal: SIMD3<Float>)? {
            guard let hit = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .vertical).first else {
                return nil
            }
            return interpretWallHit(hit)
        }

        private func wallHit(origin: SIMD3<Float>, direction: SIMD3<Float>) -> (position: SIMD3<Float>, normal: SIMD3<Float>)? {
            let query = ARRaycastQuery(origin: origin, direction: direction, allowing: .existingPlaneGeometry, alignment: .vertical)
            guard let hit = arView.session.raycast(query).first else { return nil }
            return interpretWallHit(hit)
        }

        /// Real vertical planes only, same normal the wall tap uses. Estimated planes are not a meter.
        private func interpretWallHit(_ hit: ARRaycastResult) -> (position: SIMD3<Float>, normal: SIMD3<Float>)? {
            guard let planeAnchor = hit.anchor as? ARPlaneAnchor else { return nil }
            let column = hit.worldTransform.columns.3
            let position = SIMD3<Float>(column.x, column.y, column.z)
            let up = planeAnchor.transform * SIMD4<Float>(0, 1, 0, 0)
            var normal = SIMD3(up.x, up.y, up.z)
            let len = simd_length(normal)
            guard len.isFinite, len > 0.0001 else { return nil }
            normal /= len
            return (position, normal)
        }

        private func makeSnapshot() -> PlacementSceneSnapshot {
            var snapshot = scene
            snapshot.batteryModelID = activeModel.id
            snapshot.trackingIsNormal = trackingAllowsConfirmation(report: false)
            snapshot.lidarMeshAvailable = lidarMeshAvailable
            snapshot.verticalPlanes = planes.values.sorted { $0.id.uuidString < $1.id.uuidString }
            snapshot.batteryYawRadians = appliedYaw
            snapshot.batteryPosition = batteryRig.map { PlacementAnchor($0.position(relativeTo: nil)) }
            snapshot.meterPosition = meterGroundPosition.map { PlacementAnchor($0) }
            snapshot.meterWallPosition = meterWallHit.map { PlacementAnchor($0.position) }
            snapshot.meterWallNormal = meterWallNormalIsMeasured ? meterWallHit.map { PlacementAnchor($0.normal) } : nil
            snapshot.panelPosition = panelGroundPosition.map { PlacementAnchor($0) }
            snapshot.panelWallPosition = panelWallHit.map { PlacementAnchor($0.position) }
            snapshot.panelWallNormal = panelWallNormalIsMeasured ? panelWallHit.map { PlacementAnchor($0.normal) } : nil
            snapshot.gasMeterPosition = gasMarker.map { PlacementAnchor($0.position(relativeTo: nil)) }
            snapshot.draftMeasurementStart = measurementEndpoints.first
            snapshot.draftMeasurementEnd = measurementEndpoints.count > 1 ? measurementEndpoints[1] : nil
            snapshot.workingSpacePosition = workingSpaceOverlay.map {
                PlacementAnchor($0.position(relativeTo: nil) - SIMD3<Float>(0, 0.005, 0))
            }
            snapshot.classifiedMesh = classifiedSamplesNearPlacement()
            if let feet = placementMeasurer.wallClearance(in: snapshot)?.distanceFeet {
                snapshot.automaticWallClearanceFeet = (feet * 12).rounded() / 12
            } else {
                snapshot.automaticWallClearanceFeet = nil
            }
            return snapshot
        }

        private func trackingAllowsConfirmation(report: Bool) -> Bool {
            if isRunning, trackingBlockedMessage == nil,
               let frame = arView.session.currentFrame, case .normal = frame.camera.trackingState {
                return true
            }
            if report {
                onFailure?(trackingBlockedMessage ?? "Wait for normal tracking before placing or saving.")
            }
            return false
        }

        private nonisolated static func trackingMessage(for state: ARCamera.TrackingState) -> String? {
            switch state {
            case .normal:
                return nil
            case .notAvailable:
                return "Tracking isn’t available yet. Move the phone slowly until the scene settles."
            case .limited(let reason):
                switch reason {
                case .initializing:
                    return "Tracking is starting. Hold still a moment before placing a point."
                case .excessiveMotion:
                    return "Tracking is limited by excessive motion. Slow down, then place the point."
                case .insufficientFeatures:
                    return "Tracking is limited by insufficient features. Aim at a surface with more detail."
                case .relocalizing:
                    return "Tracking is relocalizing. Hold the phone steady, then place the point."
                @unknown default:
                    return "Tracking is limited. Wait for a steadier view before placing a point."
                }
            }
        }

        private func confirmAutomaticWall() {
            guard trackingAllowsConfirmation(report: true) else { return }
            guard batteryRig != nil else {
                onFailure?("Place the battery first.")
                return
            }
            let probe = makeSnapshot()
            guard let hit = placementMeasurer.wallClearance(in: probe) else {
                onFailure?("Scan the wall")
                return
            }
            let confirmed = ConfirmedPlacementMeasurement(
                kind: .batteryToWall,
                start: MeasurementEndpoint(position: PlacementAnchor(hit.edge), captureMethod: hit.method),
                end: MeasurementEndpoint(position: PlacementAnchor(hit.wallPoint), captureMethod: hit.method),
                distanceFeet: hit.distanceFeet,
                captureMethod: hit.method,
                confirmedAt: Date()
            )
            scene.confirmedMeasurements.removeAll { $0.kind == .batteryToWall }
            scene.confirmedMeasurements.append(confirmed)
            measurementEndpoints = [confirmed.start, confirmed.end]
            measurementMarkers.forEach { $0.removeFromParent() }
            measurementMarkers.removeAll()
            for endpoint in measurementEndpoints {
                let marker = ModelEntity(
                    mesh: .generateSphere(radius: 0.025),
                    materials: [SimpleMaterial(color: .systemGreen, isMetallic: false)]
                )
                marker.position = endpoint.position.simd
                root?.addChild(marker)
                measurementMarkers.append(marker)
            }
            measurementIsConfirmed = true
            rebuildMeasurementLine()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            emit()
        }

        private func updateAutomaticWallAim() {
            guard batteryRig != nil else {
                reticle?.isEnabled = false
                hideLiveLine()
                publishLiveFeet(nil)
                return
            }
            let probe = makeSnapshot()
            guard let hit = placementMeasurer.wallClearance(in: probe) else {
                reticle?.isEnabled = false
                hideLiveLine()
                publishLiveFeet(nil)
                return
            }
            placeReticle(at: hit.wallPoint)
            updateLiveLine(from: hit.edge, to: hit.wallPoint)
            publishLiveFeet(hit.distanceFeet)
        }

        /// Samples near the battery, meter, panel, or working space. The long tape stays a raycast.
        private func classifiedSamplesNearPlacement() -> [ClassifiedMeshSample] {
            var origins: [SIMD3<Float>] = []
            if let batteryRig { origins.append(batteryRig.position(relativeTo: nil)) }
            if let meterWallHit { origins.append(meterWallHit.position) }
            if let panelWallHit { origins.append(panelWallHit.position) }
            if let workingSpaceOverlay { origins.append(workingSpaceOverlay.position(relativeTo: nil)) }
            guard !origins.isEmpty else { return [] }
            let limit: Float = 8 * 8
            var result: [ClassifiedMeshSample] = []
            for id in meshSamples.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let samples = meshSamples[id] else { continue }
                for sample in samples {
                    for origin in origins {
                        let dx = sample.point.x - origin.x
                        let dz = sample.point.z - origin.z
                        if dx * dx + dz * dz <= limit {
                            result.append(sample)
                            break
                        }
                    }
                }
            }
            return result
        }

        private func updateTransferBox(_ snapshot: PlacementSceneSnapshot) {
            let show = batteryRig != nil && (walkStep == .battery || walkStep == .finish)
            guard show, let box = placementMeasurer.transferSwitchBox(in: snapshot) else {
                transferBox?.isEnabled = false
                return
            }
            if transferBox == nil {
                let entity = ModelEntity(
                    mesh: .generateBox(width: 1, height: 1, depth: 1),
                    materials: [UnlitMaterial(color: UIColor.systemOrange.withAlphaComponent(0.35))]
                )
                entity.components.remove(CollisionComponent.self)
                root?.addChild(entity)
                transferBox = entity
            }
            guard let transferBox else { return }
            transferBox.isEnabled = true
            transferBox.scale = SIMD3(box.alongMeters, box.heightMeters, box.outMeters)
            transferBox.position = box.center
            var along = box.along
            let basis = simd_float3x3(columns: (along, box.up, box.normal))
            if simd_determinant(basis) < 0 { along = -along }
            transferBox.orientation = simd_quatf(simd_float3x3(columns: (along, box.up, box.normal)))
            let color: UIColor
            switch placementMeasurer.measure(snapshot).transferSwitchClearanceObserved {
            case true: color = .systemGreen
            case false: color = .systemRed
            case nil: color = .systemOrange
            }
            transferBox.model?.materials = [UnlitMaterial(color: color.withAlphaComponent(0.35))]
        }

        private func installMeshDraw(id: UUID, draw: MeshDrawBuffers) {
            let anchor: AnchorEntity
            if let existing = meshVisuals[id] {
                anchor = existing
                for child in Array(anchor.children) {
                    child.removeFromParent()
                }
            } else {
                let created = AnchorEntity(.anchor(identifier: id))
                arView.scene.addAnchor(created)
                meshVisuals[id] = created
                anchor = created
            }
            addMeshPart(draw.positions, draw.wall, .systemBlue, opacity: 0.34, to: anchor)
            addMeshPart(draw.positions, draw.floor, .systemGreen, opacity: 0.18, to: anchor)
            addMeshPart(draw.positions, draw.other, .systemOrange, opacity: 0.24, to: anchor)
        }

        private func addMeshPart(
            _ positions: [SIMD3<Float>],
            _ indices: [UInt32],
            _ color: UIColor,
            opacity: Float,
            to parent: Entity
        ) {
            guard indices.count >= 3, !positions.isEmpty else { return }
            var descriptor = MeshDescriptor(name: "classified-mesh")
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.primitives = .triangles(indices)
            guard let resource = try? MeshResource.generate(from: [descriptor]) else { return }
            var material = UnlitMaterial()
            material.color = .init(tint: color)
            material.blending = .transparent(opacity: .init(scale: opacity))
            let model = ModelEntity(mesh: resource, materials: [material])
            model.components.remove(CollisionComponent.self)
            parent.addChild(model)
        }

        /// One point per face, with its class, plus a faint double-sided mesh in anchor-local space.
        private nonisolated static func classifiedMeshes(from anchors: [ARAnchor]) -> [ClassifiedMeshUpdate] {
            anchors.compactMap { anchor in
                guard let mesh = anchor as? ARMeshAnchor else { return nil }
                return classifiedMesh(from: mesh)
            }
        }

        private nonisolated static func classifiedMesh(from mesh: ARMeshAnchor) -> ClassifiedMeshUpdate? {
            let geometry = mesh.geometry
            let vertices = geometry.vertices
            let faces = geometry.faces
            let vertexCount = vertices.count
            let faceCount = faces.count
            guard vertexCount > 0, faceCount > 0, faces.indexCountPerPrimitive >= 3 else { return nil }

            let vertexStride = vertices.stride
            let vertexBase = vertices.buffer.contents().advanced(by: vertices.offset)
            let floatSize = MemoryLayout<Float>.size
            func localVertex(_ index: Int) -> SIMD3<Float> {
                let pointer = vertexBase.advanced(by: index * vertexStride)
                return SIMD3(
                    pointer.load(as: Float.self),
                    pointer.advanced(by: floatSize).load(as: Float.self),
                    pointer.advanced(by: floatSize * 2).load(as: Float.self)
                )
            }
            func faceVertexIndex(_ index: Int) -> Int {
                let pointer = faces.buffer.contents().advanced(by: index * faces.bytesPerIndex)
                if faces.bytesPerIndex == 2 {
                    return Int(pointer.load(as: UInt16.self))
                }
                return Int(pointer.load(as: UInt32.self))
            }
            func surfaceClass(_ face: Int) -> MeshSurfaceClass {
                guard let source = geometry.classification, face < source.count else { return .other }
                let pointer = source.buffer.contents().advanced(by: source.offset + face * source.stride)
                switch ARMeshClassification(rawValue: Int(pointer.load(as: UInt8.self))) {
                case .floor: return .floor
                case .wall, .door, .window: return .wall
                case .ceiling: return .ceiling
                default: return .other
                }
            }

            let transform = mesh.transform
            var positions: [SIMD3<Float>] = []
            positions.reserveCapacity(vertexCount)
            for index in 0..<vertexCount {
                positions.append(localVertex(index))
            }

            var wall: [UInt32] = []
            var floor: [UInt32] = []
            var other: [UInt32] = []
            var samples: [ClassifiedMeshSample] = []
            let sampleStride = 2
            wall.reserveCapacity(faceCount)
            samples.reserveCapacity(faceCount / sampleStride + 1)

            for face in 0..<faceCount {
                let base = face * faces.indexCountPerPrimitive
                let i0 = faceVertexIndex(base)
                let i1 = faceVertexIndex(base + 1)
                let i2 = faceVertexIndex(base + 2)
                guard i0 < vertexCount, i1 < vertexCount, i2 < vertexCount else { continue }
                let label = surfaceClass(face)
                let tri: [UInt32] = [UInt32(i0), UInt32(i1), UInt32(i2), UInt32(i2), UInt32(i1), UInt32(i0)]
                switch label {
                case .wall: wall.append(contentsOf: tri)
                case .floor: floor.append(contentsOf: tri)
                case .ceiling, .other: other.append(contentsOf: tri)
                }
                // Unlabeled geometry is drawn, but it is not a clearance sample yet.
                guard geometry.classification != nil, face % sampleStride == 0 else { continue }
                let a = positions[i0]
                let b = positions[i1]
                let c = positions[i2]
                let centroid = (a + b + c) / 3
                let worldPoint = transform * SIMD4(centroid.x, centroid.y, centroid.z, 1)
                let normal = simd_cross(b - a, c - a)
                let worldNormal = transform * SIMD4(normal.x, normal.y, normal.z, 0)
                samples.append(ClassifiedMeshSample(
                    faceClass: label,
                    point: SIMD3(worldPoint.x, worldPoint.y, worldPoint.z),
                    normal: SIMD3(worldNormal.x, worldNormal.y, worldNormal.z)
                ))
            }

            return ClassifiedMeshUpdate(
                id: mesh.identifier,
                samples: samples,
                draw: MeshDrawBuffers(positions: positions, wall: wall, floor: floor, other: other)
            )
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
