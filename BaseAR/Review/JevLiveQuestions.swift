import Foundation

// The Live Survey's Jev lane, part 2: every tuning number, the instructions the app wrote (the only things Jev can
// pick), the per-step option rules, the one Choice question, and the acceptance check on a reply.
// Foundation only, so a Mac CLI can compile it with JevLiveContext.swift and JevTransport.swift for offline replay.

// MARK: - Tuning

/// Every number the live lane uses. All of them: tune on device, against the pinned `jev-1.13.0`.
enum JevLiveTuning {
    // Trigger and pacing
    /// The phone's own tip must stay on screen this long, with no gate pass and nothing locked, before Jev is asked.
    static let stuckAfter: Duration = .seconds(8)
    /// A change of the phone's line counts only once it holds this long (its hints settle in about 0.5 s).
    static let deviceTipHold: Duration = .seconds(1)
    /// No ask, and any Jev tip clears, within this long of a gate pass.
    static let passQuiet: Duration = .seconds(3)
    /// The freshness key must hold this long before a send.
    static let debounce: Duration = .milliseconds(750)
    static let minSendGap: Duration = .seconds(3)
    static let maxSendsPerStep = 6
    static let maxSendsPerSurvey = 20

    // Display policy
    /// Jev's `confidence` needed to show a tip that is not on screen yet.
    static let showConfidence = 0.60
    /// A tip already on screen stays while a re-ask picks it again at this confidence or more.
    static let keepConfidence = 0.45
    /// Our own margin: p(pick) − p(none).
    static let minMarginOverNone = 0.15
    /// A different Jev tip replaces the one on screen only past `minDwell` and with this margin over none.
    static let replaceMargin = 0.25
    /// Probabilities arrive as two-decimal floats: 0.60 − 0.45 must count as 0.15.
    static let epsilon = 1e-9
    static let minDwell: Duration = .seconds(3)
    static let maxDwell: Duration = .seconds(8)
    /// A tip that left the screen is not shown or offered again for this long.
    static let reshowAfter: Duration = .seconds(15)
    /// Product order puts capture feedback and the detector hint above any Jev tip. Team decision (§8 Q2) to change.
    static let mayReplaceCaptureHint = false
    /// What happened within this long of a tip is logged as its outcome.
    static let outcomeWindow: Duration = .seconds(10)

    // Failures
    /// 429 / 529 / 5xx / timeout / offline: the lane rests this long, or for Retry-After if longer, capped.
    static let cooldown: Duration = .seconds(30)
    static let maxCooldown: Duration = .seconds(60)
    /// Low Data Mode: the lane rests, then checks again.
    static let lowDataCooldown: Duration = .seconds(60)

    // Cache and size
    /// Replies kept per survey, keyed by the exact request bytes. Jev is close to deterministic on the same state.
    static let cacheEntries = 32
    /// DEBUG warns above this. Measured on this Mac (26 Sep 2026): state 169–211 B; body 0.8–0.9 KB with two options,
    /// 1.26 KB with five. Tokens are not published: log `usage.input_tokens` from the first real call.
    static let bodyBudgetBytes = 1800

    // Rings (on device)
    static let ringPackets = 20
    /// Packets older than this are dropped from `seen` and `main_fail` (20 packets take about 5 s at 4 Hz).
    static let ringMaxAge: Duration = .seconds(6)
    static let seenOftenAt = 6
    static let seenSteadyAt = 15
    static let dominantPackets = 10
    /// The capture gate's `captureMinArea`, `captureCloseArea`, `captureMaxArea`.
    static let sizeMinArea = 0.06
    static let sizeCloseArea = 0.15
    static let sizeMaxArea = 0.8
    /// Size, wall, and light come from packets at most this old.
    static let framingMemory: Duration = .seconds(2)
    static let readMemory: Duration = .seconds(10)
    /// The gate's `captureEmptyReadsForHint`.
    static let emptyReadsForEmpty = 2
    static let textFirstRecent: Duration = .seconds(5)
    /// Pixels of motion blur during one exposure that count as high shake. 3–6 px broke OCR in the Mac test.
    static let shakeHighPixels = 3.0
}

// MARK: - Instructions the app wrote

