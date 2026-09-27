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

/// One look-around after the meter, panel, and gas question. Farther is about 8 ft from the meter, where the
/// battery, pad, and transfer switch go, so the mesh covers that stretch of wall.
private struct LookAround: Equatable {
    var movedFarther = false
    var lookedLeft = false
    var lookedRight = false
    var done: Bool { movedFarther && lookedLeft && lookedRight }
}

/// Meter, panel, gas, look-around, then the battery. `ready` means the battery is placed and Submit is on.
private enum ScanCue: Equatable {
    case findMeter
    case findPanel
    case gas
    case lookAround
    case placeBattery
    case ready
}

/// One phone-motion cue for the meter or panel search, drawn as an SF Symbol plus short copy.
/// Raw values match the ux branch's CoachTip so its other cues can be added here.
private enum CoachTip: String {
    case lookUp = "Look up at it"
    case pointDown = "Point your phone down"
    case stepBack = "Take a few steps back"
    case scootLeft = "Scoot left"
    case scootRight = "Scoot right"
    case zoomIn = "Get closer"
    case aimAtWall = "Aim at the wall"
    case holdStill = "Hold still"

    var symbol: String {
        switch self {
        case .lookUp: "arrow.up.circle.fill"
        case .pointDown: "arrow.down.circle.fill"
        case .stepBack: "figure.walk.motion"
        case .scootLeft: "arrow.left.circle.fill"
        case .scootRight: "arrow.right.circle.fill"
        case .zoomIn: "plus.magnifyingglass"
        case .aimAtWall: "viewfinder"
        case .holdStill: "hand.raised.fill"
        }
    }
}

/// What the scan screen can say about the current meter or panel search. The controller publishes it only on change.
private struct ScanFeedback: Equatable {
    /// Cue from the target's detector box. Nil with no box, nothing to find, or no working detector.
    var hint: CoachTip?
    /// Set when "Mark it myself" should show for this target: about 12 s without a lock, or the detector is down.
    var manualTarget: EquipmentKind?
    var detector: EquipmentObservationStatus = .ok
}

