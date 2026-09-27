import Foundation
import Observation
import os

// MARK: - Integration (PlacementARView and PlacementSceneController, names as of integrate-3-step 0071159)
//
// WHAT THIS IS. A second opinion for the Live Survey's bottom line, for one moment only: the phone's own tip has
// been on screen for 8 s or more on findMeter or findPanel, no gate has passed in 3 s, and nothing is locked.
// Every per-frame job (detector, capture gate, OCR, lock, capture, step completion) stays on the phone. Jev reads
// bucketed text only (`JevLiveContext`), picks from instructions the app wrote (`JevLiveInstruction`), and its
// answer reaches only the coach's `suggestion` and the log. It never locks, captures, passes a step, moves a
// clock, or changes a rule, the placement tone, or its color. With no key, or mode `.off`, it makes no call and
// `suggestion` stays nil, so the app behaves exactly as it does today.
//
// MODES. `JevLiveCoach.Mode.configured`: UserDefaults "JevLiveMode" (scheme launch argument `-JevLiveMode show`,
// `shadow`, or `off`) wins; then "JevLiveShadow" (`-JevLiveShadow YES`) asks and logs without showing; otherwise every
// build runs `.show`: with a key, Jev tips and the one-option rule tips appear on the bottom line. No key, no call.
//
// 1. BUILD A SNAPSHOT about once a second and whenever the bottom line changes, from state the view already has.
//
//        @State private var jevCoach = JevLiveCoach()
//
//        private var jevStep: JevLiveContext.Step? {
//            switch step {
//            case .findMeter: .findMeter
//            case .findPanel: .findPanel
//            default: nil
//            }
//        }
//
//        private func jevSnapshot(_ assessment: SurveyAssessment?) -> JevLiveSnapshot {
//            var holds: JevLiveHolds = []
//            if statusMessage != nil || cameraProblem != nil { holds.insert(.error) }
//            if pausedForCapture { holds.insert(.paused) }
//            if trackingMessage != nil { holds.insert(.tracking) }
//            if coachingIsActive { holds.insert(.coaching) }
//            if flashTip != nil { holds.insert(.flash) }
//            if scanFeedback.detector != .ok { holds.insert(.detectorDown) }
//            if labelBeingRead { holds.insert(.reading) }
//            if (step == .findMeter && meterMarked) || (step == .findPanel && panelMarked) { holds.insert(.locked) }
//            if !isVisible || isLeaving { holds.insert(.leaving) }
//            return JevLiveSnapshot(
//                step: jevStep,
//                deviceTip: deviceFeedback(assessment).map { JevDeviceTip(copy: $0.text) },
//                deviceTipIsCaptureHint: lockTarget != nil && scanFeedback.hint != nil,
//                scan: store.placementController?.jevScanSignals() ?? JevScanSignals(),
//                holds: holds
//            )
//        }
//
//    `deviceTip` must be the phone's own line, never the Jev tip (see 3), or the coach would see its own tip as a
//    change of the device line and clear it. `JevDeviceTip(copy:)` maps the exact `CoachTip` copy; a line it does
//    not know is `.other`.
//
// 2. FEED THE COACH. Pull, do not publish: the snapshot is built only when the tick or a line change asks for it,
//    so nothing new re-renders the view at packet rate.
//
//        .task(id: jevStep) {
//            while !Task.isCancelled {
//                jevCoach.update(jevSnapshot(liveAssessment))
//                try? await Task.sleep(for: .seconds(1))
//            }
//        }
//        .onChange(of: scanFeedback) { _, _ in jevCoach.update(jevSnapshot(liveAssessment)) }
//        .onAppear { jevCoach.begin(surveyID: store.session.id) }          // after controller.resume()
//        .onDisappear { jevCoach.end() }
//        // lock and capture:
//        .onChange(of: meterMarked) { _, marked in if marked { jevCoach.noteProgress(.lock) } }
//        .onChange(of: panelMarked) { _, marked in if marked { jevCoach.noteProgress(.lock) } }
//        // and in the onScanCapture callback: jevCoach.noteProgress(.capture)
//
// 3. SHOW THE SUGGESTION as the lowest-priority bottom-line feedback: below error, tracking, flash, capture
//    feedback and the detector hint; above only the step's motion line. Split `feedback(_:)` in two:
//
//        /// Everything `feedback(_:)` returns today down to and including the gas hint (error, status, paused,
//        /// tracking, flash, captureTip, detector down, scanFeedback.hint, gas hint). Nil means the step line.
//        private func feedbackAboveJev(_ assessment: SurveyAssessment?) -> Feedback? { … }
//
//        /// The phone's own line, for the snapshot. Never reads jevCoach.
//        private func deviceFeedback(_ assessment: SurveyAssessment?) -> Feedback? {
//            feedbackAboveJev(assessment) ?? stepFeedback(assessment)
//        }
//
//        private func feedback(_ assessment: SurveyAssessment?) -> Feedback? {
//            if let above = feedbackAboveJev(assessment) { return above }
//            if let tip = jevCoach.suggestion {
//                return Feedback(text: tip.text, symbol: tip.symbol, tint: .primary, pulses: true)
//            }
//            return stepFeedback(assessment)
//        }
//
//    Read `jevCoach.suggestion` only there. Never write it into `captureTip`, `scanFeedback`, or `flashTip`, and
//    never read it from `labelBeingRead`, `runFindClock`, `pass(_:)`, `stepFeedback`, or any clock: `labelBeingRead`
//    feeds the find clock's reading grace, so a Jev tip there would change step timing. The pacer paces the Jev
//    line like any other; the coach itself keeps it 3–8 s and never re-shows it within 15 s, so VoiceOver
//    (`.updatesFrequently`) hears at most one Jev change every 3 s. Optional DEBUG badge: a small "Jev" capsule
//    when `jevCoach.suggestion?.source == .jev`. No confidence number is ever shown live.
//
// 4. RESET. A snapshot whose `step` differs from the last one bumps the coach's step epoch, cancels the request in
//    flight, and clears the tip, the device-tip clock, and the 15 s memory. `noteProgress(.lock / .capture)` and
//    `end()` do the same. A gate pass (from the rings), a tracking or error hold, or a device-line change that
//    holds for 1 s also clears the tip. Nothing else is needed on step change or exit.
//
// SIGNALS THE VIEW AND CONTROLLER DO NOT HAVE YET (the coach stays silent until `scan.available` is true):
//    a. `private var jevRings = JevScanRings()` on PlacementSceneController, and
//       `func jevScanSignals() -> JevScanSignals { jevRings.signals() }`.
//    b. One `jevRings.record(JevPacketSignal(...))` per `evaluateCapture` exit: `targetSeen` = a box of the target
//       kind at `captureMinConfidence` in `packet.detections`; `outcome` from the exit taken
//       (`JevGateOutcome(gateDecision:)` parses the string `logCapture` already gets); `area`, `onWall`
//       (`project` hit), and `light` (`CaptureQuality.problem` → dark / bright / ok) from the candidate.
//    c. One `jevRings.record(read:cues:textFirst:)` per `absorbRead`: `.appliance` needs ScanTextParser to report
//       `isApplianceLabel` (today it folds into value == nil, which the gate counts as an empty read and answers
//       "Get closer to the label"); `.value(agreesWithEarlier:)` compares to `capture.records` on the phone (the
//       digits never reach the ring); cue flags need the parser's private word lists exposed as
//       `Set<JevLiveContext.Cue>` (meter_word from `hasMeterCue`, panel_word from the panel nameplate/breaker words,
//       appliance_word from `isApplianceLabel`).
//    d. `jevRings.reset()` inside `resetCapture()` and when the target changes.
//    e. Optional, later: blur risk (|ω| × `ARCamera.exposureDuration` × fx) as `JevPacketSignal.blurPixels`.
//    f. The `feedbackAboveJev` / `deviceFeedback` split in the view (3).
//    g. Optional: FrameRecorder (claude/par-e-recorder). Point `jevCoach.onRecord` at a buffer and attach
//       `entry.metadata` to the next "periodic" frame's metadata; do not record extra frames for Jev.
//
// TEST HOOKS (DEBUG, no curl): Review → Jev advisory → "Live lane (DEBUG)": Self-check (no network), Replay (no
// network), Probe (one call per fixture with the real key), Latency ×20. See `JevLiveDebug`. Every request,
// reply, and decision also goes to os_log (subsystem "BaseAR", category "JevLive") in DEBUG builds.