/// The only answers Jev can give the live lane. The app writes the words; Jev text is never shown.
/// Copy and SF Symbols match the view's `CoachTip` where the tip already exists.
enum JevLiveInstruction: String, Codable, Hashable, Sendable, CaseIterable {
    case holdStill = "hold_still"
    case addLight = "add_light"
    case shadeLabel = "shade_label"
    case faceLabel = "face_label"
    case aimAtWall = "aim_at_wall"
    case stepBack = "step_back"
    case closerToLabel = "closer_to_label"
    /// NEW copy (needs team approval).
    case notThatBox = "not_that_box"
    case openPanelDoor = "open_panel_door"
    /// NEW copy (needs team approval).
    case tryOtherWall = "try_other_wall"
    /// NEW copy (needs team approval). Panel step only.
    case panelIndoors = "panel_indoors"

    /// The on-screen line.
    func copy(for step: JevLiveContext.Step) -> String {
        switch self {
        case .holdStill: "Hold still"
        case .addLight: "Too dark \u{2014} add light"
        case .shadeLabel: "Too bright \u{2014} shade the label"
        case .faceLabel: "Turn so the label faces you"
        case .aimAtWall: "Aim at the wall"
        case .stepBack: "Take a few steps back"
        case .closerToLabel: "Get closer to the label"
        case .notThatBox:
            step == .findMeter
                ? "That\u{2019}s not the meter. Look for the glass dial"
                : "That\u{2019}s not the panel. Look for a gray metal door"
        case .openPanelDoor: "Open the panel door, not the cover"
        case .tryOtherWall: "Try another outside wall"
        case .panelIndoors: "Check the garage or utility room"
        }
    }

    /// SF Symbol, in the style of `CoachTip.symbol`.
    var symbol: String {
        switch self {
        case .holdStill: "hand.raised.fill"
        case .addLight: "flashlight.on.fill"
        case .shadeLabel: "sun.max.fill"
        case .faceLabel: "rotate.3d"
        case .aimAtWall: "viewfinder"
        case .stepBack: "figure.walk.motion"
        case .closerToLabel: "plus.magnifyingglass"
        case .notThatBox: "xmark.circle.fill"
        case .openPanelDoor: "door.left.hand.open"
        case .tryOtherWall: "arrow.triangle.turn.up.right.circle.fill"
        case .panelIndoors: "door.garage.closed"
        }
    }

    /// Copy nobody has approved yet (spec §8 Q4).
    var isNewCopy: Bool {
        self == .notThatBox || self == .tryOtherWall || self == .panelIndoors
    }

    /// Phone lines that already say this. An instruction is never offered while one of them is on screen.
    var sameAsDeviceTips: Set<JevDeviceTip> {
        switch self {
        case .holdStill: [.holdStill]
        case .addLight: [.addLight]
        case .shadeLabel: [.shadeLabel]
        case .faceLabel: [.faceLabel]
        case .aimAtWall: [.aimAtWall]
        case .stepBack: [.stepBack]
        case .closerToLabel: [.closerToLabel, .getCloser]
        case .openPanelDoor: [.openPanelDoor]
        case .notThatBox, .tryOtherWall, .panelIndoors: []
        }
    }

    /// Baseline order: when the code alone must pick one of several options, the first one here wins.
    static let priority: [JevLiveInstruction] = [
        .notThatBox, .aimAtWall, .stepBack, .addLight, .shadeLabel, .holdStill, .closerToLabel, .faceLabel,
        .openPanelDoor, .panelIndoors, .tryOtherWall
    ]
}

// MARK: - Options and the question

/// Options are built in code: an instruction is offered only when its one-field condition holds in `state`, it is
/// not the phone's own line, and it has not been on screen in the last 15 s. 0 options: nothing to say.
/// 1 option: the phone shows it without asking (the fixed-rule baseline). 2 or more: one Choice over them plus none.
enum JevLiveQuestions {
    /// Bump when any question text, option rule, or state field changes. A 422 turns off only this version.
    static let version = 1
    static let questionID = "next_try"
    static let noneOption = "none"

    static func options(
        for context: JevLiveContext,
        textFirstReadRecently: Bool,
        excluding recent: Set<JevLiveInstruction> = []
    ) -> [JevLiveInstruction] {
        JevLiveInstruction.priority.filter { instruction in
            !recent.contains(instruction)
                && !instruction.sameAsDeviceTips.contains(context.tipTried)
                && holds(instruction, in: context, textFirstReadRecently: textFirstReadRecently)
        }
    }

