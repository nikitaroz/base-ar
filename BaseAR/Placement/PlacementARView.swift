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

/// One phone-motion cue for the bottom feedback line, drawn as an animated SF Symbol plus kid copy.
/// The raw value is the copy, so tracking text from the session maps back to its graphic. Copy never carries a distance.
private enum CoachTip: String {
    case lookUp = "Look up at it"
    case pointDown = "Point your phone down"
    case stepBack = "Take a few steps back"
    case turnAlongWall = "Turn to look along the wall"
    case scootLeft = "Scoot left"
    case scootRight = "Scoot right"
    case zoomIn = "Get closer"
    case aimAtWall = "Aim at the wall"
    case holdStill = "Hold still"
    case slowDown = "Slow down"
    case moveSlowly = "Move the phone slowly"
    case moreDetail = "Aim at something with more detail"
    case paused = "Paused"
    case aimDot = "Aim the dot, then tap +"
    case slideToWall = "Slide it closer to the wall"
    case dragBattery = "Drag to move, then tap Next"
    case tapNext = "Tap Next"
    case located = "Located"
    case scanned = "Scanned"

    var symbol: String {
        switch self {
        case .lookUp: "arrow.up.circle.fill"
        case .pointDown: "arrow.down.circle.fill"
        case .stepBack: "figure.walk.motion"
        case .turnAlongWall: "arrow.triangle.2.circlepath"
        case .scootLeft: "arrow.left.circle.fill"
        case .scootRight: "arrow.right.circle.fill"
        case .zoomIn: "plus.magnifyingglass"
        case .aimAtWall: "viewfinder"
        case .holdStill: "hand.raised.fill"
        case .slowDown: "tortoise.fill"
        case .moveSlowly: "iphone.gen3.radiowaves.left.and.right"
        case .moreDetail: "sparkle.magnifyingglass"
        case .paused: "pause.circle.fill"
        case .aimDot: "plus.circle.fill"
        case .slideToWall: "hand.draw.fill"
        case .dragBattery: "hand.draw.fill"
        case .tapNext: "checkmark.circle.fill"
        case .located, .scanned: "checkmark.seal.fill"
        }
    }

    /// Motion cues keep pulsing so the phone movement reads at a glance. Confirmations do not.
    var pulses: Bool {
        switch self {
        case .located, .scanned, .tapNext, .paused: false
        default: true
        }
    }
}

/// Walk back from a locked meter or panel, then pan so the mesh sees the wall.
/// One step is about 2.5 ft. The wide look is done only after the distance and the three views.
private struct ScanGuide: Equatable {
    var meterSteps: Int = 0
    var panelSteps: Int = 0
    var meterLookedLeft = false
    var meterLookedRight = false
    var meterLookedAlong = false
    var panelLookedLeft = false
    var panelLookedRight = false
    var panelLookedAlong = false
    /// Sectors of camera yaw used when a lock has no wall normal.
    var meterFallbackSectors: UInt8 = 0
    var panelFallbackSectors: UInt8 = 0
    /// True once the meter distance and the left, right, and along-wall views are all done.
    var meterWideLookDone: Bool = false
    /// The panel locked only after that wide look, so the area around the box still needs its own step-back.
    var panelWalkNeeded: Bool = false

    static let wideLookSteps = 10
    /// Side views count once the phone is a few steps out, so a spin against the wall does not finish the look.
    static let lookMinFeet = 7.5

    var meterViewsReady: Bool { meterLookedLeft && meterLookedRight && meterLookedAlong }
    var panelViewsReady: Bool { panelLookedLeft && panelLookedRight && panelLookedAlong }
    var meterSurroundDone: Bool { meterSteps >= Self.wideLookSteps && meterViewsReady }
    var panelSurroundDone: Bool { panelSteps >= Self.wideLookSteps && panelViewsReady }
}

/// Kept so the battery preview code can stay idle. This screen never leaves `.scan`.
private enum WalkStep: Equatable {
    case scan
    case gas
    case battery
    case finish
}

private enum ScanCue {
    case findMeter
    case stepBack
    case findPanel
    case stepBackFromPanel
    case ready
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
    @State private var yawRadians: Float
    @State private var scene: PlacementSceneSnapshot
    @State private var guide: ScanGuide
    @State private var screenshotToken: UUID? = nil
    /// Set while a save waits for its screenshot. Cleared when it advances, so the view can save again after Back.
    @State private var pendingSave: PlacementSaveRequest? = nil
    /// A successful handoff keeps its durable packet even if AR updates before disappearance.
    @State private var departingAfterCapture = false
    @State private var statusMessage: String? = nil
    @State private var trackingMessage: String? = nil
    @State private var equipmentTip: CoachTip? = nil
    /// Located or Scanned for a moment after a lock or a finished look-around.
    @State private var flashTip: CoachTip? = nil
    @State private var isVisible = false
    @State private var coachingIsActive = false
    /// When false, the AR view stays minimal (chip picker + Measure button). Flip true to reveal the guided walkthrough.
    @State private var measureMode: Bool = true
    @State private var step: WalkStep
    @State private var manualMark: PlacementTarget? = nil
    @State private var liveFeetText: String? = nil
    @State private var hasStartedAR = true

