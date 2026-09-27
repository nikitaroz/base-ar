import ARKit
import AVFoundation
import CoreImage
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

/// The Live Survey, in order. The screen shows the first step that is not done, so it resumes there on appear.
/// Locks, the gas mark, the look-around, and the battery come from the scene. `readMeter` and `readBreaker` are the
/// capture right after each lock: done once the photo of the locked item arrives, or after a short grace. A lock the
/// scan captured by itself already carries its photo and read, so it skips that step. A find step that runs out of
/// time moves on with the item unmarked (its checks stay unknown) and looks again on the next visit. The gas
/// step is done once marked, answered "No" on Home Info, or not seen before its timeout.
/// Why the Live Survey's camera cannot run. It stays on screen, unlike an error line that clears after 4 s.
private enum CameraProblem: Equatable {
    /// Camera access is off for the app (denied or restricted).
    case accessOff
    /// The AR session failed for another reason.
    case failed

    var task: String {
        switch self {
        case .accessOff: "Camera is off"
        case .failed: "Camera stopped"
        }
    }

    var guidance: String {
        switch self {
        case .accessOff: "Turn on Camera for Base in Settings. Swipe from the left edge to go back."
        case .failed: "Swipe from the left edge to go back, then open the Live Survey again."
        }
    }
}

private enum LiveStep: Equatable {
    case findMeter
    case readMeter
    case findPanel
    case readBreaker
    case gas
    case lookAround
    case placeBattery
    case confirm

    /// The top line: the one job for this step.
    var task: String {
        switch self {
        case .findMeter: "Find the electric meter"
        case .readMeter: "Keep the meter in view"
        case .findPanel: "Find the breaker panel"
        case .readBreaker: "Keep the panel in view"
        case .gas: "Find the gas meter"
        case .lookAround: "Step back and look around"
        case .placeBattery: "Place the battery"
        case .confirm: "Saving your scan"
        }
    }
}

/// One cue for the bottom line, drawn as an animated SF Symbol plus short copy. The raw value is the copy, so the
/// session's tracking text maps back to its graphic. Copy never carries a distance.
private enum CoachTip: String {
    // Detector hints for the meter or panel search.
    case lookUp = "Look up at it"
    case pointDown = "Point your phone down"
    case stepBack = "Take a few steps back"
    case scootLeft = "Scoot left"
    case scootRight = "Scoot right"
    case zoomIn = "Get closer"
    case aimAtWall = "Aim at the wall"
    case holdStill = "Hold still"
    // Step motion.
    case pointAtMeter = "Point at the meter"
    case pointAtPanel = "Point at the panel"
    case markIt = "Put the dot on it, then tap Mark it myself"
    case scanNumber = "Scan the number up close"
    case typeNumber = "Type the number on the meter"
    case readingNumber = "Reading the number…"
    case tapBreaker = "Main breaker amps, not the panel bus rating"
    case tapGas = "Tap the gas meter, or say there isn’t one"
    case lookLeft = "Turn to look left"
    case lookRight = "Turn to look right"
    // The Live Survey has no buttons: a hold on the center ring marks what the detector cannot.
    case holdOnMeter = "Hold the ring on the meter"
    case holdOnPanel = "Hold the ring on the panel"
    case holdOnGas = "Hold the ring on the bottom of the gas meter"
    /// Tracking stuck at initializing or short of detail: the back lens is covered or facing a blank surface.
    case cantSee = "Can’t see anything. Point the back camera at the wall"
    // Tracking, from the AR session.
    case slowDown = "Slow down"
    case moveSlowly = "Move the phone slowly"
    case moreDetail = "Aim at something with more detail"
    case paused = "Paused"
    // Confirmations, shown for a moment.
    case foundMeter = "Found the meter"
    case foundPanel = "Found the panel"
    case gotNumber = "Got the number"
    case breakerSaved = "Main breaker saved"
    case gasMarked = "Gas meter marked"
    case scanned = "Scanned"
    // Automatic capture: the scan photographs the label and reads it by itself. Appended by the capture gate.
    case closerToLabel = "Get closer to the label"
    case tooDark = "Too dark — add light"
    case tooBright = "Too bright — shade the label"
    case faceLabel = "Turn so the label faces you"
    case readingBreaker = "Reading the main breaker…"
    case openPanelDoor = "Open the panel door, not the cover"
    // `holdOnGas` (the gas hold) is declared with the other ring holds above.
    // Integration: a panel read has its own confirmation, and a find step that runs out of time moves on.
    case gotBreaker = "Got the main breaker"
    case movingOn = "Not found. Review lists it"
    case cantRecognize = "This phone can’t spot it. Review lists it"
    // Fixer: a finished scan opened again has nothing left to do but slide the battery or go back.
    case swipeBack = "Slide the battery, or swipe from the left edge to go back"

    var symbol: String {
        switch self {
        case .lookUp: "arrow.up.circle.fill"
        case .pointDown: "arrow.down.circle.fill"
        case .stepBack: "figure.walk.motion"
        case .scootLeft: "arrow.left.circle.fill"
        case .scootRight: "arrow.right.circle.fill"
        case .zoomIn: "plus.magnifyingglass"
        case .aimAtWall, .pointAtMeter, .pointAtPanel: "viewfinder"
        case .holdStill: "hand.raised.fill"
        case .markIt, .tapBreaker, .tapGas: "hand.tap.fill"
        case .scanNumber, .readingNumber: "text.viewfinder"
        case .typeNumber: "keyboard"
        case .lookLeft: "arrow.turn.up.left"
        case .lookRight: "arrow.turn.up.right"
        case .holdOnMeter, .holdOnPanel, .holdOnGas: "scope"
        case .cantSee: "eye.slash.fill"
        case .slowDown: "tortoise.fill"
        case .moveSlowly: "iphone.gen3.radiowaves.left.and.right"
        case .moreDetail: "sparkle.magnifyingglass"
        case .paused: "pause.circle.fill"
        case .foundMeter, .foundPanel, .gotNumber, .breakerSaved, .gasMarked, .scanned: "checkmark.seal.fill"
        case .closerToLabel: "plus.magnifyingglass"
        case .tooDark: "flashlight.on.fill"
        case .tooBright: "sun.max.fill"
        case .faceLabel: "rotate.3d"
        case .readingBreaker: "text.viewfinder"
        case .openPanelDoor: "door.left.hand.open"
        case .gotBreaker: "checkmark.seal.fill"
        case .movingOn: "arrow.forward.circle.fill"
        case .cantRecognize: "exclamationmark.triangle.fill"
        case .swipeBack: "hand.draw.fill"
        }
    }

    /// Motion cues keep pulsing so the phone movement reads at a glance. Confirmations and Paused do not.
    var pulses: Bool {
        switch self {
        case .foundMeter, .foundPanel, .gotNumber, .breakerSaved, .gasMarked, .scanned, .paused,
             .gotBreaker, .movingOn, .swipeBack: false
        default: true
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

/// The bottom line: short copy, an SF Symbol, and a tint. The words always carry the message; the tint only adds
/// the placement tone or a warning.
private struct Feedback: Equatable {
    var text: String
    var symbol: String
    var tint: Color
    var pulses: Bool
    var isError = false

    init(_ tip: CoachTip, tint: Color = .primary) {
        text = tip.rawValue
        symbol = tip.symbol
        self.tint = tint
        pulses = tip.pulses
    }

    init(text: String, symbol: String, tint: Color, pulses: Bool = false, isError: Bool = false) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
        self.pulses = pulses
        self.isError = isError
    }
}

/// Keeps the bottom line steady. The detector reports about four times a second, and showing every read made the cue
/// jump before it could be trusted. A new cue has to hold for a moment before it shows, and a cue that showed stays
/// up for a minimum time. Errors, "Paused", the blind-camera cue, and confirmations go straight through.
private struct FeedbackPacer {
    /// About three of the last four detector reads. Tune on device.
    static let settle: Duration = .milliseconds(750)
    /// ARKit's tracking state is steadier than detector reads. Tune on device.
    static let trackingSettle: Duration = .milliseconds(500)
    /// A cue that showed stays at least this long unless something urgent replaces it. Tune on device.
    static let minDwell: Duration = .milliseconds(1500)

    private(set) var shown: Feedback?
    private var shownAt: ContinuousClock.Instant?
    private var shownIsUrgent = false
    private var candidate: Feedback?
    private var candidateSince: ContinuousClock.Instant?

    /// Offers the latest cue. Returns how long to wait before offering it again, or nil when nothing is pending.
    mutating func offer(_ next: Feedback?, urgent: Bool, fromTracking: Bool, now: ContinuousClock.Instant) -> Duration? {
        if next == shown {
            candidate = nil
            candidateSince = nil
            return nil
        }
        // Urgent cues show at once, an empty line takes the first cue at once, and a cleared error never lingers.
        if urgent || shown == nil || shownIsUrgent {
            show(next, urgent: urgent, now: now)
            return nil
        }
        if candidate != next {
            candidate = next
            candidateSince = now
        }
        let settle = fromTracking ? Self.trackingSettle : Self.settle
        let heldFor = now - (candidateSince ?? now)
        let shownFor = now - (shownAt ?? now)
        if heldFor >= settle, shownFor >= Self.minDwell {
            show(next, urgent: false, now: now)
            return nil
        }
        return max(settle - heldFor, Self.minDwell - shownFor, .milliseconds(50))
    }

    private mutating func show(_ next: Feedback?, urgent: Bool, now: ContinuousClock.Instant) {
        shown = next
        shownAt = now
        shownIsUrgent = urgent
        candidate = nil
        candidateSince = nil
    }
}

/// A value typed over the running scan.
private enum ValueEntry: String, Identifiable {
    case meterNumber
    case breakerAmps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meterNumber: "Meter number"
        case .breakerAmps: "Main breaker"
        }
    }

    var placeholder: String {
        switch self {
        case .meterNumber: "Number on the meter"
        case .breakerAmps: "Amps on the main breaker"
        }
    }