    /// The one-field condition for each instruction. These double as the vetoes: a reply is accepted only while its
    /// pick still holds on the current state.
    static func holds(_ instruction: JevLiveInstruction, in c: JevLiveContext, textFirstReadRecently: Bool) -> Bool {
        let targetOrMeterWord = c.cues.contains(.meterWord) || c.cues.contains(.panelWord)
        switch instruction {
        case .holdStill:
            return c.shake == .high || c.mainFail == .blurry
        case .addLight:
            return c.light == .dark || c.mainFail == .dark
        case .shadeLabel:
            return c.light == .bright || c.mainFail == .bright
        case .faceLabel:
            return c.mainFail == .steep
        case .aimAtWall:
            return c.seen.isSeen && c.onWall == .no
        case .stepBack:
            return c.size == .cutOff
        case .closerToLabel:
            return c.size.isSmall || (c.step == .findMeter && c.reads == .empty && c.size == .ok)
        case .notThatBox:
            return c.reads == .appliance || (c.cues.contains(.applianceWord) && !targetOrMeterWord)
        case .openPanelDoor:
            return c.step == .findPanel && c.seen.isSeen && c.size == .ok
                && (c.reads == .noReads || c.reads == .empty) && c.cues.isEmpty
        case .tryOtherWall, .panelIndoors:
            // Text-first OCR can still lock with no box, so never send the user away while a label is being found.
            if instruction == .panelIndoors, c.step != .findPanel { return false }
            return !c.seen.isSeen && c.stuck.atLeast15s && !targetOrMeterWord && !textFirstReadRecently
        }
    }

    /// The fixed-rule baseline: the first option in `JevLiveInstruction.priority`.
    static func baselinePick(_ options: [JevLiveInstruction]) -> JevLiveInstruction? {
        options.first
    }

    static func question(step: JevLiveContext.Step, options: [JevLiveInstruction]) -> JevLiveQuestion {
        var criteria: [String: JevLiveCriterion] = [:]
        for option in options {
            criteria[option.rawValue] = criterion(option, step: step)
        }
        criteria[noneOption] = .plain("Nothing in `state` points to one of the other instructions more than the rest")
        return JevLiveQuestion(instructions: instructions(step), criteria: criteria)
    }

    static func instructions(_ step: JevLiveContext.Step) -> String {
        switch step {
        case .findMeter:
            "A person outside a house is aiming a phone to find the electric meter. The app has shown `tip_tried` for `stuck` and the photo still has not passed. Pick the one different instruction most likely to help next."
        case .findPanel:
            "A person at a house is aiming a phone to find the breaker panel. The app has shown `tip_tried` for `stuck` and the photo of the panel still has not passed. Pick the one different instruction most likely to help next."
        }
    }

    /// Fixed text per option, naming one field each.
    static func criterion(_ option: JevLiveInstruction, step: JevLiveContext.Step) -> JevLiveCriterion {
        let target = step == .findMeter ? "meter" : "breaker panel"
        switch option {
        case .holdStill:
            return .rubric(what: "`main_fail` is blurry or `shake` is high: the photo is blurred by motion",
                           notFor: "`main_fail` is too_small, dark or bright")
        case .addLight:
            return .rubric(what: "`light` is dark or `main_fail` is dark", notFor: "`light` is ok or bright")
        case .shadeLabel:
            return .rubric(what: "`light` is bright or `main_fail` is bright: glare on the label",
                           notFor: "`light` is ok or dark")
        case .faceLabel:
            return .rubric(what: "`main_fail` is steep: the label is seen at a sharp angle",
                           notFor: "`main_fail` is too_small or cut_off")
        case .aimAtWall:
            return .rubric(what: "`on_wall` is no: the box is seen but not on a wall", notFor: "`on_wall` is yes")
        case .stepBack:
            return .rubric(what: "`size` is cut_off: the box fills the screen", notFor: "`size` is too_small or small")
        case .closerToLabel:
            return .rubric(
                what: step == .findMeter
                    ? "`size` is too_small or small, or `reads` is empty: the print is too small to read"
                    : "`size` is too_small or small: the print is too small to read",
                notFor: "`size` is cut_off"
            )
        case .notThatBox:
            return .rubric(what: "`reads` is appliance or `cues` has appliance_word: an AC unit or heat pump, not the \(target)",
                           notFor: step == .findMeter ? "`cues` has meter_word" : "`cues` has panel_word")
        case .openPanelDoor:
            return .rubric(what: "`seen` is often or steady and `cues` is empty: a closed panel door hides the breakers",
                           notFor: "`cues` has panel_word")
        case .tryOtherWall:
            return .rubric(what: "`seen` is never or rarely: the \(target) is not on this wall",
                           notFor: "`seen` is often or steady")
        case .panelIndoors:
            return .rubric(what: "`seen` is never or rarely: many panels are inside, in the garage or a utility room",
                           notFor: "`seen` is often or steady")
        }
    }