    init(store: SurveyStore, onContinue: @escaping () -> Void) {
        self.store = store
        self.onContinue = onContinue
        let existing = store.placementController
        _scene = State(initialValue: existing?.scene ?? PlacementSceneSnapshot())
        _guide = State(initialValue: existing?.scanGuide ?? ScanGuide())
        _yawRadians = State(initialValue: existing?.yawRadians ?? 0)
        _step = State(initialValue: existing?.hasChosenWalkStep == true ? (existing?.walkStep ?? .scan) : .scan)
    }

    private var isSaving: Bool { pendingSave != nil }
    
    private let progressSteps: [WalkStep] = [.scan, .gas, .battery, .finish]

    private var arSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    /// Meter, then panel, then the look-around. A panel found first shares the meter's look-around.
    private var cue: ScanCue {
        if !meterIsMarked { return .findMeter }
        if !panelIsMarked { return .findPanel }
        if !guide.meterSurroundDone { return .stepBack }
        if guide.panelWalkNeeded && !guide.panelSurroundDone { return .stepBackFromPanel }
        return .ready
    }

    /// The one job for the current step. Changes only when that job is done.
    private var taskLine: String {
        switch step {
        case .scan:
            switch manualMark {
            case .meter: return "Mark the meter"
            case .panel: return "Mark the breaker panel"
            case nil, .battery, .gasMeter: break
            }
            switch cue {
            case .findMeter: return "Find the meter"
            case .findPanel: return "Find the breaker panel"
            case .stepBack: return "Look around the meter"
            case .stepBackFromPanel: return "Look around the panel"
            case .ready: return "All found"
            }
        case .gas: return "Find the gas meter"
        case .battery: return "Place the battery"
        case .finish: return "Save your scan"
        }
    }

    /// Phone-motion cue from the scan guide and wall check, for when the detector has nothing to say.
    private var motionTip: CoachTip? {
        switch step {
        case .scan:
            switch manualMark {
            case .meter: return meterIsMarked ? .tapNext : .aimDot
            case .panel: return panelIsMarked ? .tapNext : .aimDot
            case nil, .battery, .gasMeter: break
            }
            switch cue {
            case .findMeter, .findPanel: return .lookUp
            case .stepBack:
                return surroundTip(steps: guide.meterSteps, left: guide.meterLookedLeft,
                                   right: guide.meterLookedRight, along: guide.meterLookedAlong)
            case .stepBackFromPanel:
                return surroundTip(steps: guide.panelSteps, left: guide.panelLookedLeft,
                                   right: guide.panelLookedRight, along: guide.panelLookedAlong)
            case .ready: return .tapNext
            }
        case .gas:
            return scene.gasMeterPosition == nil ? .aimDot : .tapNext
        case .battery:
            guard scene.batteryPosition != nil else { return .pointDown }
            if let wallFeet = scene.automaticWallClearanceFeet, wallFeet > BaseRuleSet.maxWallDistanceFeet {
                return .slideToWall
            }
            return .dragBattery
        case .finish:
            return nil
        }
    }

    private func surroundTip(steps: Int, left: Bool, right: Bool, along: Bool) -> CoachTip {
        if steps < ScanGuide.wideLookSteps { return .stepBack }
        if !along { return .turnAlongWall }
        if !left { return .scootLeft }
        if !right { return .scootRight }
        return .stepBack
    }

    private struct Feedback: Equatable {
        let text: String
        let symbol: String
        let tint: Color
        let pulses: Bool

        init(_ tip: CoachTip, tint: Color = .blue) {
            text = tip.rawValue
            symbol = tip.symbol
            self.tint = tint
            pulses = tip.pulses
        }

        init(text: String, symbol: String, tint: Color) {
            self.text = text
            self.symbol = symbol
            self.tint = tint
            pulses = false
        }
    }

    /// One bottom line at a time: errors, then tracking, then a fresh find, then the detector, then motion.
    private var feedback: Feedback? {
        if let statusMessage {
            return Feedback(text: statusMessage, symbol: "exclamationmark.octagon.fill", tint: .red)
        }
        if let trackingMessage {
            return CoachTip(rawValue: trackingMessage).map { Feedback($0, tint: .orange) }
                ?? Feedback(text: trackingMessage, symbol: "exclamationmark.triangle.fill", tint: .orange)
        }
        if let flashTip { return Feedback(flashTip, tint: .green) }
        if let equipmentTip { return Feedback(equipmentTip) }
        if let motionTip { return Feedback(motionTip) }
        return nil
    }