/// What the coach sends through. `JevTransport` in the app; a stub in tests.
protocol JevLiveSending: Sendable {
    var isAvailable: Bool { get }
    func post(_ body: Data, profile: JevTransport.Profile) async -> JevCallResult
    func warmUp() async
}

extension JevTransport: JevLiveSending {}

/// The Live Survey's Jev lane: triggers, debounce, one request in flight, cancel on change, cache, backoff, the
/// display policy, and the log. Publishes at most one `suggestion`, read by the view's `feedback(_:)` only.
@MainActor
@Observable
final class JevLiveCoach {
    enum Mode: String, Sendable, CaseIterable {
        case off
        /// Ask and log; show nothing. For tuning: UserDefaults "JevLiveShadow" (`-JevLiveShadow YES`).
        case shadow
        /// Jev and one-option rule tips appear on the bottom line. The default: the owner tried the live tips on the
        /// phone and kept them. Still nothing without a key (`isEnabled`).
        case show

        static var configured: Mode {
            if let raw = UserDefaults.standard.string(forKey: "JevLiveMode"), let mode = Mode(rawValue: raw) {
                return mode
            }
            return UserDefaults.standard.bool(forKey: "JevLiveShadow") ? .shadow : .show
        }
    }

    enum Source: String, Sendable {
        /// Jev picked it among two or more options.
        case jev
        /// Exactly one option held, so the code picked it without asking (the fixed-rule baseline).
        case rule
    }