    /// The exact request bytes: `{model, questions, state}`, snake_case, sorted keys.
    static func requestBody(context: JevLiveContext, options: [JevLiveInstruction], model: String = JevTransport.pinnedModel) throws -> Data {
        let request = JevLiveRequest(
            model: model,
            questions: [questionID: question(step: context.step, options: options)],
            state: context
        )
        return try JevTransport.encodeBody(request, snakeCaseKeys: true)
    }

    // MARK: Acceptance

    /// The checks a reply must pass to show a tip that is not on screen yet: a pick among the options sent (not
    /// none), `confidence` ≥ 0.6, and p(pick) − p(none) ≥ 0.15. The coach adds freshness, holds, vetoes, and dwell.
    static func verdict(_ answer: JevLiveAnswer, options: [JevLiveInstruction]) -> JevLiveVerdict {
        guard answer.choice != noneOption else { return .reject(.pickedNone) }
        guard let pick = JevLiveInstruction(rawValue: answer.choice), options.contains(pick) else { return .reject(.outOfSet) }
        guard answer.confidence + JevLiveTuning.epsilon >= JevLiveTuning.showConfidence else { return .reject(.lowConfidence) }
        guard answer.margin(for: pick) + JevLiveTuning.epsilon >= JevLiveTuning.minMarginOverNone else { return .reject(.lowMargin) }
        return .pass(pick)
    }
}

struct JevLiveRequest: Encodable, Sendable {
    let model: String
    let questions: [String: JevLiveQuestion]
    let state: JevLiveContext
}

struct JevLiveQuestion: Encodable, Sendable {
    var type = "choice"
    let instructions: String
    let criteria: [String: JevLiveCriterion]
}

enum JevLiveCriterion: Encodable, Sendable, Equatable {
    case rubric(what: String, notFor: String)
    case plain(String)

    private enum Keys: String, CodingKey {
        case what
        case notFor = "not_for"
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .rubric(let what, let notFor):
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(what, forKey: .what)
            try container.encode(notFor, forKey: .notFor)
        case .plain(let text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        }
    }
}

// MARK: - Reply

/// The `next_try` Choice answer.
struct JevLiveAnswer: Sendable, Equatable {
    let choice: String
    let confidence: Double
    let probabilities: [String: Double]

    init(choice: String, confidence: Double, probabilities: [String: Double]) {
        self.choice = choice
        self.confidence = confidence
        self.probabilities = probabilities
    }

    init?(_ answer: JevAnswer?) {
        guard let answer, let choice = answer.choice else { return nil }
        self.init(choice: choice, confidence: answer.confidence ?? 0, probabilities: answer.probabilities ?? [:])
    }

    var pick: JevLiveInstruction? { JevLiveInstruction(rawValue: choice) }

    func probability(_ option: String) -> Double { probabilities[option] ?? 0 }

    /// p(pick) − p(none): our own margin, since `confidence` is opaque.
    func margin(for pick: JevLiveInstruction) -> Double {
        probability(pick.rawValue) - probability(JevLiveQuestions.noneOption)
    }

    /// Probabilities as "option=0.62", highest first, for the log.
    var probabilitiesLine: String {
        probabilities.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key)=\(String(format: "%.2f", $0.value))" }
            .joined(separator: " ")
    }
}

enum JevLiveVerdict: Equatable, Sendable {
    case pass(JevLiveInstruction)
    case reject(JevLiveReject)
}

/// Why a reply, a cache hit, or a rule pick was not shown. Logged with every decision.
enum JevLiveReject: String, Sendable {
    /// Jev picked none.
    case pickedNone = "none"
    /// The pick was not among the options sent, or no longer holds on the current state (a veto).
    case outOfSet = "out_of_set"
    case lowConfidence = "low_confidence"
    case lowMargin = "low_margin"
    /// The step, its epoch, or the freshness key changed since the send.
    case stale
    /// A skip rule holds now.
    case held
    /// The phone's line is a capture or detector hint, which outranks a Jev tip.
    case outranked
    /// A different tip is on screen and has not had its minimum dwell, or the new pick lacks the replace margin.
    case unstable
}