    /// Center-dot lock only while the prompt is asking for one object. Stepping back should not lock a random wall.
    private var holdTarget: EquipmentKind? {
        switch cue {
        case .findMeter: .electricMeter
        case .findPanel: .breakerPanel
        case .stepBack, .stepBackFromPanel, .ready: nil
        }
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
        // A new/paused live scan must not display an older capture's passing assessment.
        store.assessment(applying: scene)
    }

    var body: some View {
        Group {
            if arSupported {
                arScreen
            } else {
                unsupportedScreen
            }
        }
        .onAppear {
            guard arSupported, hasStartedAR else { return }
            departingAfterCapture = false
            isVisible = true
            let controller = store.requirePlacementController()
            controller.hidePlacedBoxes()
            controller.resume()
            scene = controller.scene
            guide = controller.scanGuide
            yawRadians = controller.yawRadians
        }
        .onDisappear {
            isVisible = false
            cancelPendingSave()
            if !departingAfterCapture { commitLiveScene() }
            store.placementController?.pauseIfIdle()
        }
        .onChange(of: scenePhase) { _, phase in
            guard isVisible, arSupported else { return }
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
            liveFeetText = nil
            if new != .scan {
                manualMark = nil
            }
        }
        .onChange(of: meterIsMarked) { _, found in
            if found { flashTip = .located }
        }
        .onChange(of: panelIsMarked) { _, found in
            if found { flashTip = .located }
        }
        .onChange(of: guide.meterSurroundDone) { _, done in
            if done { flashTip = .scanned }
        }
        .onChange(of: guide.panelSurroundDone) { _, done in
            if done { flashTip = .scanned }
        }
        .task(id: flashTip) {
            guard flashTip != nil, (try? await Task.sleep(for: .seconds(1.5))) != nil else { return }
            flashTip = nil
        }
        // One line is shared, so an old error must not hide live feedback for long.
        .task(id: statusMessage) {
            guard statusMessage != nil, (try? await Task.sleep(for: .seconds(4))) != nil else { return }
            statusMessage = nil
        }
    }