    struct Suggestion: Equatable, Sendable {
        let instruction: JevLiveInstruction
        let step: JevLiveContext.Step
        let source: Source
        /// Jev's `confidence`; nil for a rule tip. For logs and a DEBUG badge only, never shown live.
        let confidence: Double?
        /// p(pick) − p(none); nil for a rule tip.
        let margin: Double?
        let shownAt: ContinuousClock.Instant
        let seq: Int?

        var text: String { instruction.copy(for: step) }
        var symbol: String { instruction.symbol }

        func age(at now: ContinuousClock.Instant = .now) -> Duration { now - shownAt }
    }

    enum Progress: String, Sendable {
        case gatePass = "gate_pass"
        case lock
        case capture
    }

    /// The one suggestion to show, only in `.show` mode. Everything else on the coach is ignored by Observation, so
    /// the view re-renders only when this changes.
    private(set) var suggestion: Suggestion?

    var mode: Mode {
        didSet {
            guard mode != oldValue else { return }
            if mode == .off { reset("mode_off") } else { publish() }
        }
    }

    /// Every request, reply, and decision, for FrameRecorder or a test. Called on the main actor.
    @ObservationIgnored var onRecord: (@MainActor (JevLiveLogEntry) -> Void)?
    /// The last 80 log entries (DEBUG builds only).
    @ObservationIgnored private(set) var recentLog: [JevLiveLogEntry] = []

    @ObservationIgnored private let sender: any JevLiveSending
    @ObservationIgnored private let clock: @MainActor () -> ContinuousClock.Instant

    /// 401 / 403: off for this app run. 422: off for that question-set version.
    private static var keyRejected = false
    private static var rejectedQuestionVersion: Int?

    static let log = Logger(subsystem: "BaseAR", category: "JevLive")

    init(
        mode: Mode = .configured,
        sender: any JevLiveSending = JevTransport.shared,
        clock: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
    ) {
        self.mode = mode
        self.sender = sender
        self.clock = clock
    }

    /// Calls happen only with a key, a mode other than `.off`, and no 401 / 403 / 422 this run.
    var isEnabled: Bool {
        mode != .off && sender.isAvailable && !Self.keyRejected
            && Self.rejectedQuestionVersion != JevLiveQuestions.version
    }

    // MARK: - State (ignored by Observation)

    struct FreshnessKey: Hashable, Sendable {
        let epoch: Int
        let tip: JevDeviceTip
        let mainFail: JevLiveContext.Fail
        let seen: JevLiveContext.Seen
        let options: [JevLiveInstruction]
    }

    private struct AskKey: Hashable {
        let key: FreshnessKey
        let stuck: JevLiveContext.Stuck
    }

    private struct Evaluation {
        let context: JevLiveContext
        let options: [JevLiveInstruction]
        let key: FreshnessKey
    }

    private struct RequestInfo {
        let seq: Int
        let epoch: Int
        let key: FreshnessKey
        let context: JevLiveContext
        let options: [JevLiveInstruction]
        let trigger: String
        let sentAt: ContinuousClock.Instant
        let body: Data
    }

    private struct InFlight {
        let request: RequestInfo
        let task: Task<Void, Never>
    }

    private struct PendingOutcome {
        let seq: Int?
        let instruction: JevLiveInstruction
        let source: Source
        let at: ContinuousClock.Instant
    }