    var footer: String {
        switch self {
        case .meterNumber:
            "The long number on the meter’s nameplate. It is not the breaker size."
        case .breakerAmps:
            "The number on the big breaker at the top of the panel. This is the main breaker, not the panel bus rating. Don’t remove any covers."
        }
    }
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

/// Step 2, the Live Survey: the camera with one task line on top and one feedback line at the bottom. No top bar
/// and no buttons: each step advances by itself once the scan has what it needs, and a swipe right from the left
/// edge leaves. The ••• menu, the typed-number sheets, and the step buttons below stay in the code but are not shown.
struct PlacementARView: View {
    var store: SurveyStore
    /// Leaves the Live Survey from the left-edge swipe or VoiceOver's escape, after the scene is committed and the
    /// session paused. Called without an animation, since the slide already happened. Nil pops with `dismiss`.
    var onExit: (() -> Void)?
    var onContinue: () -> Void
    /// Leaves the scan for the rest of the survey. The unsupported-device screen uses it, so it never dead-ends.
    /// Nil falls back to `onExit`.
    var onReturnToSurvey: (() -> Void)?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var scene: PlacementSceneSnapshot
    @State private var lookAround = LookAround()
    @State private var yawRadians: Float
    @State private var statusMessage: String?
    @State private var trackingMessage: String?
    @State private var isVisible = false
    @State private var coachingIsActive = false
    @State private var scanFeedback = ScanFeedback()
    /// The meter or panel that just locked. "Not the …" can undo it for 5 s (and while the next item is searched for).
    @State private var recentLock: (kind: EquipmentKind, token: UUID)?
    @State private var capturedFrames = 0
    /// The bottom line as shown, paced so it does not flicker at the detector's rate.
    @State private var pacer = FeedbackPacer()
    @State private var latestFeedback: Feedback?
    @State private var pacerWait: Duration?
    @State private var pacerWake = 0
    /// Steps the scan finished that the scene itself does not show: each lock's capture and a gas meter not seen.
    /// Mirrored on the controller, so coming back to the scan does not ask again.
    @State private var passed: Set<LiveStep>
    /// A confirmation that holds the bottom line for a moment.
    @State private var flashTip: CoachTip?
    /// A confirmation earned while a cover hid the screen, shown once it closes.
    @State private var flashAfterCapture: CoachTip?
    @State private var valueEntry: ValueEntry?
    @State private var showsNumberScanner = false
    @State private var showsElectrical = false
    /// "Enter number manually" in the scanner opens the typed sheet once the scanner's cover is gone.
    @State private var typeNumberAfterScan = false
    /// The session is paused for the number scanner or the Electrical sheet. Neither fires `onDisappear`.
    @State private var pausedForCapture = false
    /// How far the left-edge swipe has slid the screen.
    @State private var dragOffset: CGFloat = 0
    /// Set from the committed swipe until the screen is gone, so nothing saves or advances on the way out.
    @State private var isLeaving = false
    /// Tracking stayed initializing or short of detail for a while. Frames arrive, but the back lens sees nothing.
    @State private var cameraSeesNothing = false
    /// The controller's capture feedback (the photo of a locked item), below confirmations and above detector hints.
    /// Set it from the controller's capture callback; any CoachTip case shows, nil says nothing.
    @State private var captureTip: CoachTip?
    /// The finish saves by itself only when the scan reached it on this visit, or the battery moved since. Coming
    /// back from Review to a finished scan must not bounce straight back to Review.
    @State private var autoFinishArmed = false
    /// The battery was slid on a finished scan opened again: that save waits for the slide to settle.
    @State private var finishWaitsForSlide = false
    /// Camera access is off or the AR session failed. Holds the step clocks and keeps its message up.
    @State private var cameraProblem: CameraProblem?

    private static let breakerChips = [100, 125, 150, 200]
    /// Touches that start inside this leading strip leave the scan; pans anywhere else reach the AR view.
    private static let edgeWidth: CGFloat = 24
    /// How long a locked meter or panel waits for its photo before the scan moves on. Review lists a missing photo.
    private static let captureGrace: Duration = .seconds(3)
    /// A gas meter not marked by then is left unknown. "Yes" on Home Info waits longer, since there is one to find.
    private static let gasWaitUnsure: Duration = .seconds(25)
    private static let gasWaitYes: Duration = .seconds(45)
    /// A tight side yard can keep the user from stepping back far enough.
    private static let lookAroundWait: Duration = .seconds(40)
    /// No ground beside the meter by then: the survey goes on without a battery, and its checks stay unknown.
    private static let batterySpotWait: Duration = .seconds(3)
    private static let batterySteady: Duration = .seconds(2)
    /// The placed battery and its tone stay on screen this long before the scan saves.
    private static let finishDwell: Duration = .seconds(1.5)
    private static let blindCameraDelay: Duration = .seconds(5)
    /// A meter or panel the scan cannot capture by then is left unmarked, so the scan still ends (amber) instead
    /// of waiting forever. With the detector down nothing can capture, so the wait is short. Tune on device.
    private static let findWait: Duration = .seconds(60)
    private static let findWaitNoDetector: Duration = .seconds(10)
    /// A label mid-read at the deadline gets this much longer.
    private static let findReadingGrace: Duration = .seconds(10)
    /// No meter means no battery spot beside it: the finish comes after this short pause.
    private static let noMeterDwell: Duration = .seconds(1.5)

    init(
        store: SurveyStore,
        onExit: (() -> Void)? = nil,
        onContinue: @escaping () -> Void,
        onReturnToSurvey: (() -> Void)? = nil
    ) {
        self.store = store
        self.onExit = onExit
        self.onContinue = onContinue
        self.onReturnToSurvey = onReturnToSurvey
        let existing = store.placementController
        _scene = State(initialValue: existing?.scene ?? PlacementSceneSnapshot())
        _lookAround = State(initialValue: existing?.lookAround ?? LookAround())
        _yawRadians = State(initialValue: existing?.yawRadians ?? 0)
        _passed = State(initialValue: existing?.passedLiveSteps ?? [])
    }

    /// Denied or restricted. Not yet asked is fine: ARKit asks when the session first runs.
    private static var cameraAccessOff: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    private var arSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    private var meterMarked: Bool {
        scene.meterPosition != nil || scene.meterWallPosition != nil
    }

    private var panelMarked: Bool {
        scene.panelPosition != nil || scene.panelWallPosition != nil
    }

    private var gasAnswer: GasMeterAnswer? {
        store.session.electrical.gasMeterAnswer
    }

    /// Marked on the scan (measured), or "No" on Home Info (the homeowner's answer, attested).
    private var gasResolved: Bool {
        scene.gasMeterPosition != nil || store.gasMeterNotVisible || gasAnswer == .no
    }

    /// The gas step is over: resolved, or not seen before its timeout. Not seen is no answer, so the gas check stays
    /// unknown; it never sets `gasMeterNotPresent`.
    private var gasStepDone: Bool {
        gasResolved || passed.contains(.gas)
    }

    /// The suggested spot beside the meter is showing and has not been accepted yet.
    private var hasBatteryGhost: Bool {
        scene.batteryPosition == nil && scene.suggestedBatteryPosition != nil
    }

    /// The scan's own capture locked it, so its photo and label read arrived with the lock.
    private var meterCapturedByScan: Bool {
        meterMarked && scene.meterLockSource == .scanCapture
    }

    private var panelCapturedByScan: Bool {
        panelMarked && scene.panelLockSource == .scanCapture
    }

    /// The meter and panel steps, where the detector runs.
    private var findingEquipment: Bool {
        switch step {
        case .findMeter, .readMeter, .findPanel, .readBreaker: true
        default: false
        }
    }

    /// The capture gate is reading a label right now.
    private var labelBeingRead: Bool {
        scanFeedback.hint == .readingNumber || scanFeedback.hint == .readingBreaker
    }

    private var recordedMeterNumber: String? {
        let number = store.session.electrical.meterNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return number.isEmpty ? nil : number
    }

    /// meter found → meter captured → panel found → panel captured → gas → look around → battery → save.
    /// Numbers are not asked for on the camera; a number read by the scan is a suggestion the user confirms in Review.
    private var step: LiveStep {
        // `passed` holding a find step means it ran out of time: the item stays unmarked and the scan goes on.
        if !meterMarked, !passed.contains(.findMeter) { return .findMeter }
        if meterMarked, !meterCapturedByScan, !passed.contains(.readMeter) { return .readMeter }
        if !panelMarked, !passed.contains(.findPanel) { return .findPanel }
        if panelMarked, !panelCapturedByScan, !passed.contains(.readBreaker) { return .readBreaker }
        if !gasStepDone { return .gas }
        if !lookAround.done { return .lookAround }
        // The suggested spot is `suggestedBatteryPosition` until it is accepted; only then is it `batteryPosition`.
        if scene.batteryPosition == nil { return .placeBattery }
        return .confirm
    }

    private var lockTarget: EquipmentKind? {
        switch step {
        case .findMeter: .electricMeter
        case .findPanel: .breakerPanel
        default: nil
        }
    }

    /// Controller step for the current one. The battery ghost only exists in `battery`; `finish` keeps the placed
    /// battery and its transfer-switch box. Any other step drops an unconfirmed ghost.
    private var guideStep: WalkStep {
        switch step {
        case .findMeter, .readMeter, .findPanel, .readBreaker, .lookAround: .scan
        case .gas: .gas
        case .placeBattery: .battery
        case .confirm: .finish
        }
    }

    /// Confirmed battery wins. Until the spot is accepted, the ghost stands in as the battery, so its tone is the
    /// tone the spot would get if placed there.
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

    /// The step clocks stop while the user cannot see the two lines or the scan is not running.
    private var clockHeld: Bool {
        !isVisible || coachingIsActive || pausedForCapture || isLeaving || cameraProblem != nil
    }

    private var stepClock: StepClock {
        StepClock(step: step, held: clockHeld)
    }

    private var batteryClock: BatteryClock {
        BatteryClock(
            step: step,
            spot: scene.suggestedBatteryPosition,
            placed: scene.batteryPosition,
            armed: autoFinishArmed,
            held: clockHeld
        )
    }

    /// ARKit's "initializing" and "not enough detail". Either one for a while means the lens sees nothing to track.
    private var trackingLooksBlind: Bool {
        trackingMessage == CoachTip.holdStill.rawValue || trackingMessage == CoachTip.moreDetail.rawValue
    }