    private var arScreen: some View {
        let tone = liveAssessment.placementTone
        return VStack(spacing: 0) {
            ZStack {
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
                        holdTarget: holdTarget,
                        yawRadians: yawRadians,
                        tone: tone,
                        screenshotToken: screenshotToken,
                        onSceneChange: acceptScene,
                        onYawChange: {
                            departingAfterCapture = false
                            yawRadians = $0
                        },
                        onLiveFeet: acceptLiveFeet,
                        onGuide: { guide = $0 },
                        onScreenshot: handleScreenshot,
                        onFailure: { statusMessage = $0 },
                        onTrackingStatus: { trackingMessage = $0 },
                        onEquipmentStatus: { equipmentTip = $0 },
                        onCoachingActiveChange: { coachingIsActive = $0 }
                    )
                }
                if !coachingIsActive {
                    VStack {
                        taskLineView
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        Spacer()
                    }
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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

    /// Animated SF Symbol plus kid copy, one cue at a time. Height stays fixed so the buttons do not jump.
    private var feedbackLine: some View {
        HStack(spacing: 12) {
            if let feedback {
                Image(systemName: feedback.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(feedback.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: feedback.pulses)
                    .symbolEffect(.bounce, value: feedback.symbol)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                Text(feedback.text)
                    .font(.headline)
                    .foregroundStyle(feedback.tint == .red ? Color.red : Color.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .animation(.easeInOut(duration: 0.2), value: feedback)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var taskLineView: some View {
        Text(taskLine)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .animation(.easeInOut(duration: 0.25), value: taskLine)
            .accessibilityAddTraits(.isHeader)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            feedbackLine
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
                .disabled(cue != .ready)
            if let missedTarget {
                Button(missedTarget == .meter ? "Mark meter yourself" : "Mark panel yourself") {
                    manualMark = missedTarget
                }
                .font(.footnote)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            Button("Skip for now") {
                cancelPendingSave()
                commitLiveScene()
                onContinue()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var finishControls: some View {
        VStack(spacing: 12) {
            // Simple status summary
            VStack(spacing: 8) {
                ForEach(placementStatusItems, id: \.title) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .foregroundStyle(item.color)
                            .font(.body)
                        Text(item.title)
                            .font(.body)
                        Spacer()
                        if item.isGood {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if item.needsAttention {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(.vertical, 8)

            // Primary actions
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

            Text("This is a preliminary survey, not an install measurement.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private struct StatusItem {
        let icon: String
        let title: String
        let color: Color
        let isGood: Bool
        let needsAttention: Bool
    }

    private var placementStatusItems: [StatusItem] {
        var items: [StatusItem] = []

        // Meter distance check
        let meterMeasurement = scene.confirmedMeasurements.first { $0.kind == .batteryToMeter }
        if let meterDist = meterMeasurement?.distanceFeet {
            let isGood = meterDist <= 20
            items.append(StatusItem(
                icon: "bolt.circle",
                title: isGood ? "Good meter distance" : "Meter is a bit far",
                color: isGood ? .green : .orange,
                isGood: isGood,
                needsAttention: !isGood
            ))
        } else if scene.meterPosition != nil || scene.meterWallPosition != nil {
            items.append(StatusItem(
                icon: "bolt.circle",
                title: "Meter marked",
                color: .secondary,
                isGood: false,
                needsAttention: false
            ))
        } else {
            items.append(StatusItem(
                icon: "bolt.circle",
                title: "Need meter location",
                color: .orange,
                isGood: false,
                needsAttention: true
            ))
        }

        // Wall distance check
        let wallMeasurement = scene.confirmedMeasurements.first { $0.kind == .batteryToWall }
        if let wallDist = wallMeasurement?.distanceFeet {
            let isGood = wallDist <= 1.5
            items.append(StatusItem(
                icon: "square.on.square",
                title: isGood ? "Close to wall" : "Check wall distance",
                color: isGood ? .green : .orange,
                isGood: isGood,
                needsAttention: !isGood
            ))
        } else if scene.automaticWallClearanceFeet != nil {
            items.append(StatusItem(
                icon: "square.on.square",
                title: "Checking wall distance",
                color: .secondary,
                isGood: false,
                needsAttention: false
            ))
        }

        // Gas meter check
        if store.session.placement.gasMeterNotPresent {
            items.append(StatusItem(
                icon: "flame.circle",
                title: "No gas meter nearby",
                color: .green,
                isGood: true,
                needsAttention: false
            ))
        } else {
            let gasMeasurement = scene.confirmedMeasurements.first { $0.kind == .batteryToGasMeter }
            if let gasDist = gasMeasurement?.distanceFeet {
                let isGood = gasDist >= 3
                items.append(StatusItem(
                    icon: "flame.circle",
                    title: isGood ? "Safe from gas meter" : "Too close to gas meter",
                    color: isGood ? .green : .red,
                    isGood: isGood,
                    needsAttention: !isGood
                ))
            } else if scene.gasMeterPosition != nil {
                items.append(StatusItem(
                    icon: "flame.circle",
                    title: "Gas meter marked",
                    color: .secondary,
                    isGood: false,
                    needsAttention: false
                ))
            }
        }

        // Footprint clearance
        let footprintClear = scene.footprintIsClear ?? store.session.placement.footprintClearAttested
        if let clear = footprintClear {
            items.append(StatusItem(
                icon: "square.dashed",
                title: clear ? "Footprint looks clear" : "Check footprint clearance",
                color: clear ? .green : .orange,
                isGood: clear,
                needsAttention: !clear
            ))
        }

        // Transfer switch space
        let transferSwitchSpace = scene.transferSwitchClearanceObserved ?? store.session.placement.transferSwitchSpaceAttested
        if let hasSpace = transferSwitchSpace {
            items.append(StatusItem(
                icon: "circle.grid.cross",
                title: hasSpace ? "Transfer switch space noted" : "Check transfer switch space",
                color: hasSpace ? .green : .orange,
                isGood: hasSpace,
                needsAttention: !hasSpace
            ))
        }

        return items
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
                description: Text("Use a physical iPhone to scan the meter and the area around it. You can complete the other survey sections here.")
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

    /// Kept for measurement bookkeeping only; feet are never shown on screen.
    private func acceptLiveFeet(_ feet: Double?) {
        let text = feet.map(formatFeet)
        guard liveFeetText != text else { return }
        liveFeetText = text
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
            statusMessage = "Place the battery preview before saving."
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

private struct EquipmentLock {
    struct Sample {
        var point: SIMD3<Float>
        var normal: SIMD3<Float>
        var normalIsMeasured: Bool = true
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
        return Sample(point: point, normal: normal, normalIsMeasured: samples.allSatisfy(\.normalIsMeasured))
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
    var holdTarget: EquipmentKind?
    var yawRadians: Float
    var tone: PlacementTone
    var screenshotToken: UUID?
    var onSceneChange: (PlacementSceneSnapshot) -> Void
    var onYawChange: (Float) -> Void
    var onLiveFeet: (Double?) -> Void
    var onGuide: (ScanGuide) -> Void
    var onScreenshot: @MainActor (UUID, UIImage?) -> Void
    var onFailure: (String) -> Void
    var onTrackingStatus: (String?) -> Void
    var onEquipmentStatus: (CoachTip?) -> Void
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
            holdTarget: holdTarget,
            yawRadians: yawRadians,
            tone: tone,
            screenshotToken: screenshotToken,
            onSceneChange: onSceneChange,
            onYawChange: onYawChange,
            onLiveFeet: onLiveFeet,
            onGuide: onGuide,
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
    var cloud: MeshPointCloudChunk?
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
    var hasChosenWalkStep = false
    fileprivate private(set) var scanGuide = ScanGuide()
    private var holdTarget: EquipmentKind?

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
    private var onEquipmentStatus: ((CoachTip?) -> Void)?
    private var lastEquipmentTip: CoachTip?
    private var lastEquipmentGeneration: UInt64?
    private var onCoachingActiveChange: ((Bool) -> Void)?
    private var onGuide: ((ScanGuide) -> Void)?
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
        /// World-space mesh kept for `scene.ply`. Separate from the on-screen draw, which stays in anchor space.
        private var meshClouds: [UUID: MeshPointCloudChunk] = [:]
        var meshVisuals: [UUID: AnchorEntity] = [:]
        fileprivate var pendingMeshDraws: [UUID: MeshDrawBuffers] = [:]
        var lastMeshDraw = Date.distantPast
        var transferBox: ModelEntity?
        var trackingBlockedMessage: String? = CoachTip.holdStill.rawValue
        private let trackingNotice = OSAllocatedUnfairLock<String?>(initialState: CoachTip.holdStill.rawValue)
        nonisolated let equipmentBridge = EquipmentScanBridge()
        /// Camera colors for `scene.ply`, remembered per world cell across mesh updates.
        nonisolated let meshColors = MeshColorCache()
        private let boxOverlay = EquipmentBoxOverlay(frame: .zero)
        private var meterGroundPosition: SIMD3<Float>?
        private var panelGroundPosition: SIMD3<Float>?
        private var meterLock = EquipmentLock()
        private var panelLock = EquipmentLock()
        private var pendingDetections: [EquipmentDetection] = []
        private var pendingScan: EquipmentScanFrame?
        /// Latest bottom-line hint while finding the meter or panel.
        private var scanHint: CoachTip?
        private var holdAnchor: SIMD3<Float>?
        private var holdSince: CFTimeInterval?
        /// After Clear, the same spot cannot lock again until the phone looks away or aims somewhere else.
        private var relockBan: (kind: EquipmentKind, point: SIMD3<Float>)?
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
            holdTarget: EquipmentKind?,
            yawRadians: Float,
            tone: PlacementTone,
            screenshotToken: UUID?,
            onSceneChange: @escaping (PlacementSceneSnapshot) -> Void,
            onYawChange: @escaping (Float) -> Void,
            onLiveFeet: @escaping (Double?) -> Void,
            onGuide: @escaping (ScanGuide) -> Void,
            onScreenshot: @escaping @MainActor (UUID, UIImage?) -> Void,
            onFailure: @escaping (String) -> Void,
            onTrackingStatus: @escaping (String?) -> Void,
            onEquipmentStatus: @escaping (CoachTip?) -> Void,
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
            self.holdTarget = holdTarget
            let startedScanning = scanning && !scanningEquipment
            scanningEquipment = scanning
            equipmentBridge.setEnabled(isRunning && scene.trackingIsNormal && scanning && !coachingActive)
            if !scanning {
                pendingDetections = []
                pendingScan = nil
                refreshEquipmentBoxes()
            }
            self.onSceneChange = onSceneChange
            self.onYawChange = onYawChange
            self.onLiveFeet = onLiveFeet
            self.onGuide = onGuide
            self.onScreenshot = onScreenshot
            self.onFailure = onFailure
            self.onTrackingStatus = onTrackingStatus
            self.onEquipmentStatus = onEquipmentStatus
            self.onCoachingActiveChange = onCoachingActiveChange
            if startedScanning, !reportedScanLoadError, let loadError = equipmentBridge.detector.loadError {
                reportedScanLoadError = true
                self.onFailure?("Equipment scan isn’t available (\(loadError)). Hold the dot on the meter or panel.")
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
            setTrackingMessage(CoachTip.holdStill.rawValue)
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
            setTrackingMessage(CoachTip.paused.rawValue)
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
                self.holdReticle.isHidden = true
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
            
            if tone == .conflict {
                batteryBody?.model?.materials = [UnlitMaterial(color: color.withAlphaComponent(0.15))]
            } else {
                batteryBody?.model?.materials = [SimpleMaterial(color: color, isMetallic: false)]
            }
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

        /// Nil without a LiDAR mesh, so Review's scene.ply wording matches what is shared.
        func pointCloudPLYData() -> Data? {
            guard hasExportableMesh else { return nil }
            return PointCloudPLY.data(from: Array(meshClouds.values))
        }

        var hasExportableMesh: Bool {
            meshClouds.values.contains { !$0.positions.isEmpty }
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
            if scanHidesPlacementVisuals {
                hidePlacementVisuals()
            }
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
            upsertMesh(from: anchors, frame: session.currentFrame)
        }

        nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            upsertPlanes(from: anchors)
            upsertMesh(from: anchors, frame: session.currentFrame)
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

        private nonisolated func upsertMesh(from anchors: [ARAnchor], frame: ARFrame? = nil) {
            let epoch = callbackEpoch.withLock { $0 }
            let samples = Self.classifiedMeshes(from: anchors, frame: frame, colors: meshColors)
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
                    self.meshClouds.removeValue(forKey: id)
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
                if let cloud = update.cloud {
                    meshClouds[update.id] = cloud
                }
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

            // Battery placement preview completely removed from live scan UI
            // Position tracking remains for measurement calculations
            footprintPad = nil
            batteryBody = nil
            batteryFaceMark = nil
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
            // Battery placement preview completely removed from live scan UI
            // Auto-placement disabled
            return
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
            case .battery, .gasMeter:
                return
            }
        }

        /// Hides the battery, footprint, and equipment cubes for this scan. Locks and saved positions stay put,
        /// so leaving the screen does not wipe a placement already stored on the scene.
        private var scanHidesPlacementVisuals = false

        func hidePlacedBoxes() {
            scanHidesPlacementVisuals = true
            hidePlacementVisuals()
            boxOverlay.items = []
        }

        private func hidePlacementVisuals() {
            let visuals: [Entity?] = [
                batteryRig, meterMarker, meterWallMarker, panelMarker, panelWallMarker,
                gasMarker, workingSpaceOverlay, transferBox, liveLine, reticle
            ]
            for entity in visuals {
                entity?.isEnabled = false
            }
            for marker in measurementMarkers {
                marker.isEnabled = false
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
            updateEquipmentStatus()
            if let packet = equipmentBridge.takeLatest() {
                applyScan(packet)
            }
            refreshEquipmentBoxes()
            noteSurroundingProgress()
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

        private func publishEquipmentStatus(_ tip: CoachTip?) {
            guard tip != lastEquipmentTip else { return }
            lastEquipmentTip = tip
            onEquipmentStatus?(tip)
        }

        private func updateEquipmentStatus() {
            guard scanningEquipment, isRunning, !coachingActive else {
                clearTransientEquipmentObservations()
                scanHint = nil
                publishEquipmentStatus(nil)
                return
            }
            // The bridge does not report per-frame status yet, so the hint from the last frame is the status.
            guard let observation = equipmentBridge.latestObservation else {
                publishEquipmentStatus(holdLockKind() == nil ? nil : scanHint)
                return
            }
            if observation.generation != lastEquipmentGeneration {
                clearTransientEquipmentObservations()
                lastEquipmentGeneration = observation.generation
            }
            switch observation.status {
            case .success:
                publishEquipmentStatus(holdLockKind() == nil ? nil : scanHint)
            case .noDetections:
                clearTransientEquipmentObservations()
                publishEquipmentStatus(holdLockKind() == nil ? nil : .lookUp)
            case .modelUnavailable, .inferenceFailed, .frameUnavailable:
                clearTransientEquipmentObservations()
                publishEquipmentStatus(nil)
            }
        }

        /// Boxes stay on the camera. A hit counts toward a lock only after it lands on a wall or, failing that, LiDAR depth.
        private func applyScan(_ packet: EquipmentScanFrame) {
            guard isRunning, scanningEquipment, !coachingActive, trackingAllowsConfirmation(report: false) else {
                pendingDetections = []
                pendingScan = nil
                scanHint = nil
                boxOverlay.items = []
                return
            }
            var best: [EquipmentKind: EquipmentDetection] = [:]
            for detection in packet.detections where detection.confidence >= 0.25 {
                if let existing = best[detection.kind], existing.confidence >= detection.confidence { continue }
                best[detection.kind] = detection
            }
            // The box overlay and the center-dot hold both read the latest frame.
            pendingScan = packet
            pendingDetections = Array(best.values)
            // A lock requires a continuous run of usable observations, not unrelated
            // hits accumulated across a failure, absence or generation change.
            if best[.electricMeter] == nil, !meterLock.locked { meterLock = EquipmentLock() }
            if best[.breakerPanel] == nil, !panelLock.locked { panelLock = EquipmentLock() }
            scanHint = hint(for: holdTarget, best: best, packet: packet)
            var lockedSomething = false
            // Weak boxes still draw, but only confident ones count toward a lock.
            // Stepping back leaves holdTarget nil, so a box in view cannot lock a random wall.
            for detection in best.values where detection.confidence >= 0.5 && detection.kind == holdTarget {
                let alreadyLocked = detection.kind == .electricMeter ? meterLock.locked : panelLock.locked
                guard !alreadyLocked, let landing = project(detection, in: packet) else { continue }
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
            if lockedSomething {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                emit()
            }
        }

        /// One short phone-motion line for the target being searched, from the detector box and wall hit.
        private func hint(
            for target: EquipmentKind?,
            best: [EquipmentKind: EquipmentDetection],
            packet: EquipmentScanFrame
        ) -> CoachTip? {
            guard let target, equipmentBridge.detector.loadError == nil else { return nil }
            let locked = target == .electricMeter ? meterLock.locked : panelLock.locked
            guard !locked else { return nil }
            guard let detection = best[target] else { return .lookUp }
            let rect = Self.viewRect(for: detection.boundingBox, in: packet)
            let viewArea = max(arView.bounds.width * arView.bounds.height, 1)
            let boxArea = rect.width * rect.height
            if detection.confidence < 0.5 || boxArea < viewArea * 0.02 { return .zoomIn }
            if boxArea > viewArea * 0.6 { return .stepBack }
            // Same slack as the center-dot hold, so "Hold still" only shows when a hold can lock.
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            if !rect.insetBy(dx: -32, dy: -32).contains(center) {
                let dx = rect.midX - center.x
                let dy = rect.midY - center.y
                if abs(dy) > abs(dx) { return dy < 0 ? .lookUp : .pointDown }
                return dx < 0 ? .scootLeft : .scootRight
            }
            if project(detection, in: packet) == nil { return .aimAtWall }
            return .holdStill
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
            guard let depth = packet.depth else { return nil }
            return depthPatch(
                at: pixel,
                depth: depth,
                imageSize: packet.imageSize,
                intrinsics: packet.intrinsics,
                cameraTransform: packet.cameraTransform,
                cameraOrigin: cameraOrigin
            )
        }

        private func relockAllowed(_ kind: EquipmentKind, point: SIMD3<Float>) -> Bool {
            guard let ban = relockBan, ban.kind == kind else { return true }
            guard simd_distance(ban.point, point) < 0.45 else {
                relockBan = nil
                return true
            }
            return false
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

        /// Live detector boxes only. A lock is a position, not a cube left in the scene.
        private func refreshEquipmentBoxes() {
            guard arView.bounds.width > 1 else { return }
            var items: [EquipmentBoxOverlay.Item] = []
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

        private func holdLockKind() -> EquipmentKind? {
            guard scanningEquipment, !coachingActive, let holdTarget else { return nil }
            let locked = holdTarget == .electricMeter ? meterLock.locked : panelLock.locked
            return locked ? nil : holdTarget
        }

        /// Counts steps back from the locked meter, then from the panel when that area still needs a look.
        /// Distance alone does not finish the look: the camera also has to pan left, right, and along the wall.
        private func noteSurroundingProgress() {
            let camera = arView.cameraTransform.translation
            let forward = Self.cameraForward(arView.cameraTransform.matrix)
            var next = scanGuide
            if meterLock.locked, let origin = meterWallHit?.position ?? meterGroundPosition {
                next.meterSteps = max(next.meterSteps, Self.backupSteps(from: origin, to: camera))
                Self.noteLook(
                    left: &next.meterLookedLeft,
                    right: &next.meterLookedRight,
                    along: &next.meterLookedAlong,
                    fallbackSectors: &next.meterFallbackSectors,
                    origin: origin,
                    wallNormal: meterWallHit?.normal,
                    camera: camera,
                    forward: forward
                )
            }
            if next.meterSurroundDone {
                if !next.meterWideLookDone {
                    next.meterWideLookDone = true
                    next.panelWalkNeeded = !panelLock.locked
                }
            } else if next.meterWideLookDone {
                next.meterWideLookDone = false
            }
            if next.meterWideLookDone, next.panelWalkNeeded, panelLock.locked,
               let origin = panelWallHit?.position ?? panelGroundPosition {
                next.panelSteps = max(next.panelSteps, Self.backupSteps(from: origin, to: camera))
                Self.noteLook(
                    left: &next.panelLookedLeft,
                    right: &next.panelLookedRight,
                    along: &next.panelLookedAlong,
                    fallbackSectors: &next.panelFallbackSectors,
                    origin: origin,
                    wallNormal: panelWallHit?.normal,
                    camera: camera,
                    forward: forward
                )
            }
            guard next != scanGuide else { return }
            scanGuide = next
            onGuide?(next)
        }

        /// ARKit's camera looks down -Z.
        private static func cameraForward(_ matrix: simd_float4x4) -> SIMD3<Float> {
            -SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        }

        /// Marks left, right, and along-wall once the phone is a few steps out and aimed that way.
        /// Standing straight back and staring at the meter only counts as along the wall.
        private static func noteLook(
            left: inout Bool,
            right: inout Bool,
            along: inout Bool,
            fallbackSectors: inout UInt8,
            origin: SIMD3<Float>,
            wallNormal: SIMD3<Float>?,
            camera: SIMD3<Float>,
            forward: SIMD3<Float>
        ) {
            let offset = SIMD3<Float>(camera.x - origin.x, 0, camera.z - origin.z)
            let feet = Double(simd_length(offset)) / Double(BatteryGeometry.feetToMeters)
            guard feet >= ScanGuide.lookMinFeet else { return }
            guard let forwardFlat = unit(SIMD3(forward.x, 0, forward.z)) else { return }
            var outward = wallNormal.flatMap { unit(SIMD3($0.x, 0, $0.z)) }
            if outward == nil {
                noteFallbackLook(left: &left, right: &right, along: &along, sectors: &fallbackSectors, forward: forwardFlat)
                return
            }
            // The plane normal can point into the house. Face it toward the phone so left and right stay outdoors.
            if let current = outward, simd_dot(offset, current) < 0 {
                outward = -current
            }
            guard let outward else { return }
            let intoWall = -outward
            guard let sideAxis = unit(simd_cross(SIMD3<Float>(0, 1, 0), outward)) else { return }
            let angle = atan2(simd_dot(forwardFlat, sideAxis), simd_dot(forwardFlat, intoWall))
            let alongLimit: Float = 40 * .pi / 180
            let sideNear: Float = 40 * .pi / 180
            let sideFar: Float = 140 * .pi / 180
            if abs(angle) <= alongLimit {
                along = true
            } else if angle > sideNear && angle < sideFar {
                left = true
            } else if angle < -sideNear && angle > -sideFar {
                right = true
            }
        }

        /// No wall normal: three different aim directions, while already stepped back, stand in for the pan.
        private static func noteFallbackLook(
            left: inout Bool,
            right: inout Bool,
            along: inout Bool,
            sectors: inout UInt8,
            forward: SIMD3<Float>
        ) {
            var bearing = atan2(forward.x, forward.z)
            if bearing < 0 { bearing += 2 * .pi }
            let sector = Int(bearing / (.pi / 4)) % 8
            guard sector >= 0 else { return }
            sectors |= UInt8(1 << sector)
            guard sectors.nonzeroBitCount >= 3 else { return }
            left = true
            right = true
            along = true
        }

        private static func unit(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
            let length = simd_length(vector)
            guard length > 0.001 else { return nil }
            return vector / length
        }

        /// Horizontal distance in walking steps, capped at the wide-look target.
        private static func backupSteps(from origin: SIMD3<Float>, to camera: SIMD3<Float>) -> Int {
            let dx = Double(camera.x - origin.x)
            let dz = Double(camera.z - origin.z)
            let feet = (dx * dx + dz * dz).squareRoot() / Double(BatteryGeometry.feetToMeters)
            let steps = Int((feet / 2.5).rounded(.down))
            return min(ScanGuide.wideLookSteps, max(steps, 0))
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
            guard trackingBlockedMessage == nil, let sample = holdSample(at: point) else {
                resetHold()
                return
            }
            // The dot only confirms a detection under it. With no model, it can still lock the wall it sits on.
            guard centerAgreesWithDetection(kind), relockAllowed(kind, point: sample.point) else {
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

        /// The center dot locks a wall only when the current target's box covers that dot.
        /// If the model failed to load, the dot itself is the fallback.
        private func centerAgreesWithDetection(_ kind: EquipmentKind) -> Bool {
            if equipmentBridge.detector.loadError != nil { return true }
            guard let packet = pendingScan else { return false }
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            for detection in pendingDetections where detection.kind == kind && detection.confidence >= 0.5 {
                let rect = Self.viewRect(for: detection.boundingBox, in: packet)
                if rect.insetBy(dx: -32, dy: -32).contains(center) {
                    return true
                }
            }
            return false
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
                return CoachTip.moveSlowly.rawValue
            case .limited(let reason):
                switch reason {
                case .initializing, .relocalizing:
                    return CoachTip.holdStill.rawValue
                case .excessiveMotion:
                    return CoachTip.slowDown.rawValue
                case .insufficientFeatures:
                    return CoachTip.moreDetail.rawValue
                @unknown default:
                    return CoachTip.holdStill.rawValue
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
            // Mesh visualization disabled to keep camera view clear.
            // Classification data still used for placement rules; visual feedback through battery color only.
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
            // Disabled: mesh floods camera view. Classification still runs for clearance checks.
            // addMeshPart(draw.positions, draw.wall, .systemBlue, opacity: 0.34, to: anchor)
            // addMeshPart(draw.positions, draw.floor, .systemGreen, opacity: 0.18, to: anchor)
            // addMeshPart(draw.positions, draw.other, .systemOrange, opacity: 0.24, to: anchor)
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
            let colors = Array(repeating: SIMD3<UInt8>(200, 200, 200), count: vertexCount)
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
                cloud: MeshPointCloudChunk(positions: worldPositions, colors: colors, triangles: triangles),
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

/// Real camera colors for exported mesh vertices, so a surface seen once keeps its color after the camera
/// turns away. Cells are in each mesh anchor's own space: ARKit keeps nudging anchor transforms to correct
/// drift, and world-space cells would miss after every nudge. Re-meshing moves vertices a little, so a miss
/// falls back to the neighboring cells.
final class MeshColorCache: Sendable {
    private let anchors = OSAllocatedUnfairLock<[UUID: [SIMD3<Int32>: SIMD3<UInt8>]]>(initialState: [:])
    private static let cellSize: Float = 0.04
    private static let neighbors: [SIMD3<Int32>] = (-1...1).flatMap { x in
        (-1...1).flatMap { y in (-1...1).map { z in SIMD3<Int32>(Int32(x), Int32(y), Int32(z)) } }
    }

    /// Nil where the point has never been visible to the camera.
    func colors(anchor: UUID, local: [SIMD3<Float>], world: [SIMD3<Float>], frame: ARFrame?) -> [SIMD3<UInt8>?] {
        let sampled = frame.map { Self.sample(world, in: $0) } ?? []
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