/// The controller's view of the scan step. `battery` shows the suggested spot beside the meter; `finish` keeps
/// the placed battery and its transfer-switch box on screen through Submit.
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
    @State private var scene: PlacementSceneSnapshot
    @State private var lookAround = LookAround()
    @State private var yawRadians: Float
    @State private var screenshotToken: UUID?
    @State private var pendingSave: UUID?
    @State private var statusMessage: String?
    @State private var trackingMessage: String?
    @State private var isVisible = false
    @State private var coachingIsActive = false
    @State private var scanFeedback = ScanFeedback()
    /// The meter or panel that just locked. "Not the …" can undo it for 5 s (and while the next item is searched for).
    @State private var recentLock: (kind: EquipmentKind, token: UUID)?
    @State private var capturedFrames = 0

    init(store: SurveyStore, onContinue: @escaping () -> Void) {
        self.store = store
        self.onContinue = onContinue
        let existing = store.placementController
        _scene = State(initialValue: existing?.scene ?? PlacementSceneSnapshot())
        _lookAround = State(initialValue: existing?.lookAround ?? LookAround())
        _yawRadians = State(initialValue: existing?.yawRadians ?? 0)
    }

    private var isSaving: Bool { pendingSave != nil }

    private var arSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    private var meterMarked: Bool {
        scene.meterPosition != nil || scene.meterWallPosition != nil
    }

    private var panelMarked: Bool {
        scene.panelPosition != nil || scene.panelWallPosition != nil
    }

    private var gasResolved: Bool {
        scene.gasMeterPosition != nil || store.gasMeterNotVisible
    }

    /// The suggested spot beside the meter is showing and has not been confirmed yet.
    private var hasBatteryGhost: Bool {
        scene.batteryPosition == nil && scene.suggestedBatteryPosition != nil
    }

    private var cue: ScanCue {
        if !meterMarked { return .findMeter }
        if !panelMarked { return .findPanel }
        if !gasResolved { return .gas }
        if !lookAround.done { return .lookAround }
        // Only "Put it here" sets batteryPosition; the ghost is `suggestedBatteryPosition`.
        if scene.batteryPosition == nil { return .placeBattery }
        return .ready
    }

    private var lockTarget: EquipmentKind? {
        switch cue {
        case .findMeter: .electricMeter
        case .findPanel: .breakerPanel
        case .gas, .lookAround, .placeBattery, .ready: nil
        }
    }

    /// Controller step for the current cue. The battery ghost only exists in `battery`; `finish` keeps the placed
    /// battery and its transfer-switch box. Any other step drops an unconfirmed ghost.
    private var guideStep: WalkStep {
        switch cue {
        case .findMeter, .findPanel, .lookAround: .scan
        case .gas: .gas
        case .placeBattery: .battery
        case .ready: .finish
        }
    }

    /// Confirmed battery wins. Until "Put it here", the ghost stands in as the battery, so its tone is the tone
    /// the spot would get if placed there.
    private var guidedScene: PlacementSceneSnapshot {
        var preview = scene
        if preview.batteryPosition == nil, let suggested = preview.suggestedBatteryPosition {
            preview.batteryPosition = suggested
            preview.batteryYawRadians = preview.suggestedBatteryYawRadians
        }
        return preview
    }

    /// The full survey assessment with the ghost or placed battery applied: every required rule, including the
    /// breaker and panel-rating ones, so the preview is green only when the survey itself would be.
    /// Nil with no battery on screen, since there is nothing to tint.
    private var liveAssessment: SurveyAssessment? {
        let preview = guidedScene
        guard preview.batteryPosition != nil else { return nil }
        return store.assessment(applying: preview)
    }

    var body: some View {
        Group {
            if arSupported {
                arScreen
            } else {
                unsupportedScreen
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            guard arSupported else { return }
            isVisible = true
            let controller = store.requirePlacementController()
            controller.resume()
            scene = controller.scene
            lookAround = controller.lookAround
            yawRadians = controller.yawRadians
            syncGuide()
        }
        .onChange(of: cue) { _, _ in
            statusMessage = nil
            syncGuide()
        }
        .onChange(of: meterMarked) { _, marked in
            noteLockChange(.electricMeter, marked: marked)
        }
        .onChange(of: panelMarked) { _, marked in
            noteLockChange(.breakerPanel, marked: marked)
        }
        .onDisappear {
            isVisible = false
            pendingSave = nil
            commitLiveScene()
            store.placementController?.pauseIfIdle()
        }
        .onChange(of: scenePhase) { _, phase in
            guard isVisible, arSupported else { return }
            if phase == .active {
                store.placementController?.resume()
            } else if phase == .background {
                store.placementController?.pauseIfIdle()
            }
        }
    }

    private var arScreen: some View {
        // One assessment per update: it tints the battery and writes the tone line.
        let assessment = liveAssessment
        return VStack(spacing: 0) {
            ZStack {
                if let controller = store.placementController {
                    PlacementARRepresentable(
                        controller: controller,
                        mode: cue == .gas ? .gasMeter : .battery,
                        measurementMode: false,
                        measurementKind: .batteryToMeter,
                        editingWorkingSpace: false,
                        // Battery step: one finger slides it along the meter wall, a tap on the ground moves it there,
                        // two fingers turn it. After "Put it here" it stays put until "Move it".
                        inputEnabled: cue == .gas || cue == .placeBattery,
                        aimEnabled: cue == .gas && scene.gasMeterPosition == nil,
                        tapEnabled: (cue == .gas && scene.gasMeterPosition == nil) || cue == .placeBattery,
                        scanning: true,
                        lockTarget: lockTarget,
                        yawRadians: yawRadians,
                        tone: assessment?.placementTone ?? .incomplete,
                        screenshotToken: screenshotToken,
                        onSceneChange: acceptScene,
                        onYawChange: { yawRadians = $0 },
                        onLiveFeet: { _ in },
                        onScreenshot: handleScreenshot,
                        onFailure: { statusMessage = $0 },
                        onTrackingStatus: { trackingMessage = $0 },
                        onCoachingActiveChange: { coachingIsActive = $0 },
                        onLookAround: { lookAround = $0 },
                        onScanFeedback: { scanFeedback = $0 }
                    )
                }
            }
            .overlay(alignment: .topTrailing) {
                if capturedFrames > 0 && !coachingIsActive {
                    Label("\(capturedFrames)", systemImage: "camera.fill")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(12)
                        .accessibilityLabel("\(capturedFrames) scan photos captured")
                }
            }
            .task {
                while !Task.isCancelled {
                    capturedFrames = store.placementController?.keyframes.count ?? 0
                    try? await Task.sleep(for: .seconds(0.5))
                }
            }
            if !coachingIsActive {
                bottomBar(assessment)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
    }

    private func bottomBar(_ assessment: SurveyAssessment?) -> some View {
        VStack(spacing: 12) {
            Text(instruction)
                .font(.body)
                .multilineTextAlignment(.center)
            if let hint = activeHint {
                Label(hint.rawValue, systemImage: hint.symbol)
                    .font(.subheadline.weight(.semibold))
                    .symbolEffect(.pulse)
            }
            if cue == .placeBattery || cue == .ready, let assessment {
                // Words and an icon with the tint, never color alone, and no distances on the camera.
                Label(toneLine(assessment), systemImage: ToneStyle.symbol(assessment.placementTone))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToneStyle.color(assessment.placementTone))
                    .multilineTextAlignment(.center)
            }
            if let trackingMessage {
                Text(trackingMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            if lockTarget != nil, scanFeedback.detector == .inferenceFailed {
                Text("The equipment detector stopped responding.")
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
            if manualTargetForCue != nil || rejectableLock != nil {
                HStack(spacing: 12) {
                    if manualTargetForCue != nil {
                        Button {
                            store.placementController?.markTargetAtDot()
                        } label: {
                            Text("Mark it myself")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if let wrong = rejectableLock {
                        Button {
                            recentLock = nil
                            store.placementController?.rejectLock(wrong)
                        } label: {
                            Text("Not the \(wrong.title.lowercased())")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if cue == .gas {
                Button("No gas meter") {
                    store.setGasMeterNotVisible(true)
                    store.placementController?.clearGasMarker()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if cue == .lookAround {
                Button("Can't move farther") {
                    store.placementController?.skipLookAround()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if cue == .placeBattery {
                if hasBatteryGhost {
                    Button("Other side") {
                        store.placementController?.flipBatterySide()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isSaving)
                } else {
                    // No ground found beside the meter yet. Saving still works; the battery checks stay unknown (amber).
                    Button("Save without battery") {
                        submit(withoutBattery: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isSaving)
                }
            }
            if cue == .ready {
                Button("Move it") {
                    store.placementController?.unconfirmBatterySpot()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isSaving)
            }
            if cue == .placeBattery, hasBatteryGhost {
                Button {
                    store.placementController?.confirmBatterySpot()
                } label: {
                    Text("Put it here")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving)
            } else {
                Button {
                    submit()
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Submit")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving || cue != .ready)
            }
            if panelMarked || meterMarked || gasResolved {
                Button("Start over") { restart() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var unsupportedScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            ContentUnavailableView(
                "Placement preview isn’t available on this device",
                systemImage: "arkit",
                description: Text("Use a physical iPhone to scan the meter and the panel. You can complete the other survey sections here.")
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

    /// Detector cue for the meter or panel search only.
    private var activeHint: CoachTip? {
        lockTarget == nil ? nil : scanFeedback.hint
    }

    /// "Mark it myself" for the object this step is asking for, once the controller offers it.
    private var manualTargetForCue: EquipmentKind? {
        guard let lockTarget, scanFeedback.manualTarget == lockTarget else { return nil }
        return lockTarget
    }

    /// A lock "Not the …" may still undo: for 5 s after it locks, and while the next item is being searched for.
    /// It clears the lock and keeps it from relocking on the same spot. Later, only Start over (or a Redo) undoes it.
    private var rejectableLock: EquipmentKind? {
        switch cue {
        case .findPanel where meterMarked: return .electricMeter
        case .gas where panelMarked: return .breakerPanel
        default: break
        }
        guard let kind = recentLock?.kind else { return nil }
        return (kind == .electricMeter ? meterMarked : panelMarked) ? kind : nil
    }

    /// Answered on the Home and Electrical screens, not by where the battery sits. They still count toward the tone;
    /// the tone line names a siting rule first, since that is what moving the battery can change.
    private static let electricalRuleIDs: Set<String> = ["austin-main-breaker", "solar-or-two-batteries"]

    /// Words for the tone line: the tone's title, plus the first rule holding it there.
    private func toneLine(_ assessment: SurveyAssessment) -> String {
        let required = assessment.results.filter(\.isRequired)
        func first(_ status: CheckStatus) -> RuleResult? {
            required.first { $0.status == status && !Self.electricalRuleIDs.contains($0.id) }
                ?? required.first { $0.status == status }
        }
        switch assessment.placementTone {
        case .clear:
            return "\(ToneStyle.title(.clear)). Preview only, not approval."
        case .attested:
            return "\(ToneStyle.title(.attested)). Some passes are your answers, not measurements."
        case .conflict:
            guard let rule = first(.conflict) else { return ToneStyle.title(.conflict) }
            return "\(ToneStyle.title(.conflict)): \(rule.title)"
        case .incomplete:
            guard let rule = first(.unknown) else { return ToneStyle.title(.incomplete) }
            return "\(ToneStyle.title(.incomplete)): \(rule.title)"
        }
    }

    private var instruction: String {
        switch cue {
        case .findMeter:
            return manualTargetForCue == nil
                ? "Looking for the meter."
                : "Put the dot on the meter, then tap Mark it myself."
        case .findPanel:
            return manualTargetForCue == nil
                ? "Looking for the panel."
                : "Put the dot on the panel, then tap Mark it myself."
        case .gas:
            return scene.gasMeterPosition == nil
                ? "Gas meter? Tap it, or say there isn’t one."
                : "Gas meter marked."
        case .lookAround:
            if !lookAround.movedFarther { return "Move farther away." }
            if !lookAround.lookedLeft { return "Look left." }
            if !lookAround.lookedRight { return "Look right." }
            return "Move farther away."
        case .placeBattery:
            return hasBatteryGhost
                ? "Drag or tap the ground to slide the battery along the wall. Then tap Put it here."
                : "Point your phone at the ground beside the meter, or tap the ground there."
        case .ready:
            return "Tap Submit."
        }
    }

    private func syncGuide() {
        store.placementController?.syncGuide(step: guideStep, gasResolved: gasResolved)
    }

    /// Opens the 5 s "Not the …" window when a lock appears, and closes it if that lock goes away.
    private func noteLockChange(_ kind: EquipmentKind, marked: Bool) {
        guard marked else {
            if recentLock?.kind == kind { recentLock = nil }
            return
        }
        let token = UUID()
        recentLock = (kind, token)
        Task {
            try? await Task.sleep(for: .seconds(5))
            if recentLock?.token == token { recentLock = nil }
        }
    }

    private func acceptScene(_ snapshot: PlacementSceneSnapshot) {
        var incoming = snapshot
        var current = scene
        incoming.verticalPlanes = []
        current.verticalPlanes = []
        guard incoming != current else { return }
        scene = snapshot
    }

    private func restart() {
        store.setGasMeterNotVisible(false)
        store.placementController?.restartScan()
        // The live scene is empty now, so it would never be committed over the old marks, height, and photo.
        store.resetPlacementEvidence()
        statusMessage = nil
        recentLock = nil
    }

    /// Submit once the battery is placed. "Save without battery" saves from the battery step when no spot showed up.
    private func submit(withoutBattery: Bool = false) {
        guard !isSaving, cue == .ready || (withoutBattery && cue == .placeBattery) else { return }
        commitLiveScene()
        let token = UUID()
        pendingSave = token
        screenshotToken = token
        statusMessage = nil
        Task {
            try? await Task.sleep(for: .seconds(5))
            failScreenshot(token)
        }
    }

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
        statusMessage = "The scan photo did not capture. Tap Submit again."
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
    var lockTarget: EquipmentKind?
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
    var onLookAround: (LookAround) -> Void
    var onScanFeedback: (ScanFeedback) -> Void

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
            lockTarget: lockTarget,
            yawRadians: yawRadians,
            tone: tone,
            screenshotToken: screenshotToken,
            onSceneChange: onSceneChange,
            onYawChange: onYawChange,
            onLiveFeet: onLiveFeet,
            onScreenshot: onScreenshot,
            onFailure: onFailure,
            onTrackingStatus: onTrackingStatus,
            onCoachingActiveChange: onCoachingActiveChange,
            onLookAround: onLookAround,
            onScanFeedback: onScanFeedback
        )
    }
}

private struct ClassifiedMeshUpdate: Sendable {
    var id: UUID
    var samples: [ClassifiedMeshSample]
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
        var gasPoint: SIMD3<Float>?
        fileprivate var lookAround = LookAround()
        private var onLookAround: ((LookAround) -> Void)?
        private var requestedLock: EquipmentKind?
        var planes: [UUID: PlaneSample] = [:]
        /// Classified face samples, keyed by ARMeshAnchor identifier so removals stay cheap.
        var meshSamples: [UUID: [ClassifiedMeshSample]] = [:]
        /// World-space mesh kept for `scene.ply`. Classification stays in the samples; it is not drawn on the camera.
        private var meshClouds: [UUID: MeshPointCloudChunk] = [:]
        var transferBox: ModelEntity?
        var trackingBlockedMessage: String?
        private let trackingNotice = OSAllocatedUnfairLock<String?>(initialState: nil)
        nonisolated let equipmentBridge = EquipmentScanBridge()
        /// Camera colors for `scene.ply`, remembered per mesh anchor so a nudge of the anchor does not miss.
        nonisolated let meshColors = MeshColorCache()
        /// Posed photos and depth from new viewpoints during the scan, zipped next to `scene.ply`.
        nonisolated let keyframes = KeyframeRecorder()
        private let boxOverlay = EquipmentBoxOverlay(frame: .zero)
        private var meterGroundPosition: SIMD3<Float>?
        private var panelGroundPosition: SIMD3<Float>?
        private var meterLock = EquipmentLock()
        private var panelLock = EquipmentLock()
        private var pendingDetections: [EquipmentDetection] = []
        /// Wall or depth landing for each box in `pendingDetections`, worked out once per packet. No key means not on a wall.
        private var pendingLandings: [EquipmentKind: (position: SIMD3<Float>, normal: SIMD3<Float>)] = [:]
        private var pendingScan: EquipmentScanFrame?
        private var holdAnchor: SIMD3<Float>?
        private var holdSince: CFTimeInterval?
        /// The center-dot hold counts its own samples. Sharing the detector's buffer let a box-center landing
        /// more than 15 cm from the dot reset the hold on every packet, so a large panel could lock on neither path.
        private var holdStreak = EquipmentLock()
        /// After "Not the …", the same spot cannot lock again until the phone looks away or aims somewhere else.
        private var relockBan: (kind: EquipmentKind, point: SIMD3<Float>)?
        private var meterLockSource: EquipmentLockSource?
        private var panelLockSource: EquipmentLockSource?
        /// Status of the last detector packet. `modelMissing` is read from the detector itself, since no packets arrive then.
        private var detectorStatus: EquipmentObservationStatus = .ok
        private var scanHint: CoachTip?
        /// The meter or panel being searched for, when that search began, and whether "Mark it myself" is on for it.
        /// Once offered, the button stays until that target locks, so a flaky detector cannot make it flicker.
        private var searchTarget: EquipmentKind?
        private var searchStartedAt: CFTimeInterval?
        private var manualMarkOffered = false
        private var onScanFeedback: ((ScanFeedback) -> Void)?
        private var lastScanFeedback: ScanFeedback?
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

        fileprivate func bind(
            mode: PlacementTarget,
            measurementMode: Bool,
            measurementKind: PlacementMeasurementKind,
            editingWorkingSpace: Bool,
            inputEnabled: Bool,
            aimEnabled: Bool,
            tapEnabled: Bool,
            scanning: Bool,
            lockTarget: EquipmentKind?,
            yawRadians: Float,
            tone: PlacementTone,
            screenshotToken: UUID?,
            onSceneChange: @escaping (PlacementSceneSnapshot) -> Void,
            onYawChange: @escaping (Float) -> Void,
            onLiveFeet: @escaping (Double?) -> Void,
            onScreenshot: @escaping (UIImage?) -> Void,
            onFailure: @escaping (String) -> Void,
            onTrackingStatus: @escaping (String?) -> Void,
            onCoachingActiveChange: @escaping (Bool) -> Void,
            onLookAround: @escaping (LookAround) -> Void,
            onScanFeedback: @escaping (ScanFeedback) -> Void
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
            self.requestedLock = lockTarget
            self.onLookAround = onLookAround
            self.onScanFeedback = onScanFeedback
            hideWorldBoxesIfNeeded()
            let startedScanning = scanning && !scanningEquipment
            scanningEquipment = scanning
            updateDetectorGate()
            updateKeyframeGate()
            if !scanning {
                clearPendingScan()
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
            // A view coming back starts from an empty ScanFeedback, so the next tick publishes again.
            lastScanFeedback = nil
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
                self.updateKeyframeGate()
                self.onCoachingActiveChange?(true)
            }
        }

        nonisolated func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
            Task { @MainActor in
                self.coachingActive = false
                self.updateDetectorGate()
                self.updateKeyframeGate()
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
                // Only the battery step moves it, so a stray tap during the scan cannot drop one.
                guard walkStep == .battery else { break }
                didPlace = moveBattery(toGroundAt: point)
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
            keyframes.consider(frame)
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

        /// ASCII PLY of every current mesh anchor plus the measurement overlay: battery, marks, distance bars,
        /// and each check as a header comment. Offline tools read the marks from here. Nil when the scan has no vertices.
        func pointCloudPLYData() -> Data? {
            let overlay = MeasurementOverlay.build(makeSnapshot(), measurer: placementMeasurer)
            return PointCloudPLY.data(from: Array(meshClouds.values) + [overlay.chunk], comments: overlay.comments)
        }

        var hasExportableMesh: Bool {
            meshClouds.values.contains { !$0.positions.isEmpty }
        }

        private func upsertMesh(_ updates: [ClassifiedMeshUpdate]) {
            for update in updates {
                meshSamples[update.id] = update.samples
                meshClouds[update.id] = update.cloud
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

        /// Locks keep a position. The camera shows the classifier box, not a cube in the world.
        private func placeMarker(kind: PlacementTarget, at position: SIMD3<Float>) {
            switch kind {
            case .meter:
                meterMarker?.removeFromParent()
                meterMarker = nil
                meterGroundPosition = position
            case .panel:
                panelMarker?.removeFromParent()
                panelMarker = nil
                panelGroundPosition = position
                updateKeyframeGate()
            case .gasMeter:
                gasMarker?.removeFromParent()
                gasMarker = nil
                gasPoint = position
            case .battery:
                return
            }
        }

        private func placeWallMarker(kind: PlacementTarget, hit: (position: SIMD3<Float>, normal: SIMD3<Float>)) {
            switch kind {
            case .meter:
                meterWallMarker?.removeFromParent()
                meterWallMarker = nil
                meterWallHit = hit
                meterLock.locked = true
                keyframes.captureNext()
            case .panel:
                panelWallMarker?.removeFromParent()
                panelWallMarker = nil
                panelWallHit = hit
                panelLock.locked = true
                keyframes.captureNext()
            default:
                return
            }
            updateKeyframeGate()
        }

        /// A home has one meter and one panel. Once the asked-for item is locked there is nothing left to find,
        /// so the detector stops instead of boxing random objects for the rest of the session. A redo turns it back on.
        private func updateDetectorGate() {
            equipmentBridge.setEnabled(scanningEquipment && !coachingActive && searchableTarget() != nil)
        }

        /// Scan photos start at the panel lock. Frames from the search before it are mostly ground and sky,
        /// and would spend the frame budget before the look-around.
        private func updateKeyframeGate() {
            let panelLocked = panelWallHit != nil || panelGroundPosition != nil
            keyframes.setEnabled(scanningEquipment && !coachingActive && panelLocked)
        }

        private var worldBoxesHidden = false

        /// Drops cubes left by an earlier placement pass: battery, markers, pad, and transfer box.
        private func hideWorldBoxesIfNeeded() {
            guard !worldBoxesHidden else { return }
            worldBoxesHidden = true
            walkStep = .scan
            let visuals: [Entity?] = [
                batteryRig, meterMarker, meterWallMarker, panelMarker, panelWallMarker,
                gasMarker, workingSpaceOverlay, transferBox, liveLine, reticle, measurementLine
            ]
            for entity in visuals {
                entity?.removeFromParent()
            }
            for marker in measurementMarkers {
                marker.removeFromParent()
            }
            measurementMarkers.removeAll()
            batteryRig = nil
            meterMarker = nil
            meterWallMarker = nil
            panelMarker = nil
            panelWallMarker = nil
            gasMarker = nil
            workingSpaceOverlay = nil
            transferBox = nil
            liveLine = nil
            reticle = nil
            measurementLine = nil
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
            if mode == .battery {
                guard walkStep == .battery, moveBattery(toGroundAt: point) else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                emitGestureEnded()
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
            gasPoint = nil
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
            publishScanFeedback()
            noteLookAround()
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
            if mode == .gasMeter {
                reticle?.isEnabled = false
                hideLiveLine()
                publishLiveFeet(nil)
                return
            }
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
                meterLockSource = nil
                meterWallHit = nil
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
                panelLockSource = nil
                panelWallHit = nil
                panelGroundPosition = nil
                panelMarker?.removeFromParent()
                panelMarker = nil
                panelWallMarker?.removeFromParent()
                panelWallMarker = nil
                scene.panelPosition = nil
                scene.panelWallPosition = nil
                scene.panelWallNormal = nil
                updateKeyframeGate()
            case .battery, .gasMeter:
                return
            }
            updateDetectorGate()
            emit()
        }

        /// A meter or panel lock this close to the other one is a mislabel: they are separate boxes.
        private static let lockSeparationMeters: Float = 0.3
        /// Height above the detected ground where a detected meter or panel may lock. Wider than Base's 6 ft meter
        /// limit on purpose, so a meter mounted too high still locks and the height check shows red.
        private static let equipmentHeightMeters: ClosedRange<Float> = 0.3...2.5
        /// Seconds of searching for one target without a lock before "Mark it myself" shows.
        private static let manualMarkDelaySeconds: CFTimeInterval = 12
        /// A packet older than this (a stalled inference) no longer counts as what the camera sees.
        private static let freshScanSeconds: CFTimeInterval = 1

        private func clearPendingScan() {
            pendingDetections = []
            pendingLandings = [:]
            pendingScan = nil
            scanHint = nil
        }

        /// The latest packet, while it is recent enough to stand for the current view.
        private var freshScan: EquipmentScanFrame? {
            guard let pendingScan, CACurrentMediaTime() - pendingScan.capturedAt < Self.freshScanSeconds else { return nil }
            return pendingScan
        }

        /// YOLO boxes are only the latest frame. A lock stores the wall position and does not leave a square behind.
        private func applyScan(_ packet: EquipmentScanFrame) {
            detectorStatus = packet.status
            guard scanningEquipment, !coachingActive, trackingBlockedMessage == nil else {
                clearPendingScan()
                return
            }
            var best: [EquipmentKind: EquipmentDetection] = [:]
            // Weak boxes still draw. Only boxes at the lock score count toward a lock or a hold.
            // A kind that is already locked has been found; there is only one per home. Its boxes elsewhere are
            // false hits, and letting them win the tie-break below would hide the item still being searched for.
            // A box on the locked item itself is still caught by the separation guard in `lockRejection`.
            for detection in packet.detections where detection.confidence >= EquipmentDetection.drawConfidence {
                let alreadyLocked = detection.kind == .electricMeter ? meterLock.locked : panelLock.locked
                if alreadyLocked { continue }
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
            pendingLandings = [:]
            for (kind, detection) in best {
                if let landing = project(detection, in: packet) {
                    pendingLandings[kind] = landing
                }
            }
            if packet.status == .ok {
                releaseRelockBanIfUnseen(Set(best.keys))
            }
            // Only the object this step is asking for can lock. Both kinds still draw.
            let target = holdLockKind()
            scanHint = hint(for: target, best: best)
            guard let target else { return }
            // A lock needs an unbroken run: a frame without a usable box for the target starts the count over.
            guard let detection = best[target], detection.confidence >= EquipmentDetection.lockConfidence,
                  let landing = pendingLandings[target],
                  relockAllowed(target, point: landing.position),
                  lockRejection(target, at: landing.position, normal: landing.normal, checkHeight: true) == nil else {
                resetStreak(target)
                return
            }
            let sample = EquipmentLock.Sample(point: landing.position, normal: landing.normal)
            let settled: EquipmentLock.Sample?
            switch target {
            case .electricMeter: settled = meterLock.absorb(sample)
            case .breakerPanel: settled = panelLock.absorb(sample)
            }
            guard let settled else { return }
            lockEquipment(target, at: settled, source: .detector)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            emit()
        }

        private func resetStreak(_ kind: EquipmentKind) {
            switch kind {
            case .electricMeter where !meterLock.locked: meterLock = EquipmentLock()
            case .breakerPanel where !panelLock.locked: panelLock = EquipmentLock()
            default: break
            }
        }

        /// Guards every lock path shares (detector, hold, and "Mark it myself"). Nil when the spot may lock.
        /// The height gate is skipped without a ground estimate, and for the user's own mark, so a bad ground
        /// estimate cannot block the only fallback.
        private func lockRejection(
            _ kind: EquipmentKind,
            at point: SIMD3<Float>,
            normal: SIMD3<Float>,
            checkHeight: Bool
        ) -> String? {
            let other = kind == .electricMeter ? panelWallHit : meterWallHit
            let otherTitle = kind == .electricMeter ? "panel" : "meter"
            if let other, simd_distance(other.position, point) < Self.lockSeparationMeters {
                return "That spot is where the \(otherTitle) is marked. Put the dot on the \(kind.title.lowercased())."
            }
            if checkHeight, let ground = groundUnder(point, normal: normal),
               !Self.equipmentHeightMeters.contains(point.y - ground.y) {
                return "That spot isn’t at \(kind.title.lowercased()) height."
            }
            return nil
        }

        private func banRelock(_ kind: EquipmentKind, point: SIMD3<Float>) {
            relockBan = (kind, point)
        }

        /// The cleared object stays banned while its box is still in frame. Aiming 45 cm or more away lifts the ban.
        private func relockAllowed(_ kind: EquipmentKind, point: SIMD3<Float>) -> Bool {
            guard let ban = relockBan, ban.kind == kind else { return true }
            guard simd_distance(ban.point, point) < 0.45 else {
                relockBan = nil
                return true
            }
            return false
        }

        private func releaseRelockBanIfUnseen(_ kinds: Set<EquipmentKind>) {
            guard equipmentBridge.detector.loadError == nil else { return }
            guard let ban = relockBan, !kinds.contains(ban.kind) else { return }
            relockBan = nil
        }

        /// "Not the meter" / "Not the panel", and the call for a "Redo meter" / "Redo panel" menu item: drops that lock
        /// and bans the same spot from relocking right away, so the scan asks for that item again. The battery and the
        /// look-around are measured from the meter wall, so redoing the meter drops them too. A redone panel keeps a
        /// placed battery; its checks rerun once the panel locks again.
        func rejectLock(_ kind: EquipmentKind) {
            let hit = kind == .electricMeter ? meterWallHit : panelWallHit
            clearEquipmentLock(kind == .electricMeter ? .meter : .panel)
            if let hit { banRelock(kind, point: hit.position) }
            resetHold()
            if kind == .electricMeter {
                clearBattery()
                lookAround = LookAround()
                onLookAround?(lookAround)
            }
        }

        /// One short phone-motion cue for the target, from its best box this frame.
        /// No low-score rule: this model scores a meter higher when it is smaller in frame, so "Get closer"
        /// on a low score would push the score down.
        private func hint(for target: EquipmentKind?, best: [EquipmentKind: EquipmentDetection]) -> CoachTip? {
            guard let target, let packet = pendingScan, let detection = best[target] else { return nil }
            let rect = Self.viewRect(for: detection.boundingBox, in: packet)
            let viewArea = max(arView.bounds.width * arView.bounds.height, 1)
            let boxArea = rect.width * rect.height
            if boxArea < viewArea * 0.02 { return .zoomIn }
            if boxArea > viewArea * 0.6 { return .stepBack }
            // Same 32 pt slack as the center-dot hold. A weak box that is centered still gets "Hold still":
            // the hold waits for a lock-score box, and holding still gives the detector more frames.
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            if !rect.insetBy(dx: -32, dy: -32).contains(center) {
                let dx = rect.midX - center.x
                let dy = rect.midY - center.y
                if abs(dy) > abs(dx) { return dy < 0 ? .lookUp : .pointDown }
                return dx < 0 ? .scootLeft : .scootRight
            }
            if pendingLandings[target] == nil { return .aimAtWall }
            return .holdStill
        }

        /// Tells the view about hints, "Mark it myself", and detector trouble. Runs on the display tick, not in a view update.
        private func publishScanFeedback() {
            let now = CACurrentMediaTime()
            let target = searchableTarget()
            if target != searchTarget {
                searchTarget = target
                searchStartedAt = target == nil ? nil : now
                manualMarkOffered = false
            }
            let status: EquipmentObservationStatus = equipmentBridge.detector.loadError != nil ? .modelMissing : detectorStatus
            if target != nil {
                if status != .ok {
                    manualMarkOffered = true
                } else if let searchStartedAt, now - searchStartedAt >= Self.manualMarkDelaySeconds {
                    manualMarkOffered = true
                }
            }
            let live = target != nil && !coachingActive && trackingBlockedMessage == nil && freshScan != nil
            let feedback = ScanFeedback(
                hint: live && status == .ok ? scanHint : nil,
                manualTarget: manualMarkOffered ? target : nil,
                detector: status
            )
            guard feedback != lastScanFeedback else { return }
            lastScanFeedback = feedback
            onScanFeedback?(feedback)
        }

        /// The meter or panel this step asks for while it is still unlocked. Unlike `holdLockKind`, the coaching
        /// overlay does not clear it, so the "Mark it myself" clock keeps running through a tracking hiccup.
        private func searchableTarget() -> EquipmentKind? {
            guard scanningEquipment, let requestedLock else { return nil }
            let locked = requestedLock == .electricMeter ? meterLock.locked : panelLock.locked
            return locked ? nil : requestedLock
        }

        /// "Mark it myself": locks the current target where the center dot sits, with no detector agreement.
        /// Same wall or depth hit as the hold and the same separation guard, then `lockEquipment`, so ground and meter height work.
        func markTargetAtDot() {
            guard let kind = holdLockKind(), kind == searchTarget, manualMarkOffered else { return }
            guard trackingAllowsConfirmation(report: true) else { return }
            let point = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            guard let sample = holdSample(at: point) else {
                onFailure?("Put the dot on the \(kind.title.lowercased()) on the wall and try again.")
                return
            }
            if let reason = lockRejection(kind, at: sample.point, normal: sample.normal, checkHeight: false) {
                onFailure?(reason)
                return
            }
            // The user's own mark overrides an earlier "Not the …" for this kind.
            if relockBan?.kind == kind { relockBan = nil }
            lockEquipment(kind, at: sample, source: .tap)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            emit()
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

        private func lockEquipment(_ kind: EquipmentKind, at sample: EquipmentLock.Sample, source: EquipmentLockSource) {
            let target: PlacementTarget = kind == .electricMeter ? .meter : .panel
            placeWallMarker(kind: target, hit: (position: sample.point, normal: sample.normal))
            let ground = groundUnder(sample.point, normal: sample.normal)
            switch kind {
            case .electricMeter:
                meterGroundPosition = ground
                meterLockSource = source
            case .breakerPanel:
                panelGroundPosition = ground
                panelLockSource = source
            }
            resetHold()
            updateDetectorGate()
        }

        /// Live boxes for both kinds, until that kind locks. A lock is a position, not a box left on the camera.
        private func refreshEquipmentBoxes() {
            guard arView.bounds.width > 1 else { return }
            var items: [EquipmentBoxOverlay.Item] = []
            if scanningEquipment, !coachingActive, trackingBlockedMessage == nil, let packet = freshScan {
                for detection in pendingDetections {
                    let locked = detection.kind == .electricMeter ? meterLock.locked : panelLock.locked
                    if locked { continue }
                    let rect = Self.viewRect(for: detection.boundingBox, in: packet)
                    guard rect.width > 2, rect.height > 2, rect.origin.x.isFinite, rect.origin.y.isFinite else { continue }
                    let onWall = pendingLandings[detection.kind] != nil
                    var title = onWall ? detection.kind.title : "\(detection.kind.title) · not on a wall"
                    #if DEBUG
                    // True detector score, for tuning the draw and lock thresholds on a device.
                    title += String(format: " %.2f", detection.confidence)
                    #endif
                    items.append(EquipmentBoxOverlay.Item(
                        rect: rect,
                        color: onWall ? (detection.kind == .electricMeter ? .systemBlue : .systemIndigo) : .white,
                        title: title
                    ))
                }
            }
            boxOverlay.items = items
        }

        private func holdLockKind() -> EquipmentKind? {
            guard scanningEquipment, !coachingActive, let requestedLock else { return nil }
            let locked = requestedLock == .electricMeter ? meterLock.locked : panelLock.locked
            return locked ? nil : requestedLock
        }

        /// Clears the scan's marks, battery, and look-around. The view also resets the survey's saved placement evidence.
        fileprivate func restartScan() {
            clearBattery()
            clearEquipmentLock(.meter)
            clearEquipmentLock(.panel)
            relockBan = nil
            resetHold()
            clearGasMarker()
            lookAround = LookAround()
            onLookAround?(lookAround)
        }

        fileprivate func skipLookAround() {
            lookAround.movedFarther = true
            lookAround.lookedLeft = true
            lookAround.lookedRight = true
            onLookAround?(lookAround)
        }

        /// After the equipment is locked, one step back and a pan left and right finish the scan. Measured from the
        /// meter wall first, since the battery, pad, and transfer switch sit beside the meter and need mesh there.
        private func noteLookAround() {
            let origin = meterWallHit?.position ?? panelWallHit?.position
            let normal = meterWallHit?.normal ?? panelWallHit?.normal
            guard let origin else { return }
            let camera = arView.cameraTransform.translation
            let forward = -SIMD3<Float>(
                arView.cameraTransform.matrix.columns.2.x,
                arView.cameraTransform.matrix.columns.2.y,
                arView.cameraTransform.matrix.columns.2.z
            )
            var next = lookAround
            let offset = SIMD3<Float>(camera.x - origin.x, 0, camera.z - origin.z)
            let feet = Double(simd_length(offset)) / Double(BatteryGeometry.feetToMeters)
            guard feet >= 8 else { return }
            next.movedFarther = true
            if let forwardFlat = horizontalUnit(forward) {
                var outward = normal.flatMap { horizontalUnit($0) }
                if let current = outward, simd_dot(offset, current) < 0 {
                    outward = -current
                }
                if let outward, let side = horizontalUnit(simd_cross(SIMD3<Float>(0, 1, 0), outward)) {
                    let angle = atan2(simd_dot(forwardFlat, side), simd_dot(forwardFlat, -outward))
                    let sideNear: Float = 40 * .pi / 180
                    let sideFar: Float = 140 * .pi / 180
                    if angle > sideNear && angle < sideFar {
                        next.lookedLeft = true
                    } else if angle < -sideNear && angle > -sideFar {
                        next.lookedRight = true
                    }
                }
            }
            guard next != lookAround else { return }
            lookAround = next
            onLookAround?(next)
        }

        func commitHoldSample() {
            guard let kind = holdLockKind() else { return }
            guard trackingAllowsConfirmation(report: true) else { return }
            let point = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            guard let sample = holdSample(at: point) else {
                onFailure?("Hold the dot on the wall and try again.")
                return
            }
            guard centerAgreesWithDetection(kind), relockAllowed(kind, point: sample.point) else {
                onFailure?("Hold the dot on the \(kind.title.lowercased()).")
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
            // The dot only confirms a detector box under it. Checked first, so no box means no depth copy this tick.
            // Without a working detector the hold never locks; "Mark it myself" is the path then.
            guard trackingBlockedMessage == nil, centerAgreesWithDetection(kind),
                  let sample = holdSample(at: point), relockAllowed(kind, point: sample.point) else {
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
            guard lockRejection(kind, at: sample.point, normal: sample.normal, checkHeight: true) == nil else {
                resetHold()
                return
            }
            guard let settled = holdStreak.absorb(sample) else { return }
            lockEquipment(kind, at: settled, source: .hold)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            emit()
        }

        /// The center dot counts toward a lock only while a lock-score box for this target covers it (32 pt slack).
        private func centerAgreesWithDetection(_ kind: EquipmentKind) -> Bool {
            guard let packet = freshScan else { return false }
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            for detection in pendingDetections
            where detection.kind == kind && detection.confidence >= EquipmentDetection.lockConfidence {
                let rect = Self.viewRect(for: detection.boundingBox, in: packet)
                if rect.insetBy(dx: -32, dy: -32).contains(center) {
                    return true
                }
            }
            return false
        }

        private func resetHold() {
            holdAnchor = nil
            holdSince = nil
            holdStreak = EquipmentLock()
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

        /// "Put it here": the ghost becomes the placed battery, so the snapshot reports it as `batteryPosition`.
        func confirmBatterySpot() {
            guard batteryRig != nil else { return }
            batteryConfirmed = true
            applyTone()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            emitGestureEnded()
        }

        /// "Move it": the placed battery goes back to a ghost at the same spot, ready to slide again.
        func unconfirmBatterySpot() {
            guard batteryConfirmed else { return }
            batteryConfirmed = false
            applyTone()
            emitGestureEnded()
        }

        /// Drops the battery, placed or not, with the slab that hangs off it. The transfer box hides on the next emit.
        private func clearBattery() {
            batteryConfirmed = false
            clearUnconfirmedBattery()
        }

        /// A tap on the ground slides the battery along the meter wall to that spot. When no spot was suggested yet
        /// (no ground found under the meter), the tapped ground gives the height and the battery starts there.
        /// Either way it stays against the meter wall; the tap does not set the meter's own ground or height.
        private func moveBattery(toGroundAt point: CGPoint) -> Bool {
            guard let ground = groundPosition(in: arView, at: point) else {
                onFailure?("Point at the ground beside the meter and tap again.")
                return false
            }
            if var slide = batterySlide {
                slide.along = simd_dot(ground - slide.origin, slide.axis)
                batterySlide = slide
                applyBatterySlide(resetYaw: false)
                return true
            }
            guard let wall = meterWallHit, let outward = horizontalUnit(wall.normal),
                  let axis = unitVector(simd_cross(SIMD3<Float>(0, 1, 0), outward)) else {
                onFailure?("Lock the meter on the wall first.")
                return false
            }
            let origin = SIMD3<Float>(wall.position.x, ground.y, wall.position.z)
            batterySlide = BatterySlide(
                origin: origin,
                outward: outward,
                axis: axis,
                groundY: ground.y,
                along: simd_dot(ground - origin, axis)
            )
            applyBatterySlide(resetYaw: true)
            return true
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
            // The gas mark is a point now (`gasPoint`); `gasMarker` is only left over from older scenes.
            if let gas = gasPoint ?? gasMarker?.position(relativeTo: nil),
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
            // A position no lock recorded came from the older tap-to-mark paths, which are the user's own mark.
            snapshot.meterLockSource = snapshot.meterPosition == nil ? nil : (meterLockSource ?? .tap)
            snapshot.panelLockSource = snapshot.panelPosition == nil ? nil : (panelLockSource ?? .tap)
            if let gasPoint {
                snapshot.gasMeterPosition = PlacementAnchor(gasPoint)
            } else if let gasMarker {
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
            // Same pass / conflict / unknown colors as the battery tone.
            let color: UIColor
            switch placementMeasurer.measure(snapshot).transferSwitchClearanceObserved {
            case true: color = ToneStyle.uiColor(.clear)
            case false: color = ToneStyle.uiColor(.conflict)
            case nil: color = ToneStyle.uiColor(.incomplete)
            }
            transferBox.model?.materials = [UnlitMaterial(color: color.withAlphaComponent(0.35))]
        }

        /// One point per face, with its class. The camera does not draw these faces.
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
            /// ARKit's own label for the face, kept raw for `scene.ply`. Nil when the device does not classify.
            func rawClass(_ face: Int) -> UInt8? {
                guard let source = geometry.classification, face < source.count else { return nil }
                let pointer = source.buffer.contents().advanced(by: source.offset + face * source.stride)
                return pointer.load(as: UInt8.self)
            }
            func surfaceClass(_ face: Int) -> MeshSurfaceClass {
                guard let raw = rawClass(face) else { return .other }
                switch ARMeshClassification(rawValue: Int(raw)) {
                case .floor: return .floor
                case .wall, .door: return .wall
                case .window: return .window
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
            let colors = cache.colors(anchor: mesh.identifier, local: positions, world: worldPositions, frame: frame)
                .map { $0 ?? SIMD3<UInt8>(200, 200, 200) }
            var triangles: [UInt32] = []
            triangles.reserveCapacity(faceCount * 3)
            var faceLabels: [UInt8] = []
            faceLabels.reserveCapacity(faceCount)

            var samples: [ClassifiedMeshSample] = []
            let sampleStride = 2
            samples.reserveCapacity(faceCount / sampleStride + 1)

            for face in 0..<faceCount {
                let base = face * faces.indexCountPerPrimitive
                let i0 = faceVertexIndex(base)
                let i1 = faceVertexIndex(base + 1)
                let i2 = faceVertexIndex(base + 2)
                guard i0 < vertexCount, i1 < vertexCount, i2 < vertexCount else { continue }
                let label = surfaceClass(face)
                triangles.append(contentsOf: [UInt32(i0), UInt32(i1), UInt32(i2)])
                faceLabels.append(rawClass(face) ?? PointCloudPLY.unlabeledFace)
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
                cloud: MeshPointCloudChunk(positions: worldPositions, colors: colors, triangles: triangles, faceLabels: faceLabels)
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

/// Real camera colors for exported mesh vertices, so a surface seen once keeps its color after the camera
/// turns away. Cells are in each mesh anchor's own space: ARKit keeps nudging anchor transforms to correct
/// drift, and world-space cells would miss after every nudge. Re-meshing moves vertices a little, so a miss
/// falls back to the neighboring cells. A fresh camera sample runs at most twice a second per anchor.
final class MeshColorCache: Sendable {
    private let anchors = OSAllocatedUnfairLock<[UUID: [SIMD3<Int32>: SIMD3<UInt8>]]>(initialState: [:])
    private let lastSample = OSAllocatedUnfairLock<[UUID: CFTimeInterval]>(initialState: [:])
    private static let cellSize: Float = 0.04
    private static let neighbors: [SIMD3<Int32>] = (-1...1).flatMap { x in
        (-1...1).flatMap { y in (-1...1).map { z in SIMD3<Int32>(Int32(x), Int32(y), Int32(z)) } }
    }

    /// Nil where the point has never been visible to the camera.
    func colors(anchor: UUID, local: [SIMD3<Float>], world: [SIMD3<Float>], frame: ARFrame?) -> [SIMD3<UInt8>?] {
        let now = CACurrentMediaTime()
        let shouldSample = lastSample.withLock { times -> Bool in
            guard now - (times[anchor] ?? 0) >= 0.5 else { return false }
            times[anchor] = now
            return true
        }
        let sampled = (shouldSample ? frame.map { Self.sample(world, in: $0) } : nil) ?? []
        return anchors.withLock { anchors in
            var cells = anchors[anchor] ?? [:]
            defer { anchors[anchor] = cells }
            return local.indices.map { index in
                let key = SIMD3<Int32>((local[index] / Self.cellSize).rounded(.down))
                if index < sampled.count, let rgb = sampled[index] {
                    cells[key] = rgb
                    return rgb
                }
                if let rgb = cells[key] { return rgb }
                guard !sampled.isEmpty else { return nil }
                for offset in Self.neighbors {
                    if let rgb = cells[key &+ offset] { return rgb }
                }
                return nil
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
                if measured > 0, abs(measured - z) > 0.15 + 0.05 * z { return nil }
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