    var body: some View {
        Group {
            if arSupported {
                liveScreen
            } else {
                unsupportedScreen
            }
        }
        // The camera has no top bar; the unsupported screen keeps one so Back still works there.
        .navigationTitle(arSupported ? "" : "Live Survey")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(arSupported ? .hidden : .automatic, for: .navigationBar)
        .onAppear {
            guard arSupported else { return }
            isVisible = true
            isLeaving = false
            dragOffset = 0
            autoFinishArmed = false
            finishWaitsForSlide = false
            let controller = store.requirePlacementController()
            // A camera that cannot run must say so and stop the clocks, not time every step out over a dead feed.
            cameraProblem = Self.cameraAccessOff ? .accessOff : nil
            controller.onSessionFailure = { cameraDenied in
                cameraProblem = cameraDenied ? .accessOff : .failed
            }
            if cameraProblem == nil {
                controller.resume()
            }
            scene = controller.scene
            lookAround = controller.lookAround
            yawRadians = controller.yawRadians
            // The controller reports tracking only on change, so a view pushed again picks up the current state.
            trackingMessage = controller.trackingBlockedMessage
            passed = controller.passedLiveSteps
            // "Not found" lasts one visit: coming back looks for the meter and panel again.
            unpass(.findMeter)
            unpass(.findPanel)
            syncGuide()
        }
        .onChange(of: step) { _, newStep in
            statusMessage = nil
            // Reached on this visit, so it saves by itself.
            if newStep == .confirm { autoFinishArmed = true }
            syncGuide()
        }
        .onChange(of: meterMarked) { _, marked in
            noteLockChange(.electricMeter, marked: marked)
            if marked {
                flashTip = .foundMeter
            } else {
                // A new lock gets its own capture.
                unpass(.readMeter)
            }
        }
        .onChange(of: panelMarked) { _, marked in
            noteLockChange(.breakerPanel, marked: marked)
            if marked {
                flashTip = .foundPanel
            } else {
                unpass(.readBreaker)
            }
        }
        .onChange(of: scene.gasMeterPosition != nil) { _, marked in
            if marked { flashTip = .gasMarked }
        }
        .onChange(of: lookAround.done) { _, done in
            if done { flashTip = .scanned }
        }
        .onChange(of: recordedMeterNumber) { old, new in
            // A number the scan read. It stays a suggestion until the user confirms it in Review.
            if isVisible, let new, new != old { flashTip = .gotNumber }
        }
        .onChange(of: store.session.electrical.mainBreakerAmperage) { old, new in
            // The panel capture's read of the main breaker, also a suggestion until confirmed in Review.
            if isVisible, new != nil, new != old, store.session.electrical.mainBreakerAmperageSource == .ocr {
                flashTip = .gotBreaker
            }
        }
        .onChange(of: scene.batteryPosition) { old, new in
            // A battery slid on a finished scan saves again once it settles.
            if step == .confirm, old != nil, new != nil {
                autoFinishArmed = true
                finishWaitsForSlide = true
            }
        }
        .onDisappear {
            isVisible = false
            commitLiveScene()
            store.placementController?.pauseIfIdle()
        }
        .onChange(of: scenePhase) { _, phase in
            // Under the number scanner or the Electrical sheet the session stays paused until that closes.
            guard isVisible, arSupported, !pausedForCapture, !isLeaving else { return }
            if phase == .active {
                // Back from Settings with the camera turned on: run again.
                if cameraProblem == .accessOff, !Self.cameraAccessOff { cameraProblem = nil }
                guard cameraProblem == nil else { return }
                store.placementController?.resume()
            } else if phase == .background {
                store.placementController?.pauseIfIdle()
            }
        }
        .task(id: flashTip) {
            guard flashTip != nil, await waitFor(.seconds(1.5)) else { return }
            flashTip = nil
        }
        // One line is shared, so an old error must not hide live feedback for long.
        .task(id: statusMessage) {
            guard statusMessage != nil, await waitFor(.seconds(4)) else { return }
            statusMessage = nil
        }
        .task(id: trackingLooksBlind) {
            cameraSeesNothing = false
            guard trackingLooksBlind, await waitFor(Self.blindCameraDelay) else { return }
            cameraSeesNothing = true
        }
        .task(id: stepClock) {
            await runStepClock()
        }
        .task(id: batteryClock) {
            await runBatteryClock()
        }
        .sheet(item: $valueEntry) { entry in
            ValueEntrySheet(entry: entry, initial: initialValue(for: entry)) { save(entry, $0) }
        }
        .sheet(isPresented: $showsElectrical, onDismiss: finishElectrical) {
            NavigationStack {
                ElectricalCaptureView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsElectrical = false }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showsNumberScanner, onDismiss: finishNumberScan) {
            LiveLabelScanner(target: .meterNumber) { read, image in
                acceptNumberScan(read, image: image)
                showsNumberScanner = false
            } onCancel: {
                showsNumberScanner = false
            } onManualEntry: {
                typeNumberAfterScan = true
                showsNumberScanner = false
            }
            .ignoresSafeArea()
        }
    }

