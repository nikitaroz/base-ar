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
    @State private var pendingSave: UUID? = nil
    @State private var statusMessage: String? = nil
    @State private var trackingMessage: String? = nil
    @State private var isVisible = false
    @State private var hasStartedAR: Bool
    @State private var isWarmingUp: Bool
    @State private var warmingRotation: Double = 0
    @State private var savePulse = false
    @State private var coachingIsActive = false
    /// When false, the AR view stays minimal (chip picker + Measure button). Flip true to reveal the guided walkthrough.
    @State private var measureMode: Bool = false

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
        // Show a brief warming overlay the first time this view opens, so the ARKit/detector spin-up isn't a jarring black screen.
        _isWarmingUp = State(initialValue: existing == nil)
    }

    private var isSaving: Bool { pendingSave != nil }

    private var arSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    /// Confirmed placement wins. Until Confirm, the wall-side ghost is what the tone and feet read.
    private var guidedScene: PlacementSceneSnapshot {
        var preview = scene
        if preview.batteryPosition == nil, let suggested = preview.suggestedBatteryPosition {
            preview.batteryPosition = suggested
            preview.batteryYawRadians = preview.suggestedBatteryYawRadians
        }
        return preview
    }

    private var liveAssessment: SurveyAssessment {
        let preview = guidedScene
        if preview.hasPlacedContent {
            return store.assessment(applying: preview)
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
                    ZStack {
                        arScreen
                        if isWarmingUp {
                            warmingOverlay
                                .transition(.opacity)
                        }
                    }
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
            syncPlacementGuide()
            if isWarmingUp {
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.35)) {
                            isWarmingUp = false
                        }
                    }
                }
            }
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
        .onChange(of: step) { _, new in
            store.placementController?.hasChosenWalkStep = true
            statusMessage = nil
            liveReadout.text = nil
            if new != .scan {
                manualMark = nil
            }
            syncPlacementGuide()
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
                        onYawChange: { yawRadians = $0 },
                        onLiveFeet: acceptLiveFeet,
                        onScreenshot: handleScreenshot,
                        onFailure: { statusMessage = $0 },
                        onTrackingStatus: { trackingMessage = $0 },
                        onCoachingActiveChange: { coachingIsActive = $0 }
                    )
                }
                if !coachingIsActive, measureMode {
                    HStack {
                        progressHeader
                            .allowsHitTesting(false)
                        Spacer()
                        Button("Back") { measureMode = false }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .padding(.horizontal, 12)
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
                commitLiveScene()
                onContinue()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var warmingOverlay: some View {
        ZStack {
            Color(.systemBackground).opacity(0.9).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 4)
                        .frame(width: 64, height: 64)
                    Circle()
                        .trim(from: 0, to: 0.35)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(warmingRotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                                warmingRotation = 360
                            }
                        }
                    Image(systemName: "viewfinder")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                Text("Warming up the camera…")
                    .font(.subheadline.weight(.semibold))
                Text("Point at the meter once we're ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera warming up")
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
            Text("Step \(progressIndex + 1) of \(progressSteps.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            HStack(spacing: 4) {
                ForEach(progressSteps.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index <= progressIndex ? Color.accentColor : Color.primary.opacity(0.25))
                        .frame(width: index == progressIndex ? 20 : 10, height: 4)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Text(instruction)
                .font(.body)
                .multilineTextAlignment(.center)
            if let equipmentScanLine {
                Text(equipmentScanLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let liveText = liveReadout.text {
                Text(liveText)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
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
                Label(trackingMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange, in: Capsule())
            }
            if let statusMessage {
                Label(statusMessage, systemImage: "xmark.octagon.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red, in: Capsule())
            }
            stepControls
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                        Image(systemName: primarySymbol)
                            .font(.title2.weight(.semibold))
                            .frame(width: 68, height: 68)
                            .background(Color.primary, in: Circle())
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .accessibilityLabel(primaryTitle)
                    Text(primaryTitle)
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
            if step == .battery, scene.suggestedBatteryPosition != nil || scene.batteryPosition != nil {
                Button("Other side") { store.placementController?.flipBatterySide() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
    }

    private var scanControls: some View {
        VStack(spacing: 8) {
            if let missedTarget {
                Button(missedTarget == .meter ? "Lock meter" : "Lock panel") {
                    store.placementController?.commitHoldSample()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if missedTarget == nil {
                Button("Next", action: goForward)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button("Next", action: goForward)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
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
                        Button(role: .destructive) {
                            store.placementController?.clearEquipmentLock(.meter)
                        } label: {
                            Label("Clear meter", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                    if panelIsMarked {
                        Button(role: .destructive) {
                            store.placementController?.clearEquipmentLock(.panel)
                        } label: {
                            Label("Clear panel", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
            }
        }
    }

    private var finishControls: some View {
        let canSave = !isSaving && scene.batteryPosition != nil
        return VStack(spacing: 8) {
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
            .disabled(!canSave)
            .scaleEffect(canSave && savePulse ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatCount(2, autoreverses: true), value: savePulse)
            .onChange(of: canSave) { _, becameCan in
                guard becameCan else { return }
                savePulse.toggle()
            }
            Button("Skip for now") {
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
        let measured = store.measurements(for: guidedScene)
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
        guidedScene.batteryPosition != nil && (step == .battery || step == .finish)
    }

    private var meshFitLine: String {
        let measured = store.measurements(for: guidedScene)
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
        step != .finish
    }

    /// Taps place a mark. Battery placement is the wall spot, not a ground tap. The scan hold uses its own reticle.
    private var tapEnabled: Bool {
        switch step {
        case .scan: manualMark != nil
        case .gas: true
        case .battery, .finish: false
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
        case .battery, .finish: false
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
            if scene.batteryPosition != nil {
                return "Drag along the wall to slide the battery. Twist two fingers to turn it."
            }
            if scene.suggestedBatteryPosition != nil {
                return "Drag along the wall, or flip to the other side, then confirm."
            }
            return "Lock the meter on the wall first. The spot shows up here after the gas step."
        case .finish:
            return "Save this placement for review."
        }
    }

    private var scanInstruction: String {
        switch (meterIsMarked, panelIsMarked) {
        case (false, false): "Hold the dot steady on the electric meter."
        case (true, false): "Meter locked. Hold the dot steady on the breaker panel."
        case (false, true): "Panel locked. Hold the dot steady on the electric meter."
        case (true, true): "Meter and panel locked. Tap Next."
        }
    }

    private var equipmentScanLine: String? {
        guard step == .scan, meterIsMarked, panelIsMarked else { return nil }
        let measured = store.measurements(for: scene)
        let height = measured.meterHeightFeet.map { String(format: "Height %.1f ft", $0) } ?? "Height —"
        let span = horizontalSeparationFeet(
            scene.meterWallPosition ?? scene.meterPosition,
            scene.panelWallPosition ?? scene.panelPosition
        )
        let panel = span.map { String(format: "Meter to panel %.1f ft", $0) } ?? "Meter to panel —"
        return "\(height)  ·  \(panel)"
    }

    private func horizontalSeparationFeet(_ origin: PlacementAnchor?, _ target: PlacementAnchor?) -> Double? {
        guard let origin, let target else { return nil }
        let dx = Double(origin.x - target.x)
        let dz = Double(origin.z - target.z)
        return (dx * dx + dz * dz).squareRoot() / Double(BatteryGeometry.feetToMeters)
    }

    private var confirmsBatterySpot: Bool {
        step == .battery && scene.batteryPosition == nil && scene.suggestedBatteryPosition != nil
    }

    private var primaryTitle: String {
        if primaryIsAdvance { return "Next" }
        if confirmsBatterySpot { return "Confirm" }
        return "Place"
    }

    private var primarySymbol: String {
        if primaryIsAdvance || confirmsBatterySpot { return "checkmark" }
        return "plus"
    }

    private func syncPlacementGuide() {
        let gasResolved = scene.gasMeterPosition != nil || store.gasMeterNotVisible
        store.placementController?.syncGuide(step: step, gasResolved: step == .battery && gasResolved)
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
            goForward()
        } else if confirmsBatterySpot {
            statusMessage = nil
            store.placementController?.confirmBatterySpot()
        } else {
            statusMessage = nil
            store.placementController?.commitAim()
        }
    }

    private func secondaryAction() {
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
        switch step {
        case .scan:
            manualMark = nil
        case .gas: step = .scan
        case .battery: step = .gas
        case .finish: step = .battery
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

private struct EquipmentLock {
    struct Sample {
        var point: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    var samples: [Sample] = []
    var locked = false

    /// Five hits whose positions all sit within about 15 cm become one lock at their center.
    /// At four detections a second that is a bit over a second of agreement.
    mutating func absorb(_ sample: Sample) -> Sample? {
        guard !locked else { return nil }
        if samples.contains(where: { simd_distance($0.point, sample.point) > 0.15 }) {
            samples = [sample]
            return nil
        }
        samples.append(sample)
        guard samples.count >= 5 else { return nil }
        locked = true
        let count = Float(samples.count)
        let point = samples.reduce(SIMD3<Float>.zero) { $0 + $1.point } / count
        let normalSum = samples.reduce(SIMD3<Float>.zero) { $0 + $1.normal }
        let length = simd_length(normalSum)
        let normal = length > 0.001 ? normalSum / length : sample.normal
        return Sample(point: point, normal: normal)
    }
}

/// World-space square kept after YOLO drops the detection. Extent is a rough box, in meters.
private struct LockedEquipmentBox {
    var center: SIMD3<Float>
    var normal: SIMD3<Float>
    var extent: Float
    var kind: EquipmentKind
}

/// Battery center slides on a line parallel to the meter wall.
private struct BatterySlide {
    var origin: SIMD3<Float>
    var outward: SIMD3<Float>
    var axis: SIMD3<Float>
    var groundY: Float
    var along: Float
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
    var onScreenshot: (UIImage?) -> Void
    var onFailure: (String) -> Void
    var onTrackingStatus: (String?) -> Void
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
    var cloud: MeshPointCloudChunk
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
    private var screenshotInFlight = false
    private var pauseRequested = false
    private var onSceneChange: ((PlacementSceneSnapshot) -> Void)?
    private var onYawChange: ((Float) -> Void)?
    private var onScreenshot: ((UIImage?) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var onTrackingStatus: ((String?) -> Void)?
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
        var batteryFaceMark: ModelEntity?
        var footprintPad: ModelEntity?
        var activeModel: BatteryModel = BatteryCatalog.baseCore
        var meterMarker: ModelEntity?
        var meterWallMarker: ModelEntity?
        var meterWallHit: (position: SIMD3<Float>, normal: SIMD3<Float>)?
        var panelMarker: ModelEntity?
        var panelWallMarker: ModelEntity?
        var panelWallHit: (position: SIMD3<Float>, normal: SIMD3<Float>)?
        var gasMarker: ModelEntity?
        var planes: [UUID: PlaneSample] = [:]
        /// Classified face samples, keyed by ARMeshAnchor identifier so removals stay cheap.
        var meshSamples: [UUID: [ClassifiedMeshSample]] = [:]
        /// World-space mesh kept for `scene.ply`. Separate from the on-screen draw, which stays in anchor space.
        private var meshClouds: [UUID: MeshPointCloudChunk] = [:]
        var meshVisuals: [UUID: AnchorEntity] = [:]
        fileprivate var pendingMeshDraws: [UUID: MeshDrawBuffers] = [:]
        var lastMeshDraw = Date.distantPast
        var transferBox: ModelEntity?
        var trackingBlockedMessage: String?
        private let trackingNotice = OSAllocatedUnfairLock<String?>(initialState: nil)
        nonisolated let equipmentBridge = EquipmentScanBridge()
        /// Camera colors for `scene.ply`, remembered per world cell across mesh updates.
        nonisolated let meshColors = MeshColorCache()
        private let boxOverlay = EquipmentBoxOverlay(frame: .zero)
        private var meterGroundPosition: SIMD3<Float>?
        private var panelGroundPosition: SIMD3<Float>?
        private var meterLock = EquipmentLock()
        private var panelLock = EquipmentLock()
        private var meterBox: LockedEquipmentBox?
        private var panelBox: LockedEquipmentBox?
        private var pendingDetections: [EquipmentDetection] = []
        private var pendingScan: EquipmentScanFrame?
        private var holdAnchor: SIMD3<Float>?
        private var holdSince: CFTimeInterval?
        private var batterySlide: BatterySlide?
        private var batteryConfirmed = false
        private var gasResolved = false
        private let holdReticle: UIView = {
            let ring = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
            ring.layer.cornerRadius = 22
            ring.layer.borderColor = UIColor.white.cgColor
            ring.layer.borderWidth = 2
            ring.isUserInteractionEnabled = false
            ring.isHidden = true
            return ring
        }()
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
            arView.addSubview(holdReticle)
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
            onScreenshot: @escaping (UIImage?) -> Void,
            onFailure: @escaping (String) -> Void,
            onTrackingStatus: @escaping (String?) -> Void,
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
            equipmentBridge.setEnabled(scanning && !coachingActive)
            if !scanning {
                pendingDetections = []
                pendingScan = nil
                refreshEquipmentBoxes()
            }
            self.onSceneChange = onSceneChange
            self.onYawChange = onYawChange
            self.onLiveFeet = onLiveFeet
            self.onScreenshot = onScreenshot
            self.onFailure = onFailure
            self.onTrackingStatus = onTrackingStatus
            self.onCoachingActiveChange = onCoachingActiveChange
            if startedScanning, !reportedScanLoadError, let loadError = equipmentBridge.detector.loadError {
                reportedScanLoadError = true
                self.onFailure?("Equipment scan isn’t available (\(loadError)). Mark the meter and panel yourself.")
            }
            if !aimEnabled && holdLockKind() == nil {
                reticle?.isEnabled = false
                aimDot.isHidden = true
                holdReticle.isHidden = true
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
            onTrackingStatus = nil
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
                self.holdReticle.isHidden = true
                self.equipmentBridge.setEnabled(false)
                self.onCoachingActiveChange?(true)
            }
        }

        nonisolated func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
            Task { @MainActor in
                self.coachingActive = false
                self.equipmentBridge.setEnabled(self.scanningEquipment)
                self.onCoachingActiveChange?(false)
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
                break
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
            guard mode == .battery, var slide = batterySlide else { return }
            let finished = gesture.state == .ended || gesture.state == .cancelled
            if let position = groundPosition(in: arView, at: gesture.location(in: arView)) {
                slide.along = simd_dot(position - slide.origin, slide.axis)
                batterySlide = slide
                applyBatterySlide(resetYaw: false)
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
            if batteryConfirmed {
                batteryBody?.model?.materials = [SimpleMaterial(color: color, isMetallic: false)]
                footprintPad?.model?.materials = [UnlitMaterial(color: color.withAlphaComponent(0.35))]
            } else {
                batteryBody?.model?.materials = [UnlitMaterial(color: color.withAlphaComponent(0.45))]
                footprintPad?.model?.materials = [UnlitMaterial(color: color.withAlphaComponent(0.22))]
            }
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
            placeDerivedWorkingSpace()
            let snapshot = makeSnapshot()
            scene = snapshot
            updateTransferBox(snapshot)
            let change = onSceneChange
            Task { @MainActor in
                change?(snapshot)
            }
        }

        nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
            equipmentBridge.consider(frame)
            let message = Self.trackingMessage(for: frame.camera.trackingState)
            let changed = trackingNotice.withLock { current -> Bool in
                guard current != message else { return false }
                current = message
                return true
            }
            guard changed else { return }
            Task { @MainActor in
                self.trackingBlockedMessage = message
                self.onTrackingStatus?(message)
            }
        }

        nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            upsertPlanes(from: anchors)
            upsertMesh(from: anchors, frame: session.currentFrame)
        }

        nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            upsertPlanes(from: anchors)
            upsertMesh(from: anchors, frame: session.currentFrame)
        }

        /// LiDAR mesh anchors update many times a second; skip the hop to the main actor when no wall changed.
        private nonisolated func upsertPlanes(from anchors: [ARAnchor]) {
            let samples = Self.planeSamples(from: anchors)
            guard !samples.isEmpty else { return }
            Task { @MainActor in
                self.upsert(samples)
            }
        }

        private nonisolated func upsertMesh(from anchors: [ARAnchor], frame: ARFrame?) {
            let samples = Self.classifiedMeshes(from: anchors, frame: frame, colors: meshColors)
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
                    self.meshClouds.removeValue(forKey: id)
                    self.pendingMeshDraws.removeValue(forKey: id)
                    self.meshVisuals[id]?.removeFromParent()
                    self.meshVisuals.removeValue(forKey: id)
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

        /// ASCII PLY of every current mesh anchor. Nil when the scan has no vertices.
        func pointCloudPLYData() -> Data? {
            PointCloudPLY.data(from: Array(meshClouds.values))
        }

        var hasExportableMesh: Bool {
            meshClouds.values.contains { !$0.positions.isEmpty }
        }

        private func upsertMesh(_ updates: [ClassifiedMeshUpdate]) {
            for update in updates {
                meshSamples[update.id] = update.samples
                meshClouds[update.id] = update.cloud
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
            activeModel = model
            if batteryRig != nil {
                buildBatteryRig()
                applyYaw()
                emit()
            }
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
            case .meter:
                meterWallHit = hit
                meterLock.locked = true
                rememberLockedBox(.electricMeter, at: hit.position, normal: hit.normal)
            case .panel:
                panelWallHit = hit
                panelLock.locked = true
                rememberLockedBox(.breakerPanel, at: hit.position, normal: hit.normal)
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
            guard mode != .battery else { return }
            guard let position = markerPosition(at: point) else {
                onFailure?(mode == .gasMeter
                    ? "Point the dot at the gas meter and try again."
                    : "Point the dot at the ground and try again.")
                return
            }
            switch mode {
            case .battery:
                return
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
            holdReticle.isHidden = true
            hideLiveLine()
        }

        @objc func tickAim() {
            let interface = arView.window?.windowScene?.interfaceOrientation ?? .portrait
            equipmentBridge.setViewport(arView.bounds.size, orientation: interface)
            if let packet = equipmentBridge.takeLatest() {
                applyScan(packet)
            }
            refreshEquipmentBoxes()
            if walkStep == .battery {
                suggestBatterySpotIfNeeded()
            }
            if holdLockKind() != nil {
                updateHoldAim()
                return
            }
            holdReticle.isHidden = true
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

        func clearEquipmentLock(_ kind: PlacementTarget) {
            switch kind {
            case .meter:
                meterLock = EquipmentLock()
                meterWallHit = nil
                meterGroundPosition = nil
                meterBox = nil
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
                panelGroundPosition = nil
                panelBox = nil
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

        /// YOLO boxes are only the latest frame. Locked boxes are projected from the world anchor instead.
        private func applyScan(_ packet: EquipmentScanFrame) {
            guard scanningEquipment, !coachingActive, trackingBlockedMessage == nil else {
                pendingDetections = []
                pendingScan = nil
                return
            }
            var best: [EquipmentKind: EquipmentDetection] = [:]
            for detection in packet.detections where detection.confidence >= 0.25 {
                if let existing = best[detection.kind], existing.confidence >= detection.confidence { continue }
                best[detection.kind] = detection
            }
            // Far away, the meter and panel look alike. One box scored as both is one object; keep the stronger label.
            if let meter = best[.electricMeter], let panel = best[.breakerPanel],
               Self.overlap(meter.boundingBox, panel.boundingBox) > 0.3 {
                best[meter.confidence >= panel.confidence ? .breakerPanel : .electricMeter] = nil
            }
            pendingScan = packet
            pendingDetections = Array(best.values)
            var lockedSomething = false
            // Weak boxes still draw, but only confident ones count toward a lock.
            for detection in best.values where detection.confidence >= 0.5 {
                let alreadyLocked = detection.kind == .electricMeter ? meterLock.locked : panelLock.locked
                guard !alreadyLocked, let landing = project(detection, in: packet) else { continue }
                // The meter and panel are separate boxes, so a lock on top of the other one is a mislabel.
                let other = detection.kind == .electricMeter ? panelWallHit : meterWallHit
                if let other, simd_distance(other.position, landing.position) < 0.3 { continue }
                let sample = EquipmentLock.Sample(point: landing.position, normal: landing.normal)
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
            if lockedSomething {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                emit()
            }
        }

        /// Intersection over the smaller box, so a box nested inside another counts as the same object.
        private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let shared = a.intersection(b)
            guard !shared.isNull else { return 0 }
            let smaller = min(a.width * a.height, b.width * b.height)
            return smaller > 0 ? shared.width * shared.height / smaller : 0
        }

        private func project(_ detection: EquipmentDetection, in packet: EquipmentScanFrame) -> (position: SIMD3<Float>, normal: SIMD3<Float>)? {
            let center = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
            let pixel = Self.bufferPixel(visionPoint: center, imageSize: packet.imageSize, orientation: packet.visionOrientation)
            let ray = Self.cameraRay(through: pixel, intrinsics: packet.intrinsics, transform: packet.cameraTransform)
            if let wall = wallHit(origin: ray.origin, direction: ray.direction) {
                return wall
            }
            guard let depth = packet.depth else { return nil }
            return depthPatch(
                at: pixel,
                depth: depth,
                imageSize: packet.imageSize,
                intrinsics: packet.intrinsics,
                cameraTransform: packet.cameraTransform,
                cameraOrigin: ray.origin
            )
        }

        /// Median of a depth patch. One empty neighbor no longer throws the hit away.
        private func depthPatch(
            at pixel: CGPoint,
            depth: DepthSample,
            imageSize: CGSize,
            intrinsics: simd_float3x3,
            cameraTransform: simd_float4x4,
            cameraOrigin: SIMD3<Float>
        ) -> (position: SIMD3<Float>, normal: SIMD3<Float>)? {
            guard depth.width > 1, depth.height > 1, imageSize.width > 1, imageSize.height > 1 else { return nil }
            let centerColumn = min(max(Int((pixel.x / imageSize.width * CGFloat(depth.width)).rounded()), 0), depth.width - 1)
            let centerRow = min(max(Int((pixel.y / imageSize.height * CGFloat(depth.height)).rounded()), 0), depth.height - 1)
            let fx = intrinsics.columns.0.x
            let fy = intrinsics.columns.1.y
            let cx = intrinsics.columns.2.x
            let cy = intrinsics.columns.2.y
            let scaleX = Float(imageSize.width) / Float(depth.width)
            let scaleY = Float(imageSize.height) / Float(depth.height)

            struct Cell {
                var column: Int
                var row: Int
                var world: SIMD3<Float>
            }

            func worldPoint(_ column: Int, _ row: Int) -> SIMD3<Float>? {
                guard column >= 0, column < depth.width, row >= 0, row < depth.height else { return nil }
                let index = row * depth.width + column
                guard depth.meters.indices.contains(index) else { return nil }
                if let confidence = depth.confidence, confidence.indices.contains(index), confidence[index] == 0 { return nil }
                let meters = depth.meters[index]
                guard meters >= 0.2, meters <= 5 else { return nil }
                let imageX = (Float(column) + 0.5) * scaleX
                let imageY = (Float(row) + 0.5) * scaleY
                let cameraPoint = SIMD4<Float>((imageX - cx) * meters / fx, -((imageY - cy) * meters / fy), -meters, 1)
                let world = cameraTransform * cameraPoint
                return SIMD3(world.x, world.y, world.z)
            }

            var cells: [Cell] = []
            let radius = 4
            for row in (centerRow - radius)...(centerRow + radius) {
                for column in (centerColumn - radius)...(centerColumn + radius) {
                    if let world = worldPoint(column, row) {
                        cells.append(Cell(column: column, row: row, world: world))
                    }
                }
            }
            guard cells.count >= 4 else { return nil }

            func medianPoint(_ subset: [Cell]) -> SIMD3<Float>? {
                guard !subset.isEmpty else { return nil }
                let mid = subset.count / 2
                let xs = subset.map(\.world.x).sorted()
                let ys = subset.map(\.world.y).sorted()
                let zs = subset.map(\.world.z).sorted()
                return SIMD3(xs[mid], ys[mid], zs[mid])
            }

            let distances = cells.map { simd_distance($0.world, cameraOrigin) }.sorted()
            let medianMeters = distances[distances.count / 2]
            guard medianMeters >= 0.2, medianMeters <= 5 else { return nil }
            let imageX = (Float(centerColumn) + 0.5) * scaleX
            let imageY = (Float(centerRow) + 0.5) * scaleY
            let cameraPoint = SIMD4<Float>((imageX - cx) * medianMeters / fx, -((imageY - cy) * medianMeters / fy), -medianMeters, 1)
            let world4 = cameraTransform * cameraPoint
            let world = SIMD3(world4.x, world4.y, world4.z)

            let left = medianPoint(cells.filter { $0.column < centerColumn })
            let right = medianPoint(cells.filter { $0.column > centerColumn })
            let up = medianPoint(cells.filter { $0.row < centerRow })
            let down = medianPoint(cells.filter { $0.row > centerRow })
            guard left != nil || right != nil, up != nil || down != nil else { return nil }
            let horizontal = (right ?? world) - (left ?? world)
            let vertical = (down ?? world) - (up ?? world)
            guard simd_length(horizontal) > 0.004, simd_length(vertical) > 0.004 else { return nil }
            var normal = simd_cross(horizontal, vertical)
            let normalLength = simd_length(normal)
            guard normalLength > 1e-6 else { return nil }
            normal /= normalLength
            guard abs(normal.y) < 0.5 else { return nil }
            var flat = SIMD3<Float>(normal.x, 0, normal.z)
            let flatLength = simd_length(flat)
            guard flatLength > 0.001 else { return nil }
            flat /= flatLength
            if simd_dot(flat, cameraOrigin - world) < 0 { flat = -flat }
            return (world, flat)
        }

        private func lockEquipment(_ kind: EquipmentKind, at sample: EquipmentLock.Sample) {
            let target: PlacementTarget = kind == .electricMeter ? .meter : .panel
            placeWallMarker(kind: target, hit: (position: sample.point, normal: sample.normal))
            let ground = groundUnder(sample.point, normal: sample.normal)
            switch kind {
            case .electricMeter: meterGroundPosition = ground
            case .breakerPanel: panelGroundPosition = ground
            }
        }

        private func rememberLockedBox(_ kind: EquipmentKind, at point: SIMD3<Float>, normal: SIMD3<Float>) {
            let outward = horizontalUnit(normal) ?? SIMD3<Float>(0, 0, 1)
            let extent: Float = kind == .electricMeter ? 0.25 : 0.4
            let box = LockedEquipmentBox(center: point, normal: outward, extent: extent, kind: kind)
            switch kind {
            case .electricMeter: meterBox = box
            case .breakerPanel: panelBox = box
            }
        }

        /// Projects locked world boxes every frame, including after the scan step ends.
        private func refreshEquipmentBoxes() {
            guard arView.bounds.width > 1 else { return }
            let frame = arView.session.currentFrame
            var items: [EquipmentBoxOverlay.Item] = []
            for box in [meterBox, panelBox].compactMap({ $0 }) {
                guard let rect = projectedRect(for: box, frame: frame) else { continue }
                let title: String
                if let frame, let meters = medianDepthMeters(in: rect, frame: frame) {
                    let feet = Double(meters) / Double(BatteryGeometry.feetToMeters)
                    title = String(format: "%@ · %.1f ft", box.kind.title, feet)
                } else {
                    title = box.kind.title
                }
                items.append(EquipmentBoxOverlay.Item(rect: rect, color: .systemGreen, title: title))
            }
            if scanningEquipment, !coachingActive, trackingBlockedMessage == nil, let packet = pendingScan {
                for detection in pendingDetections {
                    let locked = detection.kind == .electricMeter ? meterLock.locked : panelLock.locked
                    if locked { continue }
                    let rect = Self.viewRect(for: detection.boundingBox, in: packet)
                    guard rect.width > 2, rect.height > 2, rect.origin.x.isFinite, rect.origin.y.isFinite else { continue }
                    let landing = project(detection, in: packet)
                    let color: UIColor
                    let title: String
                    if landing == nil {
                        color = .white
                        title = "\(detection.kind.title) · not on a wall"
                    } else {
                        color = detection.kind == .electricMeter ? .systemBlue : .systemIndigo
                        title = detection.kind.title
                    }
                    items.append(EquipmentBoxOverlay.Item(rect: rect, color: color, title: title))
                }
            }
            boxOverlay.items = items
        }

        private func projectedRect(for box: LockedEquipmentBox, frame: ARFrame?) -> CGRect? {
            guard let frame else { return nil }
            let camera = frame.camera.transform
            let cameraPosition = SIMD3<Float>(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
            let look = -SIMD3<Float>(camera.columns.2.x, camera.columns.2.y, camera.columns.2.z)
            let visible = boxCorners(box).filter { simd_dot($0 - cameraPosition, look) > 0.05 }
            guard visible.count >= 2 else { return nil }
            let projected = visible.compactMap { arView.project($0) }
            guard projected.count >= 2 else { return nil }
            let xs = projected.map(\.x)
            let ys = projected.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
                  minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite else { return nil }
            return CGRect(x: minX, y: minY, width: max(maxX - minX, 12), height: max(maxY - minY, 12))
        }

        private func boxCorners(_ box: LockedEquipmentBox) -> [SIMD3<Float>] {
            let up = SIMD3<Float>(0, 1, 0)
            var along = simd_cross(box.normal, up)
            let length = simd_length(along)
            if length > 0.001 {
                along /= length
            } else {
                along = SIMD3(1, 0, 0)
            }
            let half = box.extent / 2
            return [
                box.center + along * half + up * half,
                box.center - along * half + up * half,
                box.center + along * half - up * half,
                box.center - along * half - up * half
            ]
        }

        /// Confident depth inside the on-screen box. Confidence 0 is skipped. Past about 5 m stays unlabeled.
        private func medianDepthMeters(in viewRect: CGRect, frame: ARFrame) -> Float? {
            guard let depth = EquipmentPixelBuffer.depthSample(from: frame.smoothedSceneDepth ?? frame.sceneDepth) else { return nil }
            let viewSize = arView.bounds.size
            guard viewSize.width > 1, viewSize.height > 1, depth.width > 1, depth.height > 1 else { return nil }
            let interface = arView.window?.windowScene?.interfaceOrientation ?? .portrait
            let display = frame.displayTransform(for: interface, viewportSize: viewSize)
            let inverse = display.inverted()
            let corners = [
                CGPoint(x: viewRect.minX, y: viewRect.minY),
                CGPoint(x: viewRect.maxX, y: viewRect.minY),
                CGPoint(x: viewRect.minX, y: viewRect.maxY),
                CGPoint(x: viewRect.maxX, y: viewRect.maxY)
            ].map { corner -> CGPoint in
                CGPoint(x: corner.x / viewSize.width, y: corner.y / viewSize.height).applying(inverse)
            }
            let xs = corners.map(\.x)
            let ys = corners.map(\.y)
            guard let minNX = xs.min(), let maxNX = xs.max(), let minNY = ys.min(), let maxNY = ys.max() else { return nil }
            let minColumn = max(Int((minNX * CGFloat(depth.width)).rounded(.down)), 0)
            let maxColumn = min(Int((maxNX * CGFloat(depth.width)).rounded(.up)), depth.width - 1)
            let minRow = max(Int((minNY * CGFloat(depth.height)).rounded(.down)), 0)
            let maxRow = min(Int((maxNY * CGFloat(depth.height)).rounded(.up)), depth.height - 1)
            guard maxColumn >= minColumn, maxRow >= minRow else { return nil }
            var values: [Float] = []
            for row in minRow...maxRow {
                for column in minColumn...maxColumn {
                    let index = row * depth.width + column
                    guard depth.meters.indices.contains(index) else { continue }
                    if let confidence = depth.confidence, confidence.indices.contains(index), confidence[index] == 0 { continue }
                    let meters = depth.meters[index]
                    guard meters >= 0.2, meters <= 5 else { continue }
                    let imagePoint = CGPoint(
                        x: (CGFloat(column) + 0.5) / CGFloat(depth.width),
                        y: (CGFloat(row) + 0.5) / CGFloat(depth.height)
                    )
                    let viewNorm = imagePoint.applying(display)
                    let viewPoint = CGPoint(x: viewNorm.x * viewSize.width, y: viewNorm.y * viewSize.height)
                    guard viewRect.contains(viewPoint) else { continue }
                    values.append(meters)
                }
            }
            guard !values.isEmpty else { return nil }
            values.sort()
            return values[values.count / 2]
        }

        private func holdLockKind() -> EquipmentKind? {
            guard scanningEquipment, !coachingActive else { return nil }
            if !meterLock.locked { return .electricMeter }
            if !panelLock.locked { return .breakerPanel }
            return nil
        }

        func commitHoldSample() {
            guard let kind = holdLockKind() else { return }
            guard trackingAllowsConfirmation(report: true) else { return }
            let point = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            guard let sample = holdSample(at: point) else {
                onFailure?("Hold the dot on the wall and try again.")
                return
            }
            absorbHold(sample, kind: kind)
        }

        private func updateHoldAim() {
            guard arView.bounds.width > 1, let kind = holdLockKind() else {
                holdReticle.isHidden = true
                resetHold()
                return
            }
            let point = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            holdReticle.center = point
            holdReticle.isHidden = false
            aimDot.center = point
            aimDot.isHidden = false
            reticle?.isEnabled = false
            hideLiveLine()
            guard trackingBlockedMessage == nil, let sample = holdSample(at: point) else {
                resetHold()
                return
            }
            let now = CACurrentMediaTime()
            if let anchor = holdAnchor, simd_distance(anchor, sample.point) <= 0.15 {
                if let holdSince, now - holdSince >= 0.5 {
                    absorbHold(EquipmentLock.Sample(point: anchor, normal: sample.normal), kind: kind)
                }
            } else {
                holdAnchor = sample.point
                holdSince = now
            }
        }

        private func holdSample(at viewPoint: CGPoint) -> EquipmentLock.Sample? {
            if let wall = wallHit(in: arView, at: viewPoint) {
                let flat = horizontalUnit(wall.normal) ?? wall.normal
                return EquipmentLock.Sample(point: wall.position, normal: flat)
            }
            guard let frame = arView.session.currentFrame,
                  let depth = EquipmentPixelBuffer.depthSample(from: frame.smoothedSceneDepth ?? frame.sceneDepth) else { return nil }
            let interface = arView.window?.windowScene?.interfaceOrientation ?? .portrait
            let imageSize = CGSize(
                width: CVPixelBufferGetWidth(frame.capturedImage),
                height: CVPixelBufferGetHeight(frame.capturedImage)
            )
            guard arView.bounds.width > 1, arView.bounds.height > 1, imageSize.width > 1 else { return nil }
            let display = frame.displayTransform(for: interface, viewportSize: arView.bounds.size)
            let viewNorm = CGPoint(x: viewPoint.x / arView.bounds.width, y: viewPoint.y / arView.bounds.height)
            let imageNorm = viewNorm.applying(display.inverted())
            let pixel = CGPoint(x: imageNorm.x * imageSize.width, y: imageNorm.y * imageSize.height)
            let camera = frame.camera.transform
            let origin = SIMD3<Float>(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
            guard let hit = depthPatch(
                at: pixel,
                depth: depth,
                imageSize: imageSize,
                intrinsics: frame.camera.intrinsics,
                cameraTransform: camera,
                cameraOrigin: origin
            ) else { return nil }
            return EquipmentLock.Sample(point: hit.position, normal: hit.normal)
        }

        private func absorbHold(_ sample: EquipmentLock.Sample, kind: EquipmentKind) {
            let settled: EquipmentLock.Sample?
            switch kind {
            case .electricMeter: settled = meterLock.absorb(sample)
            case .breakerPanel: settled = panelLock.absorb(sample)
            }
            guard let settled else { return }
            lockEquipment(kind, at: settled)
            resetHold()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            emit()
        }

        private func resetHold() {
            holdAnchor = nil
            holdSince = nil
        }

        /// 3 ft transfer-switch reserve plus half the 3 ft pad.
        private var batteryAlongOffset: Float {
            TransferSwitchReservation.heightMeters + BatteryGeometry.footprintMeters / 2
        }

        /// A few inches, so the measured back face can sit inside the 1 ft wall check.
        private var batteryWallGap: Float { 3 * BatteryGeometry.inchesToMeters }

        fileprivate func syncGuide(step: WalkStep, gasResolved: Bool) {
            walkStep = step
            self.gasResolved = gasResolved
            guard !batteryConfirmed else { return }
            if step == .battery, gasResolved {
                suggestBatterySpotIfNeeded()
            } else if step != .battery {
                clearUnconfirmedBattery()
            }
        }

        func confirmBatterySpot() {
            guard batteryRig != nil else { return }
            batteryConfirmed = true
            applyTone()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            emitGestureEnded()
        }

        func flipBatterySide() {
            guard var slide = batterySlide else { return }
            if abs(slide.along) < 0.2 {
                slide.along = slide.along >= 0 ? -batteryAlongOffset : batteryAlongOffset
            } else {
                slide.along = -slide.along
            }
            batterySlide = slide
            applyBatterySlide(resetYaw: true)
            emitGestureEnded()
        }

        private func suggestBatterySpotIfNeeded() {
            guard walkStep == .battery, gasResolved, !batteryConfirmed, batteryRig == nil else { return }
            guard let wall = meterWallHit, let outward = horizontalUnit(wall.normal) else { return }
            guard let groundY = meterGroundPosition?.y ?? groundUnder(wall.position, normal: wall.normal)?.y else { return }
            let up = SIMD3<Float>(0, 1, 0)
            guard let axis = unitVector(simd_cross(up, outward)) else { return }
            var along = batteryAlongOffset
            if let panel = panelWallHit?.position, simd_dot(panel - wall.position, axis) > 0.05 {
                along = -batteryAlongOffset
            }
            var slide = BatterySlide(
                origin: SIMD3(wall.position.x, groundY, wall.position.z),
                outward: outward,
                axis: axis,
                groundY: groundY,
                along: along
            )
            if let gas = gasMarker?.position(relativeTo: nil),
               horizontalFeet(batteryWorldPosition(slide), gas) < BaseRuleSet.minGasMeterDistanceFeet {
                slide.along = -slide.along
            }
            batterySlide = slide
            applyBatterySlide(resetYaw: true)
            emit()
        }

        private func clearUnconfirmedBattery() {
            guard !batteryConfirmed, batteryRig != nil || batterySlide != nil else { return }
            batteryRig?.removeFromParent()
            batteryRig = nil
            batteryBody = nil
            batteryFaceMark = nil
            footprintPad = nil
            batterySlide = nil
            workingSpaceOverlay?.removeFromParent()
            workingSpaceOverlay = nil
            scene.workingSpacePosition = nil
            emit()
        }

        private func applyBatterySlide(resetYaw: Bool) {
            guard let slide = batterySlide else { return }
            if resetYaw {
                let yaw = atan2(slide.outward.x, slide.outward.z)
                yawRadians = yaw
                appliedYaw = yaw
                onYawChange?(yaw)
            }
            placeBattery(at: batteryWorldPosition(slide))
        }

        private func batteryWorldPosition(_ slide: BatterySlide) -> SIMD3<Float> {
            let offset = BatteryGeometry.depthMeters / 2 + batteryWallGap
            let center = slide.origin + slide.outward * offset + slide.axis * slide.along
            return SIMD3(center.x, slide.groundY, center.z)
        }

        private func horizontalFeet(_ origin: SIMD3<Float>, _ target: SIMD3<Float>) -> Double {
            let dx = Double(origin.x - target.x)
            let dz = Double(origin.z - target.z)
            return (dx * dx + dz * dz).squareRoot() / Double(BatteryGeometry.feetToMeters)
        }

        private func horizontalUnit(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
            unitVector(SIMD3(vector.x, 0, vector.z))
        }

        private func unitVector(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
            let length = simd_length(vector)
            guard length > 0.001 else { return nil }
            return vector / length
        }

        /// Horizontal plane directly under the wall hit. X and Z stay on the hit so meter distance uses that face.
        private func groundUnder(_ point: SIMD3<Float>, normal: SIMD3<Float>) -> SIMD3<Float>? {
            let flat = SIMD3<Float>(normal.x, 0, normal.z)
            let length = simd_length(flat)
            let outward = length > 0.001 ? flat / length : SIMD3<Float>(0, 0, 1)
            let origin = point + outward * 0.12 + SIMD3<Float>(0, 0.05, 0)
            for allowing: ARRaycastQuery.Target in [.existingPlaneGeometry, .estimatedPlane] {
                let query = ARRaycastQuery(origin: origin, direction: SIMD3(0, -1, 0), allowing: allowing, alignment: .horizontal)
                if let hit = arView.session.raycast(query).first {
                    return SIMD3(point.x, hit.worldTransform.columns.3.y, point.z)
                }
            }
            return nil
        }

        /// The 30 × 36 in slab sits in front of the locked meter (or panel) once the battery exists, so the mesh check has a volume.
        private func placeDerivedWorkingSpace() {
            guard batteryRig != nil else { return }
            let sample: (position: SIMD3<Float>, normal: SIMD3<Float>)?
            let groundY: Float
            if let meterWallHit {
                sample = meterWallHit
                groundY = meterGroundPosition?.y ?? meterWallHit.position.y
            } else if let panelWallHit {
                sample = panelWallHit
                groundY = panelGroundPosition?.y ?? panelWallHit.position.y
            } else {
                // Both locks were cleared. Drop the slab so it is not scored at the old spot.
                workingSpaceOverlay?.removeFromParent()
                workingSpaceOverlay = nil
                scene.workingSpacePosition = nil
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
        private func interpretWallHit(_ hit: ARRaycastResult) -> (position: SIMD3<Float>, normal: SIMD3<Float>) {
            let column = hit.worldTransform.columns.3
            let position = SIMD3<Float>(column.x, column.y, column.z)
            var normal = SIMD3<Float>(0, 0, 1)
            if let planeAnchor = hit.anchor as? ARPlaneAnchor {
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
            snapshot.batteryPosition = nil
            snapshot.suggestedBatteryPosition = nil
            if let batteryRig {
                let anchor = PlacementAnchor(batteryRig.position(relativeTo: nil))
                if batteryConfirmed {
                    snapshot.batteryPosition = anchor
                } else {
                    snapshot.suggestedBatteryPosition = anchor
                    snapshot.suggestedBatteryYawRadians = appliedYaw
                }
            }
            if let meterGroundPosition {
                snapshot.meterPosition = PlacementAnchor(meterGroundPosition)
            } else if let meterMarker {
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
            if let panelGroundPosition {
                snapshot.panelPosition = PlacementAnchor(panelGroundPosition)
            } else if let panelMarker {
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
            } else {
                snapshot.workingSpacePosition = nil
            }
            snapshot.classifiedMesh = classifiedSamplesNearPlacement()
            if let feet = placementMeasurer.wallClearance(in: snapshot)?.distanceFeet {
                snapshot.automaticWallClearanceFeet = (feet * 12).rounded() / 12
            } else {
                snapshot.automaticWallClearanceFeet = nil
            }
            return snapshot
        }

        private func grounded(_ position: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(position.x, position.y - 0.14, position.z)
        }

        private func trackingAllowsConfirmation(report: Bool) -> Bool {
            guard let trackingBlockedMessage else { return true }
            if report {
                onFailure?(trackingBlockedMessage)
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
            for samples in meshSamples.values {
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
        private nonisolated static func classifiedMeshes(from anchors: [ARAnchor], frame: ARFrame?, colors: MeshColorCache) -> [ClassifiedMeshUpdate] {
            anchors.compactMap { anchor in
                guard let mesh = anchor as? ARMeshAnchor else { return nil }
                return classifiedMesh(from: mesh, frame: frame, colors: colors)
            }
        }

        private nonisolated static func classifiedMesh(from mesh: ARMeshAnchor, frame: ARFrame?, colors cache: MeshColorCache) -> ClassifiedMeshUpdate? {
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
            var worldPositions: [SIMD3<Float>] = []
            positions.reserveCapacity(vertexCount)
            worldPositions.reserveCapacity(vertexCount)
            for index in 0..<vertexCount {
                let local = localVertex(index)
                positions.append(local)
                let world = transform * SIMD4(local.x, local.y, local.z, 1)
                worldPositions.append(SIMD3(world.x, world.y, world.z))
            }
            let colors = cache.colors(for: worldPositions, frame: frame).map { $0 ?? SIMD3<UInt8>(200, 200, 200) }
            var triangles: [UInt32] = []
            triangles.reserveCapacity(faceCount * 3)

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
                triangles.append(contentsOf: [UInt32(i0), UInt32(i1), UInt32(i2)])
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
                draw: MeshDrawBuffers(positions: positions, wall: wall, floor: floor, other: other),
                cloud: MeshPointCloudChunk(positions: worldPositions, colors: colors, triangles: triangles)
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

/// Real camera colors for exported mesh vertices. Kept in a 2 cm world grid, so a surface seen once keeps
/// its color after the camera turns away and ARKit re-meshes the chunk.
final class MeshColorCache: Sendable {
    private let cells = OSAllocatedUnfairLock<[SIMD3<Int32>: SIMD3<UInt8>]>(initialState: [:])
    private static let cellSize: Float = 0.02

    /// Nil where the point has never been visible to the camera.
    func colors(for worldPositions: [SIMD3<Float>], frame: ARFrame?) -> [SIMD3<UInt8>?] {
        let sampled = frame.map { Self.sample(worldPositions, in: $0) } ?? []
        return cells.withLock { cells in
            worldPositions.indices.map { index in
                let key = SIMD3<Int32>((worldPositions[index] / Self.cellSize).rounded(.down))
                if index < sampled.count, let rgb = sampled[index] {
                    cells[key] = rgb
                    return rgb
                }
                return cells[key]
            }
        }
    }

    /// Projects each point into the captured image. LiDAR depth drops points hidden behind nearer surfaces.
    private static func sample(_ points: [SIMD3<Float>], in frame: ARFrame) -> [SIMD3<UInt8>?] {
        let image = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(image) == 2 else { return [] }
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(image, 0),
              let chromaBase = CVPixelBufferGetBaseAddressOfPlane(image, 1) else { return [] }
        let width = CVPixelBufferGetWidthOfPlane(image, 0)
        let height = CVPixelBufferGetHeightOfPlane(image, 0)
        let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        let chromaRow = CVPixelBufferGetBytesPerRowOfPlane(image, 1)
        let luma = lumaBase.assumingMemoryBound(to: UInt8.self)
        let chroma = chromaBase.assumingMemoryBound(to: UInt8.self)

        let depthMap = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap
        if let depthMap { CVPixelBufferLockBaseAddress(depthMap, .readOnly) }
        defer { if let depthMap { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) } }
        let depthBase = depthMap.flatMap { CVPixelBufferGetBaseAddress($0) }
        let depthWidth = depthMap.map { CVPixelBufferGetWidth($0) } ?? 0
        let depthHeight = depthMap.map { CVPixelBufferGetHeight($0) } ?? 0
        let depthRow = depthMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        let intrinsics = frame.camera.intrinsics
        let worldToCamera = frame.camera.transform.inverse
        return points.map { point in
            // ARKit's camera looks down -Z with +Y up; image rows grow downward.
            let camera = worldToCamera * SIMD4(point.x, point.y, point.z, 1)
            let z = -camera.z
            guard z > 0.1, z < 8 else { return nil }
            let u = intrinsics[0][0] * camera.x / z + intrinsics[2][0]
            let v = intrinsics[2][1] - intrinsics[1][1] * camera.y / z
            guard u >= 0, v >= 0, u < Float(width - 1), v < Float(height - 1) else { return nil }
            let x = Int(u)
            let y = Int(v)

            if let depthBase {
                let dx = min(depthWidth - 1, x * depthWidth / width)
                let dy = min(depthHeight - 1, y * depthHeight / height)
                let measured = depthBase.advanced(by: dy * depthRow).assumingMemoryBound(to: Float.self)[dx]
                if measured > 0, abs(measured - z) > 0.08 + 0.03 * z { return nil }
            }

            // Full-range bi-planar YCbCr 4:2:0.
            let luminance = Float(luma[y * lumaRow + x])
            let chromaIndex = (y / 2) * chromaRow + (x / 2) * 2
            let cb = Float(chroma[chromaIndex]) - 128
            let cr = Float(chroma[chromaIndex + 1]) - 128
            func channel(_ value: Float) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }
            return SIMD3(
                channel(luminance + 1.402 * cr),
                channel(luminance - 0.344136 * cb - 0.714136 * cr),
                channel(luminance + 1.772 * cb)
            )
        }
    }
}