    @ObservationIgnored private var surveyID: UUID?
    @ObservationIgnored private var begunAt: ContinuousClock.Instant?
    @ObservationIgnored private var surveySends = 0
    @ObservationIgnored private var stepSends = 0
    @ObservationIgnored private var step: JevLiveContext.Step?
    @ObservationIgnored private var stepEpoch = 0
    @ObservationIgnored private var seq = 0
    /// The phone's own line and since when (a change counts once it holds `deviceTipHold`).
    @ObservationIgnored private var tip: JevDeviceTip?
    @ObservationIgnored private var tipSince: ContinuousClock.Instant?
    @ObservationIgnored private var pendingTip: (tip: JevDeviceTip?, since: ContinuousClock.Instant)?
    @ObservationIgnored private var latest: JevLiveSnapshot?
    @ObservationIgnored private var inFlight: InFlight?
    @ObservationIgnored private var lastSentAt: ContinuousClock.Instant?
    @ObservationIgnored private var lastAsked: AskKey?
    @ObservationIgnored private var candidate: (key: FreshnessKey, since: ContinuousClock.Instant)?
    @ObservationIgnored private var cache: [Data: JevLiveAnswer] = [:]
    @ObservationIgnored private var cacheOrder: [Data] = []
    @ObservationIgnored private var cooldownUntil: ContinuousClock.Instant?
    /// What would be on screen in `.show` mode. `.shadow` keeps it too, so shadow logs match what show would do.
    @ObservationIgnored private var displayed: Suggestion?
    @ObservationIgnored private var leftScreenAt: [JevLiveInstruction: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var pendingOutcome: PendingOutcome?
    @ObservationIgnored private var lastNote: String?
    @ObservationIgnored private var decisionCounts: [String: Int] = [:]

    // MARK: - Lifecycle

    /// The Live Survey appeared. Per-survey counters and the cache reset when the survey changes. Warms the
    /// connection once when the lane is on.
    func begin(surveyID: UUID) {
        let now = clock()
        if self.surveyID != surveyID {
            self.surveyID = surveyID
            surveySends = 0
            cache = [:]
            cacheOrder = []
            decisionCounts = [:]
        }
        begunAt = now
        record(.begin, fields: [
            "mode": mode.rawValue,
            "enabled": "\(isEnabled)",
            "model": JevTransport.pinnedModel,
            "questions_v": "\(JevLiveQuestions.version)"
        ])
        guard isEnabled else { return }
        let sender = self.sender
        Task { await sender.warmUp() }
    }

    /// The Live Survey is gone. Cancels, clears, and logs the per-survey counts.
    func end() {
        let now = clock()
        cancelInFlight("exit")
        clear("exit", now: now)
        resolveOutcome("exit", now: now)
        record(.end, fields: summaryFields)
        leaveStep()
        step = nil
        latest = nil
    }

    /// For `FrameRecorder.shared.end(summary:)`.
    var summary: [String: any Sendable] {
        [
            "jevMode": mode.rawValue,
            "jevEnabled": isEnabled,
            "jevSends": surveySends,
            "jevDecisions": decisionCounts
        ]
    }

    /// A lock, a capture, or a gate pass: cancel, clear, and log the weak label (which tip was up, which failure
    /// held) for scoring shadow picks offline.
    func noteProgress(_ event: Progress) {
        guard isEnabled else { return }
        let now = clock()
        var fields = ["event": event.rawValue, "tip_tried": tip?.rawValue ?? "-"]
        if let latest { fields["main_fail"] = latest.scan.mainFail.rawValue; fields["seen"] = latest.scan.seen.rawValue }
        if let tipSince { fields["tip_ms"] = "\(JevTransport.milliseconds(now - tipSince))" }
        record(.progress, fields: fields)
        resolveOutcome(event.rawValue, now: now)
        cancelInFlight(event.rawValue)
        clear(event.rawValue, now: now)
        candidate = nil
    }

    // MARK: - Update

    /// Call about once a second and whenever the bottom line changes. Cheap when nothing is due.
    func update(_ snapshot: JevLiveSnapshot) {
        let now = clock()
        guard isEnabled else {
            if displayed != nil || inFlight != nil || step != nil {
                reset("lane_off")
                leaveStep()
                step = nil
            }
            return
        }
        latest = snapshot
        if snapshot.step != step { enterStep(snapshot.step, now: now) }
        guard snapshot.step != nil else { return }

        trackDeviceTip(snapshot.deviceTip, now: now)
        settleOutcome(now: now)
        if let hold = snapshot.holds.intersection(.clearing).names.first { clear("hold_\(hold)", now: now) }
        if snapshot.scan.passedRecently { clear("gate_pass", now: now) }
        if let displayed, displayed.age(at: now) >= JevLiveTuning.maxDwell { clear("max_dwell", now: now) }

        guard let evaluation = evaluate(snapshot, now: now) else {
            candidate = nil
            return
        }
        if let inFlight, inFlight.request.key != evaluation.key { cancelInFlight("key_changed") }
        // The tip on screen no longer fits the state (its condition stopped holding): it goes after its minimum dwell.
        if let shown = displayed, !evaluation.options.contains(shown.instruction),
           shown.age(at: now) >= JevLiveTuning.minDwell {
            clear("condition_gone", now: now)
        }
        if let hold = holdReason(snapshot) {
            note("skip_\(hold)", evaluation.key)
            return
        }
        // Debounce: the freshness key must hold before anything is shown or sent.
        guard let candidate, candidate.key == evaluation.key else {
            self.candidate = (evaluation.key, now)
            return
        }
        guard now - candidate.since >= JevLiveTuning.debounce else { return }

        switch evaluation.options.count {
        case 0: note("skip_no_options", evaluation.key)
        case 1: offerRule(evaluation, snapshot: snapshot, now: now)
        default: considerAsking(evaluation, now: now)
        }
    }

    // MARK: - Steps and the device line

    private func enterStep(_ newStep: JevLiveContext.Step?, now: ContinuousClock.Instant) {
        cancelInFlight("step_changed")
        clear("step_changed", now: now)
        resolveOutcome("step_changed", now: now)
        leaveStep()
        step = newStep
        record(.step, fields: ["to": newStep?.rawValue ?? "none"])
    }

    private func leaveStep() {
        stepEpoch += 1
        stepSends = 0
        tip = nil
        tipSince = nil
        pendingTip = nil
        candidate = nil
        lastAsked = nil
        leftScreenAt = [:]
        lastNote = nil
    }

    private func trackDeviceTip(_ newTip: JevDeviceTip?, now: ContinuousClock.Instant) {
        guard tipSince != nil else {
            tip = newTip
            tipSince = now
            return
        }
        if newTip == tip {
            pendingTip = nil
            return
        }
        if let pending = pendingTip, pending.tip == newTip {
            guard now - pending.since >= JevLiveTuning.deviceTipHold else { return }
            tip = newTip
            tipSince = pending.since
            pendingTip = nil
            candidate = nil
            clear("device_tip_changed", now: now)
        } else {
            pendingTip = (newTip, now)
        }
    }

    private func evaluate(_ snapshot: JevLiveSnapshot, now: ContinuousClock.Instant) -> Evaluation? {
        guard let step = snapshot.step, snapshot.scan.available, let tip, tip != .reading, let tipSince,
              let stuck = JevLiveContext.Stuck(onScreenFor: now - tipSince) else { return nil }
        let context = JevLiveContext(step: step, stuck: stuck, tipTried: tip, scan: snapshot.scan)
        let options = JevLiveQuestions.options(
            for: context,
            textFirstReadRecently: snapshot.scan.textFirstReadRecently,
            excluding: recentlyLeft(now: now)
        )
        let key = FreshnessKey(epoch: stepEpoch, tip: tip, mainFail: context.mainFail, seen: context.seen, options: options)
        return Evaluation(context: context, options: options, key: key)
    }

    private func holdReason(_ snapshot: JevLiveSnapshot) -> String? {
        if let first = snapshot.holds.names.first { return first }
        if snapshot.scan.passedRecently { return "gate_pass" }
        return nil
    }

    private func recentlyLeft(now: ContinuousClock.Instant) -> Set<JevLiveInstruction> {
        leftScreenAt = leftScreenAt.filter { now - $0.value < JevLiveTuning.reshowAfter }
        return Set(leftScreenAt.keys)
    }

    // MARK: - One option: the rule

    private func offerRule(_ evaluation: Evaluation, snapshot: JevLiveSnapshot, now: ContinuousClock.Instant) {
        let pick = evaluation.options[0]
        if displayed?.instruction == pick { return }
        if snapshot.deviceTipIsCaptureHint, !JevLiveTuning.mayReplaceCaptureHint {
            note("rule_outranked_\(pick.rawValue)", evaluation.key)
            return
        }
        if let shown = displayed {
            guard shown.age(at: now) >= JevLiveTuning.minDwell else { return }
            clear("replaced", now: now)
        }
        present(pick, source: .rule, answer: nil, seq: nil, context: evaluation.context, options: evaluation.options, now: now)
    }

    // MARK: - Two or more options: ask Jev

    private func considerAsking(_ evaluation: Evaluation, now: ContinuousClock.Instant) {
        let ask = AskKey(key: evaluation.key, stuck: evaluation.context.stuck)
        guard ask != lastAsked, inFlight == nil else { return }
        if let cooldownUntil, now < cooldownUntil {
            note("skip_cooling_down", evaluation.key)
            return
        }
        if let lastSentAt, now - lastSentAt < JevLiveTuning.minSendGap { return }
        guard stepSends < JevLiveTuning.maxSendsPerStep, surveySends < JevLiveTuning.maxSendsPerSurvey else {
            note("skip_cap_reached", evaluation.key)
            return
        }
        let body: Data
        do {
            body = try JevLiveQuestions.requestBody(context: evaluation.context, options: evaluation.options)
        } catch {
            note("skip_encode_failed", evaluation.key)
            return
        }
        let trigger = lastAsked?.key == evaluation.key ? "stuck_bucket" : "stuck"
        lastAsked = ask
        seq += 1
        let request = RequestInfo(
            seq: seq,
            epoch: stepEpoch,
            key: evaluation.key,
            context: evaluation.context,
            options: evaluation.options,
            trigger: trigger,
            sentAt: now,
            body: body
        )
        if let cached = cache[body] {
            record(.reply, seq: request.seq, fields: answerFields(cached).merging([
                "cache_hit": "true", "trigger": trigger, "state": evaluation.context.encodedString
            ]) { $1 })
            decide(cached, for: request)
            return
        }
        send(request)
    }

    private func send(_ request: RequestInfo) {
        stepSends += 1
        surveySends += 1
        lastSentAt = request.sentAt
        #if DEBUG
        if request.body.count > JevLiveTuning.bodyBudgetBytes {
            Self.log.error("request body \(request.body.count) B is over the \(JevLiveTuning.bodyBudgetBytes) B budget")
        }
        #endif
        record(.request, seq: request.seq, fields: [
            "trigger": request.trigger,
            "state": request.context.encodedString,
            "options": request.options.map(\.rawValue).joined(separator: ","),
            "baseline": JevLiveQuestions.baselinePick(request.options)?.rawValue ?? "-",
            "bytes": "\(request.body.count)",
            "step_sends": "\(stepSends)",
            "survey_sends": "\(surveySends)"
        ])
        let sender = self.sender
        let body = request.body
        let task = Task { @MainActor [weak self] in
            let result = await sender.post(body, profile: .live)
            self?.receive(result, for: request)
        }
        inFlight = InFlight(request: request, task: task)
    }

    private func cancelInFlight(_ reason: String) {
        guard let inFlight else { return }
        inFlight.task.cancel()
        self.inFlight = nil
        record(.cancel, seq: inFlight.request.seq, fields: ["reason": reason])
    }

    private func receive(_ result: JevCallResult, for request: RequestInfo) {
        guard inFlight?.request.seq == request.seq else {
            if case .failure(.cancelled) = result { return }
            record(.reply, seq: request.seq, fields: ["dropped": "superseded"])
            return
        }
        inFlight = nil
        switch result {
        case .failure(let failure):
            handleFailure(failure, for: request)
        case .success(let reply):
            let answer = JevLiveAnswer(reply.answers[JevLiveQuestions.questionID])
            var fields: [String: String] = [
                "status": "\(reply.status)",
                "ms": "\(JevTransport.milliseconds(reply.roundTrip))",
                "attempts": "\(reply.attempts)",
                "model": reply.model ?? "-",
                "in_tokens": reply.usage?.inputTokens.map(String.init) ?? "-",
                "out_tokens": reply.usage?.outputTokens.map(String.init) ?? "-",
                "request_id": reply.requestID ?? "-",
                "net": reply.network?.summary ?? "-"
            ]
            if let answer { fields.merge(answerFields(answer)) { $1 } }
            record(.reply, seq: request.seq, fields: fields)
            guard let answer else {
                cooldownUntil = clock() + JevLiveTuning.cooldown
                return
            }
            remember(answer, for: request.body)
            decide(answer, for: request)
        }
    }

    private func remember(_ answer: JevLiveAnswer, for body: Data) {
        if cache[body] == nil { cacheOrder.append(body) }
        cache[body] = answer
        while cacheOrder.count > JevLiveTuning.cacheEntries {
            cache[cacheOrder.removeFirst()] = nil
        }
    }

    private func handleFailure(_ failure: JevCallFailure, for request: RequestInfo) {
        let now = clock()
        record(.failure, seq: request.seq, fields: ["error": failure.description])
        switch failure {
        case .cancelled, .noKey:
            return
        case .http(let status, _, _, _) where status == 401 || status == 403:
            Self.keyRejected = true
            reset("key_rejected")
        case .http(422, _, _, _):
            Self.rejectedQuestionVersion = JevLiveQuestions.version
            reset("bad_request_v\(JevLiveQuestions.version)")
        case .constrained:
            cooldownUntil = now + JevLiveTuning.lowDataCooldown
        case .http(_, let retryAfter, _, _):
            cooldownUntil = now + min(max(JevLiveTuning.cooldown, retryAfter ?? .zero), JevLiveTuning.maxCooldown)
        default:
            cooldownUntil = now + JevLiveTuning.cooldown
        }
    }

    // MARK: - Display policy

    private func decide(_ answer: JevLiveAnswer, for request: RequestInfo) {
        let now = clock()
        guard let snapshot = latest, request.epoch == stepEpoch,
              let current = evaluate(snapshot, now: now), current.key == request.key else {
            return reject(.stale, answer, request)
        }
        if holdReason(snapshot) != nil { return reject(.held, answer, request) }

        // A re-ask while this same Jev tip is up: keep it unless the confidence fell below the keep line.
        if let shown = displayed, shown.source == .jev, shown.instruction == answer.pick {
            if answer.confidence + JevLiveTuning.epsilon < JevLiveTuning.keepConfidence {
                clear("reask_low_confidence", now: now)
                return reject(.lowConfidence, answer, request)
            }
            count("kept")
            record(.decision, seq: request.seq, fields: answerFields(answer).merging(["decision": "kept"]) { $1 })
            return
        }

        switch JevLiveQuestions.verdict(answer, options: request.options) {
        case .reject(let reason):
            // The pick changed on a re-ask: the old Jev tip goes.
            if displayed?.source == .jev { clear("pick_changed", now: now) }
            reject(reason, answer, request)
        case .pass(let pick):
            // Veto: the pick's condition must still hold on the state as it is now.
            guard current.options.contains(pick) else { return reject(.outOfSet, answer, request) }
            if snapshot.deviceTipIsCaptureHint, !JevLiveTuning.mayReplaceCaptureHint {
                return reject(.outranked, answer, request)
            }
            if let shown = displayed, shown.instruction != pick {
                guard shown.age(at: now) >= JevLiveTuning.minDwell,
                      answer.margin(for: pick) + JevLiveTuning.epsilon >= JevLiveTuning.replaceMargin else {
                    return reject(.unstable, answer, request)
                }
                clear("replaced", now: now)
            }
            present(pick, source: .jev, answer: answer, seq: request.seq, context: request.context, options: request.options, now: now)
        }
    }

    private func reject(_ reason: JevLiveReject, _ answer: JevLiveAnswer, _ request: RequestInfo) {
        count("reject_\(reason.rawValue)")
        record(.decision, seq: request.seq, fields: answerFields(answer).merging([
            "decision": reason.rawValue,
            "baseline": JevLiveQuestions.baselinePick(request.options)?.rawValue ?? "-"
        ]) { $1 })
    }

    private func present(
        _ pick: JevLiveInstruction,
        source: Source,
        answer: JevLiveAnswer?,
        seq: Int?,
        context: JevLiveContext,
        options: [JevLiveInstruction],
        now: ContinuousClock.Instant
    ) {
        resolveOutcome("next_tip", now: now)
        displayed = Suggestion(
            instruction: pick,
            step: context.step,
            source: source,
            confidence: answer?.confidence,
            margin: answer.map { $0.margin(for: pick) },
            shownAt: now,
            seq: seq
        )
        publish()
        pendingOutcome = PendingOutcome(seq: seq, instruction: pick, source: source, at: now)
        let decision = mode == .show ? "shown" : "shadow_shown"
        count("\(decision)_\(source.rawValue)")
        var fields: [String: String] = [
            "decision": decision,
            "pick": pick.rawValue,
            "source": source.rawValue,
            "options": options.map(\.rawValue).joined(separator: ","),
            "baseline": JevLiveQuestions.baselinePick(options)?.rawValue ?? "-",
            "state": context.encodedString
        ]
        if let answer { fields.merge(answerFields(answer)) { current, _ in current } }
        record(.decision, seq: seq, fields: fields)
    }

    private func clear(_ reason: String, now: ContinuousClock.Instant) {
        guard let shown = displayed else { return }
        leftScreenAt[shown.instruction] = now
        displayed = nil
        publish()
        record(.clear, seq: shown.seq, fields: [
            "reason": reason,
            "pick": shown.instruction.rawValue,
            "source": shown.source.rawValue,
            "dwell_ms": "\(JevTransport.milliseconds(now - shown.shownAt))"
        ])
    }

    private func publish() {
        let target = mode == .show ? displayed : nil
        if suggestion != target { suggestion = target }
    }

    private func reset(_ reason: String) {
        let now = clock()
        cancelInFlight(reason)
        clear(reason, now: now)
        candidate = nil
        lastAsked = nil
        if suggestion != nil { suggestion = nil }
    }

    // MARK: - Outcomes (weak labels for offline scoring)

    private func resolveOutcome(_ outcome: String, now: ContinuousClock.Instant) {
        guard let pending = pendingOutcome else { return }
        pendingOutcome = nil
        guard now - pending.at <= JevLiveTuning.outcomeWindow else { return }
        record(.outcome, seq: pending.seq, fields: [
            "pick": pending.instruction.rawValue,
            "source": pending.source.rawValue,
            "outcome": outcome,
            "after_ms": "\(JevTransport.milliseconds(now - pending.at))"
        ])
    }

    private func settleOutcome(now: ContinuousClock.Instant) {
        guard let pending = pendingOutcome, now - pending.at > JevLiveTuning.outcomeWindow else { return }
        pendingOutcome = nil
        record(.outcome, seq: pending.seq, fields: [
            "pick": pending.instruction.rawValue,
            "source": pending.source.rawValue,
            "outcome": "none_in_10s",
            "tip_now": tip?.rawValue ?? "-"
        ])
    }

    // MARK: - Log

    private func answerFields(_ answer: JevLiveAnswer) -> [String: String] {
        [
            "choice": answer.choice,
            "confidence": String(format: "%.2f", answer.confidence),
            "margin": answer.pick.map { String(format: "%.2f", answer.margin(for: $0)) } ?? "-",
            "probabilities": answer.probabilitiesLine
        ]
    }

    private var summaryFields: [String: String] {
        var fields = ["survey_sends": "\(surveySends)", "mode": mode.rawValue, "enabled": "\(isEnabled)"]
        for (key, value) in decisionCounts { fields[key] = "\(value)" }
        return fields
    }

    private func count(_ key: String) {
        decisionCounts[key, default: 0] += 1
    }

    /// Logs a skip once per freshness key, not every second.
    private func note(_ message: String, _ key: FreshnessKey) {
        let tag = "\(message)|\(key.hashValue)"
        guard tag != lastNote else { return }
        lastNote = tag
        record(.skip, fields: ["reason": message, "options": key.options.map(\.rawValue).joined(separator: ",")])
    }

    private func record(_ kind: JevLiveLogEntry.Kind, seq: Int? = nil, fields: [String: String]) {
        let now = clock()
        let entry = JevLiveLogEntry(
            kind: kind,
            seq: seq,
            epoch: stepEpoch,
            step: step?.rawValue,
            elapsedMs: begunAt.map { JevTransport.milliseconds(now - $0) } ?? 0,
            mode: mode.rawValue,
            fields: fields
        )
        #if DEBUG
        Self.log.debug("\(entry.line, privacy: .public)")
        recentLog.append(entry)
        if recentLog.count > 80 { recentLog.removeFirst(recentLog.count - 80) }
        #endif
        onRecord?(entry)
    }

    #if DEBUG
    /// Waits for the request in flight, if any. Tests and the DEBUG replay use it.
    func settle() async {
        await inFlight?.task.value
    }

    /// One line for a DEBUG overlay.
    var debugState: String {
        let tipLine = tip.map { "\($0.rawValue) \(tipSince.map { JevTransport.milliseconds(clock() - $0) / 1000 } ?? 0)s" } ?? "-"
        return "jev \(mode.rawValue) \(isEnabled ? "on" : "off") step=\(step?.rawValue ?? "-") tip=\(tipLine) "
            + "sends=\(stepSends)/\(surveySends) inflight=\(inFlight != nil) shown=\(displayed?.instruction.rawValue ?? "-")"
    }

    /// Clears the per-run off switches (401 / 403 / 422) for tests.
    static func resetRunState() {
        keyRejected = false
        rejectedQuestionVersion = nil
    }
    #endif
}

/// One request, reply, decision, clear, or outcome. Privacy-safe: the encoded state, the options, and the answers.
struct JevLiveLogEntry: Sendable {
    enum Kind: String, Sendable {
        case begin, step, request, reply, decision, skip, clear, outcome, progress, failure, cancel, end
    }

    let kind: Kind
    let seq: Int?
    let epoch: Int
    let step: String?
    /// Since `begin`.
    let elapsedMs: Int
    let mode: String
    let fields: [String: String]

    /// For FrameRecorder: `["jev": {kind, seq, epoch, t_ms, mode, …fields}, "step": …]`.
    var metadata: [String: any Sendable] {
        var jev: [String: any Sendable] = [
            "kind": kind.rawValue,
            "epoch": epoch,
            "t_ms": elapsedMs,
            "mode": mode
        ]
        if let seq { jev["seq"] = seq }
        for (key, value) in fields { jev[key] = value }
        return ["jev": jev, "step": step ?? "none"]
    }

    var line: String {
        let head = "jev \(kind.rawValue) t=\(elapsedMs)ms epoch=\(epoch) seq=\(seq.map(String.init) ?? "-") step=\(step ?? "-")"
        let body = fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        return body.isEmpty ? head : head + " " + body
    }
}