    /// The camera, slid by the left-edge swipe.
    private var liveScreen: some View {
        GeometryReader { geometry in
            arScreen
                .offset(x: dragOffset)
                .overlay(alignment: .leading) {
                    edgeSwipe(width: geometry.size.width)
                }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .accessibilityAction(.escape) { leave() }
    }

    /// A rightward drag from the left edge follows the finger. Past about a third of the width, or on a fast flick,
    /// the scan leaves; anything shorter springs back.
    private func edgeSwipe(width: CGFloat) -> some View {
        Color.clear
            .frame(width: Self.edgeWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in
                        guard !isLeaving else { return }
                        dragOffset = max(0, value.translation.width)
                    }
                    .onEnded { value in
                        guard !isLeaving else { return }
                        let travel = max(value.translation.width, value.predictedEndTranslation.width)
                        if travel > width * 0.35 {
                            leave(slidingOut: width)
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = 0 }
                        }
                    }
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    private var arScreen: some View {
        // One assessment per update: it tints the battery and writes the tone line.
        let assessment = liveAssessment
        return ZStack {
            if let controller = store.placementController {
                PlacementARRepresentable(
                    controller: controller,
                    mode: step == .gas ? .gasMeter : .battery,
                    measurementMode: false,
                    measurementKind: .batteryToMeter,
                    editingWorkingSpace: false,
                    // Battery: one finger slides it along the meter wall and two fingers turn it, before and after
                    // it settles. The gas step's hold needs input too.
                    inputEnabled: step == .gas || step == .placeBattery || step == .confirm,
                    aimEnabled: step == .gas && scene.gasMeterPosition == nil,
                    // Nothing is marked by a tap: the scan locks, holds, and places by itself.
                    tapEnabled: false,
                    // Scanning stays on for the whole scan screen, as on main. The controller's detector gate rests
                    // the detector once both are locked, and the keyframe gate records from the panel lock through
                    // the look-around; both depend on this staying true.
                    scanning: true,
                    lockTarget: lockTarget,
                    yawRadians: yawRadians,
                    tone: assessment?.placementTone ?? .incomplete,
                    onSceneChange: acceptScene,
                    onYawChange: { yawRadians = $0 },
                    // The camera never shows a distance.
                    onLiveFeet: { _ in },
                    onFailure: { statusMessage = $0 },
                    onTrackingStatus: { trackingMessage = $0 },
                    onCoachingActiveChange: { coachingIsActive = $0 },
                    onLookAround: { lookAround = $0 },
                    onScanFeedback: { scanFeedback = $0 },
                    onMeterCrop: {
                        store.attachScanMeterPhotoIfMissing($0)
                        noteCaptured(.electricMeter)
                    }
                )
                .ignoresSafeArea()
            }
            // The coaching overlay has the camera to itself. The two lines come back when it finishes. A lens that
            // sees nothing keeps the coaching up, so the blind-camera line shows over it: "move the phone" won't help.
            if !coachingIsActive || (cameraSeesNothing && trackingLooksBlind) || cameraProblem != nil {
                VStack(spacing: 0) {
                    if !coachingIsActive || cameraProblem != nil {
                        taskLineView
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    Spacer(minLength: 0)
                    bottomBar(assessment)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                // Nothing on the lines takes a touch, so a drag that starts on them still reaches the AR view.
                .allowsHitTesting(false)
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
    }

    /// The top line: the one job now. A finished scan opened again says so.
    private var taskText: String {
        if let cameraProblem { return cameraProblem.task }
        if step == .confirm, !autoFinishArmed { return "Scan done" }
        // The battery spot is taken by itself in the background: the line says only that the scan is saving.
        if step == .placeBattery { return LiveStep.confirm.task }
        return step.task
    }

    private var taskLineView: some View {
        Text(taskText)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .animation(.easeInOut(duration: 0.25), value: taskText)
            .accessibilityAddTraits(.isHeader)
    }

    private func bottomBar(_ assessment: SurveyAssessment?) -> some View {
        let raw = feedback(assessment)
        return feedbackLine(pacer.shown)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onChange(of: raw, initial: true) { _, new in pace(new) }
            .task(id: pacerWake) {
                guard let wait = pacerWait, await waitFor(wait) else { return }
                pace(latestFeedback)
            }
    }

    private func pace(_ new: Feedback?) {
        latestFeedback = new
        let urgent = new.map { cue in
            cue.isError
                || cue.text == CoachTip.cantSee.rawValue
                || cue.text == CoachTip.paused.rawValue
                || flashTip.map { Feedback($0) } == cue
        } ?? false
        let fromTracking = !urgent && trackingMessage != nil && new?.text == trackingMessage
        pacerWait = pacer.offer(new, urgent: urgent, fromTracking: fromTracking, now: .now)
        if pacerWait != nil { pacerWake &+= 1 }
    }

    /// Animated SF Symbol plus short copy, one cue at a time. The height stays fixed so the line does not jump.
    private func feedbackLine(_ feedback: Feedback?) -> some View {
        HStack(spacing: 12) {
            if let feedback {
                Image(systemName: feedback.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(feedback.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: feedback.pulses)
                    .symbolEffect(.bounce, value: feedback.symbol)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                Text(feedback.text)
                    .font(.headline)
                    .foregroundStyle(feedback.isError ? feedback.tint : Color.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .animation(.easeInOut(duration: 0.2), value: feedback)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// One bottom line at a time: an error, then tracking, then a fresh confirmation, then capture feedback, then the
    /// detector, then the step.
    private func feedback(_ assessment: SurveyAssessment?) -> Feedback? {
        if let cameraProblem {
            return Feedback(
                text: cameraProblem.guidance,
                symbol: "video.slash.fill",
                tint: ToneStyle.color(.conflict),
                isError: true
            )
        }
        if let statusMessage {
            return Feedback(
                text: statusMessage,
                symbol: "exclamationmark.octagon.fill",
                tint: ToneStyle.color(.conflict),
                isError: true
            )
        }
        let warning = ToneStyle.color(.incomplete)
        if pausedForCapture {
            return Feedback(.paused, tint: warning)
        }
        if let trackingMessage {
            if cameraSeesNothing, trackingLooksBlind {
                return Feedback(.cantSee, tint: warning)
            }
            return CoachTip(rawValue: trackingMessage).map { Feedback($0, tint: warning) }
                ?? Feedback(text: trackingMessage, symbol: "exclamationmark.triangle.fill", tint: warning)
        }
        if let flashTip {
            return Feedback(flashTip)
        }
        if let captureTip {
            return Feedback(captureTip)
        }
        if lockTarget != nil {
            // Nothing captures without the detector, so the step moves on shortly.
            if scanFeedback.detector != .ok {
                return Feedback(.cantRecognize, tint: warning)
            }
            // The capture gate's cue: framing, light, or "Reading…".
            if let hint = scanFeedback.hint {
                return Feedback(hint)
            }
        }
        // The gas hold's cue ("Hold still" while the ring rests on a spot it can mark).
        if step == .gas, let hint = scanFeedback.hint {
            return Feedback(hint)
        }
        return stepFeedback(assessment)
    }

    private func stepFeedback(_ assessment: SurveyAssessment?) -> Feedback? {
        switch step {
        // The scan captures the meter and panel by itself; there is no hold to mark them. After a while without a
        // box, say what the capture needs.
        case .findMeter:
            return Feedback(manualTargetForCue == nil ? .pointAtMeter : .closerToLabel)
        case .findPanel:
            return Feedback(manualTargetForCue == nil ? .pointAtPanel : .openPanelDoor)
        case .readMeter, .readBreaker:
            return Feedback(.holdStill)
        case .gas:
            return Feedback(.holdOnGas)
        case .lookAround:
            if !lookAround.movedFarther { return Feedback(.stepBack) }
            if !lookAround.lookedLeft { return Feedback(.lookLeft) }
            if !lookAround.lookedRight { return Feedback(.lookRight) }
            return Feedback(.stepBack)
        case .placeBattery, .confirm:
            // A finished scan opened again ("Scan done") does not save by itself until the battery moves.
            if step == .confirm, !autoFinishArmed { return Feedback(.swipeBack) }
            // The save right after the look-around gives no battery instructions.
            if step == .placeBattery || autoFinishArmed && !finishWaitsForSlide { return Feedback(.scanned) }
            // No ghost yet means no ground beside the meter.
            guard let assessment else { return Feedback(.pointDown) }
            return toneFeedback(assessment)
        }
    }

    /// Not shown: the Live Survey has no buttons. Kept for the step actions it wires.
    private var stepControls: some View {
        VStack(spacing: 8) {
            stepActions
            lockControls
        }
    }

    @ViewBuilder
    private var stepActions: some View {
        switch step {
        case .findMeter, .findPanel:
            EmptyView()
        case .readMeter:
            if recordedMeterNumber != nil {
                primaryButton("Looks right") { pass(.readMeter) }
                HStack(spacing: 8) {
                    if LiveLabelScanner.isSupported {
                        secondaryButton("Scan again") { beginNumberScan() }
                    }
                    secondaryButton("Type it") { valueEntry = .meterNumber }
                }
            } else {
                if LiveLabelScanner.isSupported {
                    primaryButton("Scan meter number") { beginNumberScan() }
                }
                HStack(spacing: 8) {
                    secondaryButton("Type it") { valueEntry = .meterNumber }
                    secondaryButton("Skip") { pass(.readMeter) }
                }
            }
        case .readBreaker:
            HStack(spacing: 8) {
                ForEach(Self.breakerChips, id: \.self) { amps in
                    Button {
                        saveBreaker(amps)
                    } label: {
                        Text("\(amps) A")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("\(amps) amp main breaker")
                }
            }
            HStack(spacing: 8) {
                secondaryButton("Other…") { valueEntry = .breakerAmps }
                secondaryButton("Skip") { pass(.readBreaker) }
            }
        case .gas:
            secondaryButton("No gas meter") {
                store.setGasMeterNotVisible(true)
                store.placementController?.clearGasMarker()
            }
        case .lookAround:
            secondaryButton("Can’t step back") {
                store.placementController?.skipLookAround()
            }
        case .placeBattery:
            if hasBatteryGhost {
                primaryButton("Put it here") {
                    store.placementController?.confirmBatterySpot()
                }
                secondaryButton("Other side") {
                    store.placementController?.flipBatterySide()
                }
            } else {
                // No ground found beside the meter yet. Saving still works; the battery checks stay unknown (amber).
                secondaryButton("Save without battery") {
                    submit(withoutBattery: true)
                }
            }
        case .confirm:
            Button {
                submit()
            } label: {
                Text("Save and review")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            secondaryButton("Move it") {
                store.placementController?.unconfirmBatterySpot()
            }
        }
    }

    @ViewBuilder
    private var lockControls: some View {
        if manualTargetForCue != nil || rejectableLock != nil {
            HStack(spacing: 8) {
                if manualTargetForCue != nil {
                    secondaryButton("Mark it myself") {
                        store.placementController?.markTargetAtDot()
                    }
                }
                if let wrong = rejectableLock {
                    secondaryButton("Not the \(wrong.title.lowercased())") {
                        dropLock(wrong)
                    }
                }
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    /// Not shown: the Live Survey has no top bar. Review's "What's missing" rows cover redo and typed numbers.
    private var moreMenu: some View {
        Menu {
            Section {
                Button(role: .destructive) {
                    restart()
                } label: {
                    Label("Start the scan over", systemImage: "arrow.uturn.backward")
                }
                .disabled(!(meterMarked || panelMarked || gasResolved))
                Button {
                    dropLock(.electricMeter)
                } label: {
                    Label("Redo meter", systemImage: "arrow.counterclockwise")
                }
                .disabled(!meterMarked)
                Button {
                    dropLock(.breakerPanel)
                } label: {
                    Label("Redo panel", systemImage: "arrow.counterclockwise")
                }
                .disabled(!panelMarked)
            }
            Section {
                if LiveLabelScanner.isSupported {
                    Button {
                        beginNumberScan()
                    } label: {
                        Label("Scan meter number", systemImage: "text.viewfinder")
                    }
                }
                Button {
                    openElectrical()
                } label: {
                    Label("Type electrical numbers", systemImage: "keyboard")
                }
            }
            Button {
                finishLater()
            } label: {
                Label("Finish later", systemImage: "clock")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    private var unsupportedScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            ContentUnavailableView(
                "Placement preview isn’t available on this device",
                systemImage: "arkit",
                description: Text("Use a physical iPhone to scan the meter and the panel. You can complete the other survey sections here.")
            )
            Button("Return to survey") {
                returnToSurvey()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            Button("Type electrical numbers") {
                openElectrical()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            Button("Review missing items") {
                onContinue()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The target the controller has given up auto-locking on, about 12 s in or with the detector down. The bottom
    /// line then asks for the center-ring hold.
    private var manualTargetForCue: EquipmentKind? {
        guard let lockTarget, scanFeedback.manualTarget == lockTarget else { return nil }
        return lockTarget
    }

    /// A lock "Not the …" may still undo: for 5 s after it locks, and while the next item is being searched for.
    /// It clears the lock and keeps it from relocking on the same spot. Later, Redo in the ••• menu does the same.
    private var rejectableLock: EquipmentKind? {
        switch step {
        case .findPanel where meterMarked: return .electricMeter
        case .gas where panelMarked: return .breakerPanel
        default: break
        }
        guard let kind = recentLock?.kind else { return nil }
        return (kind == .electricMeter ? meterMarked : panelMarked) ? kind : nil
    }

    /// The tone as words, an icon, and its color: what the spot needs next, never a distance.
    private func toneFeedback(_ assessment: SurveyAssessment) -> Feedback {
        let tone = assessment.placementTone
        let text: String
        switch tone {
        case .clear:
            text = "Fits here. An engineer still confirms."
        case .attested:
            text = "Fits, but some checks are your answers"
        case .conflict:
            text = firstRule(.conflict, in: assessment).map(Self.fix(for:)) ?? ToneStyle.title(.conflict)
        case .incomplete:
            text = firstRule(.unknown, in: assessment).map { nextAction(for: $0) } ?? "Still checking…"
        }
        // Confirmations hold still. A fix or a next action is a motion cue.
        return Feedback(
            text: text,
            symbol: ToneStyle.symbol(tone),
            tint: ToneStyle.color(tone),
            pulses: tone == .conflict || tone == .incomplete
        )
    }

    /// The rule the tone line speaks for: first what moving the battery changes, then what the scan found at the
    /// meter and panel, then answers from the other screens. All of them still count toward the tone.
    private func firstRule(_ status: CheckStatus, in assessment: SurveyAssessment) -> RuleResult? {
        func tier(_ id: String) -> Int {
            switch id {
            case "austin-main-breaker", "solar-or-two-batteries": 2
            case "meter-height", "meter-panel-same-wall": 1
            default: 0
            }
        }
        let matching = assessment.results.filter { $0.isRequired && $0.status == status }
        for level in 0...2 {
            if let rule = matching.first(where: { tier($0.id) == level }) { return rule }
        }
        return nil
    }

    /// A conflicting rule as the fix to try. What moving the battery cannot fix says what was found.
    private static func fix(for rule: RuleResult) -> String {
        switch rule.id {
        case "wall-distance": "Slide it closer to the wall"
        case "meter-distance": "Move it closer to the meter"
        case "gas-meter-clearance": "Too close to the gas meter"
        case "not-in-front-of-window": "It’s in front of a window"
        case "meter-panel-access": "It blocks the meter or panel"
        case "planning-footprint": "Something is in the way"
        case "transfer-switch-space": "Something blocks the wall beside the meter"
        case "front-working-space": "Something blocks the space in front of the meter"
        case "meter-height": "The meter is outside Base’s height range"
        case "meter-panel-same-wall": "The meter and panel are on different walls"
        case "austin-main-breaker": "The main breaker is outside Austin’s range"
        case "solar-or-two-batteries": "The panel bus rating is too low for this plan"
        // Rule titles carry thresholds in feet, and the camera never shows a distance.
        default: "Something doesn’t fit here. Review lists it."
        }
    }

    /// An unknown rule as the next thing to do. Mesh checks cannot finish on an iPhone without LiDAR. What the camera
    /// cannot settle points at Review, which asks for it; there are no buttons here.
    private func nextAction(for rule: RuleResult) -> String {
        let meshChecks: Set<String> = ["planning-footprint", "not-in-front-of-window", "transfer-switch-space", "front-working-space"]
        if meshChecks.contains(rule.id), !scene.lidarMeshAvailable {
            return "This iPhone can’t scan that. Review lists it."
        }
        switch rule.id {
        case "wall-distance", "not-in-front-of-window": return "Aim at the wall behind it"
        case "planning-footprint": return "Point down at the ground under it"
        case "transfer-switch-space": return "Look at the wall beside the meter"
        case "front-working-space": return "Point down in front of the meter"
        case "meter-panel-access", "meter-panel-same-wall": return "Keep the meter and panel in view"
        case "meter-distance": return "Keep the meter in view"
        case "meter-height": return "Point down at the ground under the meter"
        case "gas-meter-clearance": return "Review asks about the gas meter"
        case "austin-main-breaker": return "Review asks for the main breaker size"
        case "solar-or-two-batteries":
            return store.session.electrical.needsPanelBusRating
                ? "Review asks for the panel bus rating"
                : "Answer solar and battery count in Home info"
        default: return "Still checking…"
        }
    }

    private func syncGuide() {
        // A gas meter not seen still lets the battery be suggested; its clearance check stays unknown.
        store.placementController?.syncGuide(step: guideStep, gasResolved: gasStepDone)
    }

    private func pass(_ liveStep: LiveStep) {
        passed.insert(liveStep)
        store.placementController?.passedLiveSteps = passed
    }

    private func unpass(_ liveStep: LiveStep) {
        guard passed.contains(liveStep) else { return }
        passed.remove(liveStep)
        store.placementController?.passedLiveSteps = passed
    }

    /// A number the survey already has counts as read. Only the Electrical sheet uses it now.
    private func passRecordedSteps() {
        if recordedMeterNumber != nil { pass(.readMeter) }
    }

    /// The photo of a locked meter or panel arrived, so that item's "Keep it in view" step is done. The meter's crop
    /// from its lock counts. Hook any other capture callback here.
    private func noteCaptured(_ kind: EquipmentKind) {
        switch kind {
        case .electricMeter: pass(.readMeter)
        case .breakerPanel: pass(.readBreaker)
        }
    }

    /// The timeouts that keep a button-free scan from stalling. Each restarts when the step changes or the lines hide.
    private func runStepClock() async {
        guard !clockHeld else { return }
        let waiting = step
        switch waiting {
        case .readMeter, .readBreaker:
            // No photo from the lock: move on. Review lists a missing photo.
            guard await waitFor(Self.captureGrace), step == waiting else { return }
            pass(waiting)
        case .gas:
            // "Not seen" is no answer. The gas check stays unknown; only "No" on Home Info says there is none.
            guard await waitFor(gasAnswer == .yes ? Self.gasWaitYes : Self.gasWaitUnsure),
                  step == .gas, scene.gasMeterPosition == nil else { return }
            pass(.gas)
        case .lookAround:
            // The look-around is measured from the meter or panel wall. With neither found there is nothing to
            // look around from, so it is skipped at once.
            if meterMarked || panelMarked {
                // The mesh checks still judge what was covered, so moving on claims nothing.
                guard await waitFor(Self.lookAroundWait), step == .lookAround else { return }
            }
            store.placementController?.skipLookAround()
        case .findMeter, .findPanel:
            await runFindClock(waiting)
        case .placeBattery, .confirm:
            return
        }
    }

    /// A meter or panel that never captures must not trap the user: after `findWait` (short with the detector
    /// down, a little longer while a label is mid-read) the step moves on with it unmarked. Its checks stay
    /// unknown and Review lists it. The wait is measured as it runs, so a detector that flickers cannot restart it.
    private func runFindClock(_ waiting: LiveStep) async {
        let clock = ContinuousClock()
        let start = clock.now
        while true {
            guard await waitFor(.milliseconds(500)), step == waiting else { return }
            let elapsed = clock.now - start
            let limit = scanFeedback.detector == .ok ? Self.findWait : Self.findWaitNoDetector
            if elapsed < limit { continue }
            if labelBeingRead, elapsed < limit + Self.findReadingGrace { continue }
            break
        }
        let detectorDown = scanFeedback.detector != .ok
        pass(waiting)
        flashTip = detectorDown ? .cantRecognize : .movingOn
    }

    /// Battery and finish, both hands-free and instant. The suggested spot is accepted as soon as it exists; with
    /// no spot within `batterySpotWait` the survey goes on without a battery (amber). The finish takes the scan
    /// photo and opens Review at once. (`batterySteady` and `phoneHeldSteady` are no longer used.)
    private func runBatteryClock() async {
        guard !clockHeld else { return }
        switch step {
        case .placeBattery:
            if hasBatteryGhost {
                store.placementController?.confirmBatterySpot()
            } else {
                // The spot is suggested beside the meter, so with no meter there is none to wait for.
                guard await waitFor(meterMarked ? Self.batterySpotWait : Self.noMeterDwell),
                      step == .placeBattery, !hasBatteryGhost else { return }
                submit(withoutBattery: true)
            }
        case .confirm:
            guard autoFinishArmed, step == .confirm else { return }
            // Reached right after the look-around, it saves at once; a slide on a reopened scan settles first.
            if finishWaitsForSlide {
                guard await waitFor(Self.finishDwell), step == .confirm else { return }
            }
            submit()
        default:
            return
        }
    }

    /// True once the camera has stayed within 3 cm and 4° for `duration` with tracking normal. False if cancelled.
    private func phoneHeldSteady(for duration: Duration) async -> Bool {
        let clock = ContinuousClock()
        var anchor: CameraPose?
        var since = clock.now
        while true {
            guard await waitFor(.milliseconds(200)) else { return false }
            guard trackingMessage == nil, let pose = cameraPose() else {
                anchor = nil
                continue
            }
            if let start = anchor, pose.isNear(start) {
                if clock.now - since >= duration { return true }
            } else {
                anchor = pose
                since = clock.now
            }
        }
    }

    private func cameraPose() -> CameraPose? {
        guard let controller = store.placementController else { return nil }
        let matrix = controller.arView.cameraTransform.matrix
        let forward = -SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        let length = simd_length(forward)
        guard length > 0.001 else { return nil }
        return CameraPose(
            position: SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z),
            forward: forward / length
        )
    }

    /// Sleeps for `duration`. False when the task was cancelled.
    private func waitFor(_ duration: Duration) async -> Bool {
        (try? await Task.sleep(for: duration)) != nil
    }

    /// The left-edge swipe and VoiceOver's escape: keep the scan, pause the camera, and leave. The swipe slides the
    /// screen out first, so the navigation itself runs without an animation.
    private func leave(slidingOut width: CGFloat? = nil) {
        guard !isLeaving else { return }
        isLeaving = true
        commitLiveScene()
        store.placementController?.pauseIfIdle()
        guard let width else {
            exitNow()
            return
        }
        withAnimation(.easeOut(duration: 0.2)) { dragOffset = width }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            exitNow()
        }
    }

    private func exitNow() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let onExit {
                onExit()
            } else {
                dismiss()
            }
        }
        // Still on screen (nothing took the exit): come back rather than stay slid away with the camera paused.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard isVisible, isLeaving else { return }
            isLeaving = false
            dragOffset = 0
            if scenePhase == .active {
                store.placementController?.resume()
            }
        }
    }

    private func returnToSurvey() {
        if let onReturnToSurvey {
            onReturnToSurvey()
        } else if let onExit {
            onExit()
        } else {
            dismiss()
        }
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

    /// "Not the …" and Redo: the scan asks for that item again. A meter photo that was only this lock's crop goes too.
    private func dropLock(_ kind: EquipmentKind) {
        recentLock = nil
        store.placementController?.rejectLock(kind)
        if kind == .electricMeter {
            store.dropScanMeterPhoto()
        }
    }

    private func saveBreaker(_ amps: Int) {
        store.setMainBreakerAmperage(amps)
        flashTip = .breakerSaved
    }

    private func initialValue(for entry: ValueEntry) -> String {
        switch entry {
        case .meterNumber: store.session.electrical.meterNumber ?? ""
        case .breakerAmps: store.session.electrical.mainBreakerAmperage.map(String.init) ?? ""
        }
    }

    private func save(_ entry: ValueEntry, _ value: String) {
        switch entry {
        case .meterNumber:
            store.setMeterNumber(value, source: .manual)
            pass(.readMeter)
        case .breakerAmps:
            guard let amps = Int(value), amps > 0 else { return }
            saveBreaker(amps)
        }
    }

    /// Main's live number scan, the one that reads up close. The AR session lets go of the camera first.
    private func beginNumberScan() {
        Task {
            if let reason = await LiveLabelScanner.prepare() {
                statusMessage = reason
                return
            }
            pauseForCapture()
            showsNumberScanner = true
        }
    }

    /// Same order as the Electrical screen: the number first, so the photo's own OCR does not run over it.
    private func acceptNumberScan(_ read: LabelScanRead, image: UIImage?) {
        if let number = read.meterNumber {
            store.setMeterNumber(number, source: .ocr, note: "Scanned from the camera. Confirm it matches the meter.")
            flashAfterCapture = .gotNumber
        }
        if let image {
            store.attachMeterPhoto(image)
        }
        pass(.readMeter)
    }

    private func finishNumberScan() {
        resumeAfterCapture()
        if let flash = flashAfterCapture {
            flashAfterCapture = nil
            flashTip = flash
        }
        if typeNumberAfterScan {
            typeNumberAfterScan = false
            valueEntry = .meterNumber
        }
    }

    private func openElectrical() {
        pauseForCapture()
        showsElectrical = true
    }

    /// A number typed or scanned on the Electrical sheet counts as read.
    private func finishElectrical() {
        resumeAfterCapture()
        passRecordedSteps()
    }

    /// A full-screen cover or a sheet does not fire `onDisappear`, so the scan pauses itself: the number scanner
    /// needs the camera ARKit holds, and a frozen camera should not keep locking or measuring.
    private func pauseForCapture() {
        guard arSupported, !pausedForCapture else { return }
        pausedForCapture = true
        commitLiveScene()
        store.placementController?.pauseIfIdle()
    }

    private func resumeAfterCapture() {
        guard pausedForCapture else { return }
        pausedForCapture = false
        // Backgrounded meanwhile: the scene-phase change resumes it instead.
        guard isVisible, scenePhase == .active else { return }
        store.placementController?.resume()
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
        // Home Info's "No" is the homeowner's answer, not part of the scan.
        store.setGasMeterNotVisible(gasAnswer == .no)
        store.placementController?.restartScan()
        // The live scene is empty now, so it would never be committed over the old marks and height.
        store.resetPlacementEvidence()
        store.dropScanMeterPhoto()
        passed = store.placementController?.passedLiveSteps ?? []
        statusMessage = nil
        flashTip = nil
        recentLock = nil
    }

    /// Keeps the scan as it is and opens Review. Coming back resumes at the first step that is not done.
    private func finishLater() {
        commitLiveScene()
        onContinue()
    }

    /// Saves the scan and opens Review: from the finish, or from the battery step when no spot showed up.
    private func submit(withoutBattery: Bool = false) {
        guard !isLeaving, step == .confirm || (withoutBattery && step == .placeBattery) else { return }
        commitLiveScene()
        statusMessage = nil
        onContinue()
    }

    private func commitLiveScene() {
        guard let live = store.placementController?.scene, live.hasPlacedContent else { return }
        store.commitPlacement(live)
    }
}

/// What the step clocks key on. A new value cancels the running clock and starts it over.
private struct StepClock: Equatable {
    var step: LiveStep
    var held: Bool
}

private struct BatteryClock: Equatable {
    var step: LiveStep
    var spot: PlacementAnchor?
    var placed: PlacementAnchor?
    var armed: Bool
    var held: Bool
}

/// Where the camera is and which way it faces, for the battery's hold-still check.
private struct CameraPose {
    var position: SIMD3<Float>
    var forward: SIMD3<Float>

    func isNear(_ other: CameraPose) -> Bool {
        simd_distance(position, other.position) < 0.03 && simd_dot(forward, other.forward) > cos(4 * Float.pi / 180)
    }
}

/// One typed value over the running scan: the meter number, or a main-breaker size that is not a chip.
private struct ValueEntrySheet: View {
    var entry: ValueEntry
    var initial: String
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(entry.placeholder, text: $text)
                            .keyboardType(entry == .breakerAmps ? .numberPad : .default)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .onChange(of: text) { _, newValue in
                                guard entry == .breakerAmps else { return }
                                let digits = newValue.filter(\.isNumber)
                                if digits != newValue { text = digits }
                            }
                        if entry == .breakerAmps {
                            Text("A")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(entry.footer)
                }
            }
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { text = initial }
        // Focus once the sheet is up, or the keyboard request is dropped.
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            focused = true
        }
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

/// A box the capture gate is judging this frame: a detector box, or the text-first box of a label it read.
private struct CaptureCandidate {
    /// Vision-normalized, origin lower left of the upright image.
    var box: CGRect
    var quality: CaptureReading?
    var textFirst: Bool
    var source: String
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
    var onSceneChange: (PlacementSceneSnapshot) -> Void
    var onYawChange: (Float) -> Void
    var onLiveFeet: (Double?) -> Void
    var onFailure: (String) -> Void
    var onTrackingStatus: (String?) -> Void
    var onCoachingActiveChange: (Bool) -> Void
    var onLookAround: (LookAround) -> Void
    var onScanFeedback: (ScanFeedback) -> Void
    var onMeterCrop: (UIImage) -> Void

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
            onSceneChange: onSceneChange,
            onYawChange: onYawChange,
            onLiveFeet: onLiveFeet,
            onFailure: onFailure,
            onTrackingStatus: onTrackingStatus,
            onCoachingActiveChange: onCoachingActiveChange,
            onLookAround: onLookAround,
            onScanFeedback: onScanFeedback,
            onMeterCrop: onMeterCrop
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
    /// Live Survey steps the user accepted or skipped. Kept here so the answer survives leaving the scan screen.
    fileprivate var passedLiveSteps: Set<LiveStep> = []

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
    private var onSceneChange: ((PlacementSceneSnapshot) -> Void)?
    private var onYawChange: ((Float) -> Void)?
    private var onFailure: ((String) -> Void)?
    /// The AR session itself failed. True when camera access is off. Set by the Live Survey, which keeps a message up
    /// and stops its clocks; without it the failure goes to `onFailure`.
    var onSessionFailure: ((_ cameraDenied: Bool) -> Void)?
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
        /// Best box per kind from the last three packets, newest last. Drawing waits for two of three to agree.
        private var recentBoxes: [[EquipmentKind: CGRect]] = []
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
        private var onMeterCrop: ((UIImage) -> Void)?
        /// The capture gate's photo and label value for a meter or panel it locked. The store sets this when it
        /// creates the controller, so no screen has to pass it through.
        var onScanCapture: ((ScanCapture) -> Void)?
        /// A lock the capture gate made was cleared ("Not the …", Redo, Start over): its photo and read go too.
        var onScanCaptureCleared: ((EquipmentKind) -> Void)?
        private let textReader = ScanTextReader()
        private var capture = ScanCaptureState()
        private var shownCaptureHint: CoachTip?
        private var proposedCaptureHint: CoachTip?
        private var proposedCaptureHintCount = 0
        private var gasHoldAnchor: SIMD3<Float>?
        private var gasHoldSince: CFTimeInterval?
        /// When the gas step's ring appeared, so a hold only counts once the user has had a moment to aim.
        private var gasAimSince: CFTimeInterval?
        private var gasHint: CoachTip?
        private static let captureLog = Logger(subsystem: "BaseAR", category: "ScanCapture")
        /// Renders the fallback meter photo off the main thread. Core Image contexts are thread-safe.
        private nonisolated static let cropContext = CIContext()
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
            onSceneChange: @escaping (PlacementSceneSnapshot) -> Void,
            onYawChange: @escaping (Float) -> Void,
            onLiveFeet: @escaping (Double?) -> Void,
            onFailure: @escaping (String) -> Void,
            onTrackingStatus: @escaping (String?) -> Void,
            onCoachingActiveChange: @escaping (Bool) -> Void,
            onLookAround: @escaping (LookAround) -> Void,
            onScanFeedback: @escaping (ScanFeedback) -> Void,
            onMeterCrop: @escaping (UIImage) -> Void
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
            self.onMeterCrop = onMeterCrop
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
            self.onFailure = onFailure
            self.onTrackingStatus = onTrackingStatus
            self.onCoachingActiveChange = onCoachingActiveChange
            if startedScanning, !reportedScanLoadError, let loadError = equipmentBridge.detector.loadError {
                reportedScanLoadError = true
                // The Live Survey has nothing to tap, so say what happens instead: the steps move on and Review lists them.
                var message = "This phone can’t spot the meter or panel. Review lists them."
                #if DEBUG
                message += " (\(loadError))"
                #endif
                self.onFailure?(message)
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
        }

        func resume() {
            // A view coming back starts from an empty ScanFeedback, so the next tick publishes again.
            lastScanFeedback = nil
            prepareIfNeeded()
            guard let configuration else { return }
            arView.session.run(configuration, options: [])
            startAiming()
        }

        func pauseIfIdle() {
            guard isPrepared else { return }
            // Any in-flight rotation gesture is invalidated by pausing the session.
            rotationStartYaw = appliedYaw
            stopAiming()
            arView.session.pause()
        }

        func stop() {
            stopAiming()
            onSceneChange = nil
            onYawChange = nil
            onFailure = nil
            onTrackingStatus = nil
            onLiveFeet = nil
            onCoachingActiveChange = nil
            onSessionFailure = nil
            onMeterCrop = nil
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
            let cameraDenied = (error as? ARError)?.code == .cameraUnauthorized
            Task { @MainActor in
                if let onSessionFailure = self.onSessionFailure {
                    onSessionFailure(cameraDenied)
                } else {
                    self.onFailure?(message)
                }
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
        /// and would spend the frame budget before the look-around. The Live Survey stops the detector once both
        /// are locked, so this does not wait on `scanningEquipment`: the gas and battery steps are the look-around.
        /// Frames arrive only while the Live Survey's session runs.
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
            if mode != .gasMeter || !aimEnabled || coachingActive, gasAimSince != nil || gasHint != nil {
                gasAimSince = nil
                gasHint = nil
                resetGasHold()
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
            if mode == .gasMeter {
                reticle?.isEnabled = false
                hideLiveLine()
                publishLiveFeet(nil)
                updateGasHold(at: point)
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
            let clearedScanCapture: EquipmentKind? = switch kind {
            case .meter where meterLockSource == .scanCapture: .electricMeter
            case .panel where panelLockSource == .scanCapture: .breakerPanel
            default: nil
            }
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
            resetCapture()
            if let clearedScanCapture {
                onScanCaptureCleared?(clearedScanCapture)
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
            recentBoxes = []
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
                capture.breakStreak()
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
            // Far away, the meter and panel look alike. One box scored as both is one object. While a step is asking
            // for one of them, keep that label: a meter often sits inside or beside the larger panel box, and dropping
            // it whenever the panel scored higher left the meter unlockable. With no step asking, keep the stronger label.
            if let meter = best[.electricMeter], let panel = best[.breakerPanel],
               Self.overlap(meter.boundingBox, panel.boundingBox) > 0.3 {
                let keep = holdLockKind() ?? (meter.confidence >= panel.confidence ? .electricMeter : .breakerPanel)
                best[keep == .electricMeter ? .breakerPanel : .electricMeter] = nil
            }
            pendingScan = packet
            pendingDetections = Array(best.values)
            recentBoxes.append(best.mapValues(\.boundingBox))
            if recentBoxes.count > 3 { recentBoxes.removeFirst(recentBoxes.count - 3) }
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
            let asked = holdLockKind()
            var streakTarget = asked
            if Self.scanCaptureEnabled {
                scanHint = settledCaptureHint(evaluateCapture(packet))
                // Late fallback, meter only. Glare, a dirty cover, a short number, or a barcode-only plate can keep
                // the label from ever reading twice, and with no meter there is no battery spot. After
                // `lateDetectorLockSeconds` of searching, the detector-streak lock below (main's rule: five agreeing
                // wall hits at the lock score, height and separation guards) may lock it too, on a sharp, exposed box.
                // Its source is `.detector`, so no number is suggested; Review asks for it. Not the panel: on its own
                // that lock took any wall for the panel.
                streakTarget = holdLockKind()
                guard streakTarget == .electricMeter, let searchStartedAt,
                      CACurrentMediaTime() - searchStartedAt >= Self.lateDetectorLockSeconds else { return }
            } else {
                scanHint = hint(for: asked, best: best)
            }
            guard let target = streakTarget else { return }
            // A lock needs an unbroken run: a frame without a usable box for the target starts the count over.
            guard let detection = best[target], detection.confidence >= EquipmentDetection.lockConfidence,
                  !Self.scanCaptureEnabled || detection.quality.map({ CaptureQuality.problem($0) == nil }) ?? true,
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
                hint: live && status == .ok ? scanHint : (target == nil && mode == .gasMeter ? gasHint : nil),
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
                sendMeterCrop(source: source)
            case .breakerPanel:
                panelGroundPosition = ground
                panelLockSource = source
            }
            resetHold()
            updateDetectorGate()
        }

        /// The locked meter cut from the same frame as its box, for a fallback meter photo. From 1–3 m the number is
        /// seldom legible, so the store keeps it only when the survey has no meter photo; the number scan up close is
        /// the real one. The detector's own box for a detector lock; for a hold or "Mark it myself", only a meter box
        /// under the dot. No box, no crop.
        private func sendMeterCrop(source: EquipmentLockSource) {
            // A scan capture hands over its own photo, the sharp crop it read.
            guard source != .scanCapture else { return }
            guard onMeterCrop != nil, let packet = freshScan, let pixels = packet.pixels else { return }
            let meterBoxes = pendingDetections.filter { $0.kind == .electricMeter }
            let detection: EquipmentDetection?
            if source == .detector {
                detection = meterBoxes.first
            } else {
                let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
                detection = meterBoxes.first {
                    Self.viewRect(for: $0.boundingBox, in: packet).insetBy(dx: -32, dy: -32).contains(center)
                }
            }
            guard let box = detection?.boundingBox else { return }
            let orientation = packet.visionOrientation
            Task.detached(priority: .utility) { [weak self] in
                guard let image = PlacementSceneController.meterCrop(pixels, box: box, orientation: orientation) else { return }
                await self?.deliverMeterCrop(image)
            }
        }

        private func deliverMeterCrop(_ image: UIImage) {
            onMeterCrop?(image)
        }

        private nonisolated static func meterCrop(
            _ pixels: CopiedPixels,
            box: CGRect,
            orientation: CGImagePropertyOrientation
        ) -> UIImage? {
            let upright = CIImage(cvPixelBuffer: pixels.buffer).oriented(orientation)
            let extent = upright.extent
            // Vision boxes are normalized to the upright image with the origin at the lower left, as Core Image is.
            let rect = CGRect(
                x: extent.minX + box.minX * extent.width,
                y: extent.minY + box.minY * extent.height,
                width: box.width * extent.width,
                height: box.height * extent.height
            )
            // A quarter more around the box, so the meter's collar and nameplate edge stay in the photo.
            let padded = rect.insetBy(dx: -rect.width * 0.125, dy: -rect.height * 0.125).integral.intersection(extent)
            guard !padded.isNull, padded.width >= 32, padded.height >= 32,
                  let image = cropContext.createCGImage(upright, from: padded) else { return nil }
            return UIImage(cgImage: image)
        }

        /// A box draws once the same kind sat in about the same spot in two of the last three packets,
        /// so one-frame blips never show. The current packet is already in `recentBoxes`.
        private func isSteady(_ detection: EquipmentDetection) -> Bool {
            let box = detection.boundingBox
            let agreeing = recentBoxes.filter { packet in
                guard let other = packet[detection.kind] else { return false }
                return hypot(other.midX - box.midX, other.midY - box.midY) < 0.15
            }
            return agreeing.count >= 2
        }

        /// Live boxes for both kinds, until that kind locks. A lock is a position, not a box left on the camera.
        private func refreshEquipmentBoxes() {
            guard arView.bounds.width > 1 else { return }
            var items: [EquipmentBoxOverlay.Item] = []
            if scanningEquipment, !coachingActive, trackingBlockedMessage == nil, let packet = freshScan {
                for detection in pendingDetections {
                    let locked = detection.kind == .electricMeter ? meterLock.locked : panelLock.locked
                    if locked || !isSteady(detection) { continue }
                    let rect = Self.viewRect(for: detection.boundingBox, in: packet)
                    guard rect.width > 2, rect.height > 2, rect.origin.x.isFinite, rect.origin.y.isFinite else { continue }
                    let onWall = pendingLandings[detection.kind] != nil
                    // The Live Survey's camera carries only its two lines, so release boxes have no text; the bottom
                    // line already says "aim at the wall". DEBUG keeps the label and the true score for tuning.
                    #if DEBUG
                    let title = (onWall ? detection.kind.title : "\(detection.kind.title) · not on a wall")
                        + String(format: " %.2f", detection.confidence)
                    #else
                    let title = ""
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

        /// Clears the scan's marks, battery, look-around, and skipped steps. The view also resets the survey's saved
        /// placement evidence.
        func restartScan() {
            passedLiveSteps = []
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
            // The capture gate locks the meter and panel. The dot stays as an aiming aid; the hold lock is off.
            if Self.scanCaptureEnabled {
                holdReticle.isHidden = true
                resetHold()
                return
            }
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

        // MARK: - Automatic capture

        /// The meter and the panel lock only through this gate: a steady, sharp, well-lit view of it on a wall, and
        /// the same label value read twice. The detector-streak and center-dot hold locks stay in the code, off:
        /// on their own they locked AC condensers as meters and any wall as the panel.
        private static let scanCaptureEnabled = true
        /// Consecutive detector evaluations (about 4 a second) that must pass every image check. Tune on device.
        private static let captureStreakRequired = 3
        /// Lowest true detector score that can be a capture candidate: the model's own NMS floor. Real meters close up
        /// score 0.25–0.38, and the label read decides. Tune on device.
        private static let captureMinConfidence: Float = 0.25
        /// "Same place" from one evaluation to the next. Tune on device.
        private static let captureMinIoU: CGFloat = 0.5
        /// Smallest box, as a share of the screen, whose print can be read. Tune on device.
        private static let captureMinArea: CGFloat = 0.06
        /// Under this share of the screen, a meter whose number will not read needs the phone closer. Tune on device.
        private static let captureCloseArea: CGFloat = 0.15
        /// A box this big is cut off by the frame. Tune on device.
        private static let captureMaxArea: CGFloat = 0.8
        /// The label seen more obliquely than this reads badly. Tune on device.
        private static let captureMaxObliqueDegrees: Float = 60
        /// OCR at most twice a second while a candidate passes, and once a second while searching by text alone.
        private static let captureReadInterval: CFTimeInterval = 0.5
        private static let textSearchReadInterval: CFTimeInterval = 1
        /// Two agreeing reads must fall inside this window. Tune on device.
        private static let captureReadWindow: CFTimeInterval = 4
        /// A text-first candidate stands this long after the read that found it.
        private static let textCandidateSeconds: CFTimeInterval = 1.2
        /// The candidate's wall spot moved this far between evaluations: the streak starts over. Tune on device.
        private static let captureMaxDriftMeters: Float = 0.15
        /// Reads taken this far from the current candidate were of something else and are dropped.
        private static let captureReadRadiusMeters: Float = 0.3
        /// Good frames with no value read before the hint says what to change.
        private static let captureEmptyReadsForHint = 2
        /// Evaluations a new hint must hold before it replaces the one on screen, so the line does not flicker.
        private static let hintSettleEvaluations = 2
        /// Text-first search for the meter too, when the detector gives no box. A meter word must be on the label.
        private static let textFirstMeterEnabled = true
        /// Seconds of searching for the meter before the late detector lock may happen, so the label read gets its
        /// chance first. Well inside the Live Survey's 60 s find wait. Tune on device.
        private static let lateDetectorLockSeconds: CFTimeInterval = 20

        /// One detector packet through the gate. Returns the bottom-line cue for the current target.
        private func evaluateCapture(_ packet: EquipmentScanFrame) -> CoachTip? {
            guard let target = holdLockKind() else {
                if capture.target != nil { resetCapture() }
                return nil
            }
            if capture.target != target {
                resetCapture()
                capture.target = target
            }
            let now = CACurrentMediaTime()
            // (1) Tracking. The bridge only runs on normal tracking; a packet can still land after tracking dropped.
            guard packet.status == .ok, trackingBlockedMessage == nil else {
                capture.breakStreak()
                logCapture(target, "blocked", "status=\(packet.status)")
                return nil
            }
            guard let candidate = captureCandidate(for: target, in: packet, now: now) else {
                capture.breakStreak()
                // Text first: with no box, read the middle of the screen for the label itself.
                if allowsTextFirst(target), let region = packet.centerRegion, let quality = packet.centerQuality,
                   CaptureQuality.problem(quality) == nil {
                    requestRead(target, packet: packet, region: region, textFirst: true, landing: nil, now: now)
                }
                logCapture(target, "no-candidate", Self.describe(packet.centerQuality))
                return nil
            }
            // (2) Same place as the last evaluation.
            var iou: CGFloat = 1
            if let last = capture.lastBox {
                iou = CaptureQuality.iou(last, candidate.box)
                if !candidate.textFirst, iou < Self.captureMinIoU { capture.breakStreak() }
            }
            let probe = EquipmentDetection(kind: target, confidence: 1, boundingBox: candidate.box)
            guard let landing = project(probe, in: packet) else {
                capture.breakStreak()
                logCapture(target, "not-on-wall", candidate.source)
                return .aimAtWall
            }
            if let lastLanding = capture.lastLanding, simd_distance(lastLanding, landing.position) > Self.captureMaxDriftMeters {
                capture.breakStreak()
            }
            capture.records.removeAll { record in
                record.landing.map { simd_distance($0, landing.position) > Self.captureReadRadiusMeters } ?? false
            }
            // Height above ground (0.3–2.5 m), separation from the other lock, and the "Not the …" ban.
            guard relockAllowed(target, point: landing.position) else {
                capture.breakStreak()
                logCapture(target, "banned", candidate.source)
                return nil
            }
            if let reason = lockRejection(target, at: landing.position, normal: landing.normal, checkHeight: true) {
                capture.breakStreak()
                logCapture(target, "rejected", "\(candidate.source) \(reason)")
                return nil
            }
            // (3) Big enough to read, and in the middle of the screen.
            let rect = Self.viewRect(for: candidate.box, in: packet)
            let viewWidth = max(packet.viewSize.width, 1)
            let viewHeight = max(packet.viewSize.height, 1)
            let area = rect.width * rect.height / (viewWidth * viewHeight)
            let centerX = rect.midX / viewWidth
            let centerY = rect.midY / viewHeight
            let inset = (1 - EquipmentScanBridge.centerFraction) / 2
            let camera = SIMD3<Float>(packet.cameraTransform.columns.3.x, packet.cameraTransform.columns.3.y, packet.cameraTransform.columns.3.z)
            let oblique = Self.obliqueDegrees(normal: landing.normal, from: landing.position, to: camera)
            var problem: CoachTip?
            if !candidate.textFirst, area < Self.captureMinArea {
                problem = .closerToLabel
            } else if area > Self.captureMaxArea {
                problem = .stepBack
            } else if centerX < inset || centerX > 1 - inset || centerY < inset || centerY > 1 - inset {
                let dx = centerX - 0.5
                let dy = centerY - 0.5
                problem = abs(dy) > abs(dx) ? (dy < 0 ? .lookUp : .pointDown) : (dx < 0 ? .scootLeft : .scootRight)
            } else if oblique > Self.captureMaxObliqueDegrees {
                problem = .faceLabel
            } else if let quality = candidate.quality {
                // (4) Sharp and (5) exposed.
                switch CaptureQuality.problem(quality) {
                case .tooDark: problem = .tooDark
                case .tooBright: problem = .tooBright
                case .blurry: problem = .holdStill
                case nil: break
                }
            } else {
                problem = .holdStill
            }
            let measured = String(
                format: "%@ area=%.3f c=(%.2f,%.2f) iou=%.2f oblique=%.0f %@",
                candidate.source, Double(area), Double(centerX), Double(centerY), Double(iou), Double(oblique),
                Self.describe(candidate.quality)
            ) + debugHeight(landing.position, normal: landing.normal)
            if let problem {
                capture.breakStreak()
                logCapture(target, "fail:\(problem)", measured)
                return problem
            }
            capture.streak += 1
            capture.lastBox = candidate.box
            capture.lastLanding = landing.position
            capture.landings.append((landing.position, landing.normal))
            if capture.landings.count > Self.captureStreakRequired {
                capture.landings.removeFirst(capture.landings.count - Self.captureStreakRequired)
            }
            // (6) Read the label on this good frame, at full resolution.
            let region = candidate.textFirst
                ? (packet.centerRegion ?? CaptureQuality.padded(candidate.box, by: 1))
                : CaptureQuality.padded(candidate.box, by: 0.125)
            requestRead(target, packet: packet, region: region, textFirst: candidate.textFirst, landing: landing.position, now: now)
            logCapture(target, "pass streak=\(capture.streak) reads=\(capture.records.count)", measured)
            if tryCapture() { return nil }
            if capture.records.isEmpty, capture.emptyReads >= Self.captureEmptyReadsForHint {
                switch target {
                case .electricMeter: return area < Self.captureCloseArea ? .closerToLabel : .faceLabel
                case .breakerPanel: return .openPanelDoor
                }
            }
            return target == .electricMeter ? .readingNumber : .readingBreaker
        }

        /// The detector's box for the target, a meter-labeled box standing in for the panel, or a label read by text.
        private func captureCandidate(for target: EquipmentKind, in packet: EquipmentScanFrame, now: CFTimeInterval) -> CaptureCandidate? {
            let boxes = packet.detections.filter { $0.confidence >= Self.captureMinConfidence }
            if let own = boxes.filter({ $0.kind == target }).max(by: { $0.confidence < $1.confidence }) {
                return CaptureCandidate(box: own.boundingBox, quality: own.quality, textFirst: false, source: "\(target.rawValue)-box")
            }
            // Off the demo wall the panel class almost never fires; panels come back as weak meter boxes. With the
            // meter already locked, a meter box somewhere else can be the panel. Only the main-breaker read decides.
            if target == .breakerPanel, meterLock.locked, let meter = meterWallHit {
                let stand = boxes
                    .filter { $0.kind == .electricMeter }
                    .sorted { $0.confidence > $1.confidence }
                    .first { box in
                        guard let landing = project(box, in: packet) else { return false }
                        return simd_distance(landing.position, meter.position) >= Self.lockSeparationMeters
                    }
                if let stand {
                    return CaptureCandidate(box: stand.boundingBox, quality: stand.quality, textFirst: false, source: "meter-box-as-panel")
                }
            }
            if allowsTextFirst(target), let text = capture.textCandidate, now - text.at <= Self.textCandidateSeconds {
                return CaptureCandidate(box: text.box, quality: packet.centerQuality, textFirst: true, source: "text")
            }
            return nil
        }

        private func allowsTextFirst(_ target: EquipmentKind) -> Bool {
            target == .breakerPanel || Self.textFirstMeterEnabled
        }

        /// Starts one OCR pass on this packet's copied pixels, unless one is running or ran too recently.
        private func requestRead(
            _ target: EquipmentKind,
            packet: EquipmentScanFrame,
            region: CGRect,
            textFirst: Bool,
            landing: SIMD3<Float>?,
            now: CFTimeInterval
        ) {
            let interval = textFirst && capture.textCandidate == nil ? Self.textSearchReadInterval : Self.captureReadInterval
            guard !capture.ocrInFlight, now - capture.lastOCRAt >= interval, let pixels = packet.pixels,
                  region.width > 0.01, region.height > 0.01 else { return }
            capture.ocrInFlight = true
            capture.lastOCRAt = now
            capture.pendingLanding = landing
            textReader.read(
                pixels,
                region: region,
                orientation: packet.visionOrientation,
                kind: target,
                textFirst: textFirst,
                generation: capture.generation
            ) { [weak self] read in
                Task { @MainActor in
                    self?.absorbRead(read)
                }
            }
        }

        private func absorbRead(_ read: ScanTextRead) {
            guard read.generation == capture.generation, read.kind == capture.target else { return }
            capture.ocrInFlight = false
            let now = CACurrentMediaTime()
            var value = read.value
            // Read by text alone, a long number is a meter number only on a label with a meter word.
            if read.textFirst, read.kind == .electricMeter, read.meter?.hasMeterCue != true { value = nil }
            #if DEBUG
            let preview = read.lines.prefix(6).joined(separator: " | ")
            Self.captureLog.debug("\(read.kind.rawValue, privacy: .public) read value=\(value ?? "-", privacy: .public) textFirst=\(read.textFirst) lines=\(read.lines.count) [\(preview, privacy: .public)]")
            #endif
            guard let value else {
                if !read.textFirst || capture.textCandidate != nil { capture.emptyReads += 1 }
                return
            }
            capture.emptyReads = 0
            if read.textFirst, let box = read.textBox {
                // Tiny label boxes jitter; compare them grown to twice their size.
                if let previous = capture.textCandidate,
                   CaptureQuality.iou(CaptureQuality.padded(previous.box, by: 0.5), CaptureQuality.padded(box, by: 0.5)) < Self.captureMinIoU {
                    capture.records.removeAll()
                    capture.breakStreak()
                }
                capture.textCandidate = (box, now)
            }
            capture.records.append(CaptureReadRecord(read: read, landing: capture.pendingLanding, at: now))
            capture.records.removeAll { now - $0.at > Self.captureReadWindow }
            if capture.records.count > 4 { capture.records.removeFirst(capture.records.count - 4) }
            #if DEBUG
            Self.captureLog.debug("\(read.kind.rawValue, privacy: .public) kept \(value, privacy: .public) records=\(self.capture.records.compactMap(\.read.value).joined(separator: ","), privacy: .public)")
            #endif
            _ = tryCapture()
        }

        /// Locks and hands over the photo once the image checks held for the whole streak and the last read agrees
        /// with an earlier one. Same guards as every other lock path.
        @discardableResult
        private func tryCapture() -> Bool {
            guard let target = capture.target, capture.streak >= Self.captureStreakRequired,
                  let latest = capture.records.last, let value = latest.read.value, let image = latest.read.image,
                  capture.records.dropLast().contains(where: { $0.read.value == value }),
                  let lastLanding = capture.landings.last else { return false }
            let count = Float(capture.landings.count)
            let point = capture.landings.reduce(SIMD3<Float>.zero) { $0 + $1.point } / count
            let normalSum = capture.landings.reduce(SIMD3<Float>.zero) { $0 + $1.normal }
            let normal = simd_length(normalSum) > 0.001 ? simd_normalize(normalSum) : lastLanding.normal
            guard trackingBlockedMessage == nil, relockAllowed(target, point: point),
                  lockRejection(target, at: point, normal: normal, checkHeight: true) == nil else { return false }
            lockEquipment(target, at: EquipmentLock.Sample(point: point, normal: normal), source: .scanCapture)
            let result = ScanCapture(
                kind: target,
                image: UIImage(cgImage: image),
                meterNumber: target == .electricMeter ? latest.read.meter?.number : nil,
                mainBreakerAmps: target == .breakerPanel ? latest.read.breaker?.amps : nil
            )
            logCapture(target, "CAPTURED", "value=\(value) reads=\(capture.records.count) image=\(image.width)x\(image.height)")
            resetCapture()
            onScanCapture?(result)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            emit()
            return true
        }

        private func resetCapture() {
            let generation = capture.generation + 1
            capture = ScanCaptureState()
            capture.generation = generation
            shownCaptureHint = nil
            proposedCaptureHint = nil
            proposedCaptureHintCount = 0
        }

        /// A new cue shows at once over nothing; otherwise it must repeat before it replaces the one on screen.
        private func settledCaptureHint(_ proposed: CoachTip?) -> CoachTip? {
            if proposed == shownCaptureHint {
                proposedCaptureHintCount = 0
                return shownCaptureHint
            }
            if proposed == proposedCaptureHint {
                proposedCaptureHintCount += 1
            } else {
                proposedCaptureHint = proposed
                proposedCaptureHintCount = 1
            }
            if shownCaptureHint == nil || proposedCaptureHintCount >= Self.hintSettleEvaluations {
                shownCaptureHint = proposed
                proposedCaptureHintCount = 0
            }
            return shownCaptureHint
        }

        /// Degrees between the wall's normal and the line to the camera. Either face of the normal counts.
        private static func obliqueDegrees(normal: SIMD3<Float>, from point: SIMD3<Float>, to camera: SIMD3<Float>) -> Float {
            let toCamera = camera - point
            let length = simd_length(toCamera) * simd_length(normal)
            guard length > 1e-5 else { return 0 }
            let cosine = min(1, abs(simd_dot(toCamera, normal)) / length)
            return acos(cosine) * 180 / .pi
        }

        private static func describe(_ quality: CaptureReading?) -> String {
            guard let quality else { return "quality=-" }
            return String(
                format: "sharp=%.0f luma=%.0f dark=%.2f clip=%.2f",
                Double(quality.sharpness), Double(quality.meanLuma), Double(quality.darkFraction), Double(quality.clippedFraction)
            )
        }

        /// Height above the ground under the spot, for tuning the 0.3–2.5 m gate. DEBUG only: it costs a raycast.
        private func debugHeight(_ point: SIMD3<Float>, normal: SIMD3<Float>) -> String {
            #if DEBUG
            guard let ground = groundUnder(point, normal: normal) else { return " height=-" }
            return String(format: " height=%.2f", Double(point.y - ground.y))
            #else
            return ""
            #endif
        }

        private func logCapture(_ target: EquipmentKind, _ decision: String, _ detail: String) {
            #if DEBUG
            Self.captureLog.debug("\(target.rawValue, privacy: .public) \(decision, privacy: .public) \(detail, privacy: .public)")
            #endif
        }

        // MARK: - Gas meter hold

        /// Gas step: the ring held on the gas meter marks it, no tap. Tune every number on device.
        private static let gasHoldEnabled = true
        private static let gasHoldSeconds: CFTimeInterval = 1
        /// On the ground itself, or with no ground estimate, the hold is longer, so a phone pointed at the feet
        /// while walking does not mark the gas meter.
        private static let gasGroundHoldSeconds: CFTimeInterval = 2
        /// Below this height the spot counts as the ground itself.
        private static let gasGroundBandMeters: Float = 0.08
        /// Gas meters sit low on their riser.
        private static let gasMaxHeightMeters: Float = 1.2
        private static let gasMaxRangeMeters: Float = 4
        /// A gas meter is its own object, not the electric meter or the panel.
        private static let gasClearanceFromEquipmentMeters: Float = 0.6
        /// Time into the gas step before a hold counts, so the ring does not mark whatever it rested on as the step began.
        private static let gasAimSettleSeconds: CFTimeInterval = 1.5
        private static let gasHoldDriftMeters: Float = 0.15
        /// A spot on the ground counts only this close to a detected wall: gas meters stand against the house.
        private static let gasGroundWallMeters: Float = 1

        private func updateGasHold(at point: CGPoint) {
            guard Self.gasHoldEnabled, gasPoint == nil else {
                gasHint = nil
                resetGasHold()
                return
            }
            let now = CACurrentMediaTime()
            if gasAimSince == nil { gasAimSince = now }
            guard now - (gasAimSince ?? now) >= Self.gasAimSettleSeconds else { return }
            guard trackingBlockedMessage == nil, let position = raycastPoint(at: point, alignment: .any)?.position.simd,
                  simd_distance(arView.cameraTransform.translation, position) <= Self.gasMaxRangeMeters,
                  ![meterWallHit?.position, panelWallHit?.position].contains(where: { other in
                      other.map { simd_distance($0, position) < Self.gasClearanceFromEquipmentMeters } ?? false
                  }) else {
                gasHint = .holdOnGas
                resetGasHold()
                return
            }
            let height = gasGroundY(under: position).map { position.y - $0 }
            if let height, height > Self.gasMaxHeightMeters {
                gasHint = .holdOnGas
                resetGasHold()
                return
            }
            let onGround = height.map { $0 < Self.gasGroundBandMeters } ?? true
            if onGround, !isNearWall(position, within: Self.gasGroundWallMeters) {
                gasHint = .holdOnGas
                resetGasHold()
                return
            }
            let needed = onGround ? Self.gasGroundHoldSeconds : Self.gasHoldSeconds
            holdReticle.center = point
            holdReticle.isHidden = false
            gasHint = .holdStill
            guard let anchor = gasHoldAnchor, let since = gasHoldSince,
                  simd_distance(anchor, position) <= Self.gasHoldDriftMeters else {
                gasHoldAnchor = position
                gasHoldSince = now
                return
            }
            guard now - since >= needed else { return }
            placeMarker(kind: .gasMeter, at: anchor)
            #if DEBUG
            Self.captureLog.debug("gas marked height=\(height ?? -1, format: .fixed(precision: 2)) held=\(now - since, format: .fixed(precision: 2))")
            #endif
            gasHint = nil
            resetGasHold()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            emit()
        }

        private func resetGasHold() {
            gasHoldAnchor = nil
            gasHoldSince = nil
            holdReticle.isHidden = true
        }

        /// True when a detected vertical plane (a wall) stands within `meters` of the spot, measured across the floor.
        private func isNearWall(_ point: SIMD3<Float>, within meters: Float) -> Bool {
            planes.values.contains { plane in
                guard let normal = horizontalUnit(plane.normal) else { return false }
                let offset = SIMD3<Float>(point.x - plane.center.x, 0, point.z - plane.center.z)
                let away = abs(simd_dot(offset, normal))
                let along = simd_length(offset - simd_dot(offset, normal) * normal)
                return away <= meters && along <= max(plane.width, plane.length) / 2 + 0.5
            }
        }

        /// The ground straight under a spot, from a plane; else the ground found under the meter or panel.
        private func gasGroundY(under point: SIMD3<Float>) -> Float? {
            let origin = point + SIMD3<Float>(0, 0.05, 0)
            for allowing: ARRaycastQuery.Target in [.existingPlaneGeometry, .estimatedPlane] {
                let query = ARRaycastQuery(origin: origin, direction: SIMD3(0, -1, 0), allowing: allowing, alignment: .horizontal)
                if let hit = arView.session.raycast(query).first {
                    return hit.worldTransform.columns.3.y
                }
            }
            return meterGroundPosition?.y ?? panelGroundPosition?.y
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

        /// Short copy that matches a CoachTip, so the bottom line draws its graphic. It is also what a blocked tap reports.
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
