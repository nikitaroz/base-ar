import Foundation

// The Live Survey's Jev lane, part 1: what leaves the phone (`JevLiveContext`), what the phone tells the coach
// (`JevLiveSnapshot`), and the on-device rings that turn per-packet gate results into buckets (`JevScanRings`).
// Foundation only, so a Mac CLI can compile this file and replay FrameLog contexts byte for byte.

// MARK: - State sent to Jev

/// `state` for the live Jev lane. v1: the meter and panel find steps only; gas and look-around are off.
///
/// PRIVACY. Enums only: no String, no number, no dictionary, no clock time, no place, no label text, no digits.
/// Encode with `JevLiveContext.encoded()` (snake_case keys, sorted), so the same state always gives the same bytes.
/// Nil fields drop out. No `seq`, survey id, or version goes in `state`; the version is in the question set and
/// the cache key. Any new field needs a privacy review and an update to `allowedKeys`.
/// The server still sees the request time and the phone's IP address, and one survey's requests arrive in a row.
struct JevLiveContext: Encodable, Hashable, Sendable {
    enum Step: String, Encodable, Hashable, Sendable, CaseIterable {
        case findMeter = "find_meter"
        case findPanel = "find_panel"
    }

    /// How long the phone's own tip (`tip_tried`) has been on screen. Nothing is sent before 8 s.
    enum Stuck: String, Encodable, Hashable, Sendable, CaseIterable {
        case s8to15 = "8_15s"
        case s15to30 = "15_30s"
        case s30plus = "30s_plus"

        /// Nil under `JevLiveTuning.stuckAfter` (8 s).
        init?(onScreenFor duration: Duration) {
            if duration < JevLiveTuning.stuckAfter { return nil }
            if duration < .seconds(15) { self = .s8to15 } else if duration < .seconds(30) { self = .s15to30 } else { self = .s30plus }
        }

        var atLeast15s: Bool { self != .s8to15 }
    }

    /// Packets with a target-kind box at the capture floor, out of the last 20 (about 5 s at 4 Hz).
    enum Seen: String, Encodable, Hashable, Sendable, CaseIterable {
        case never, rarely, often, steady

        init(boxes: Int) {
            switch boxes {
            case ..<1: self = .never
            case ..<JevLiveTuning.seenOftenAt: self = .rarely
            case ..<JevLiveTuning.seenSteadyAt: self = .often
            default: self = .steady
            }
        }

        var isSeen: Bool { self == .often || self == .steady }
    }

    /// The candidate box as a share of the screen, on the capture gate's own edges:
    /// `captureMinArea` 0.06, `captureCloseArea` 0.15, `captureMaxArea` 0.8.
    enum Size: String, Encodable, Hashable, Sendable, CaseIterable {
        case noTarget = "none"
        case tooSmall = "too_small"
        case small
        case ok
        case cutOff = "cut_off"

        init(area: Double?) {
            guard let area else { self = .noTarget; return }
            if area < JevLiveTuning.sizeMinArea { self = .tooSmall }
            else if area < JevLiveTuning.sizeCloseArea { self = .small }
            else if area <= JevLiveTuning.sizeMaxArea { self = .ok }
            else { self = .cutOff }
        }

        var isSmall: Bool { self == .tooSmall || self == .small }
    }

    enum OnWall: String, Encodable, Hashable, Sendable, CaseIterable {
        case yes, no, unknown
    }

    /// The gate failure that holds 10 or more of the last 20 packets; `mixed` when failures hold 10 or more but no
    /// single one does; `none` otherwise. "No candidate" and tracking blocks are not failures (`seen` covers them).
    enum Fail: String, Encodable, Hashable, Sendable, CaseIterable {
        case tooSmall = "too_small"
        case cutOff = "cut_off"
        case offCenter = "off_center"
        case steep
        case dark
        case bright
        case blurry
        case notOnWall = "not_on_wall"
        case rejected
        case mixed
        case noDominant = "none"
    }

    /// The gate's own luma verdict (`CaptureQuality.problem`) on the latest frame.
    enum Light: String, Encodable, Hashable, Sendable, CaseIterable {
        case dark, ok, bright
    }

    /// Motion blur risk. Only once the blur-risk gate exists (|ω| × exposureDuration × fx, in pixels); nil until then.
    enum Shake: String, Encodable, Hashable, Sendable, CaseIterable {
        case low, high

        init(blurPixels: Double) {
            self = blurPixels >= JevLiveTuning.shakeHighPixels ? .high : .low
        }

        /// Pixels of motion blur during one exposure: angular speed (rad/s) × exposure (s) × focal length (px).
        static func blurPixels(angularSpeed: Double, exposureSeconds: Double, focalPixels: Double) -> Double {
            abs(angularSpeed) * max(0, exposureSeconds) * max(0, focalPixels)
        }
    }

    /// What the label reads have said lately. There is no "agree": two agreeing reads capture.
    enum Reads: String, Encodable, Hashable, Sendable, CaseIterable {
        case noReads = "none"
        case empty
        case disagree
        case appliance
    }

    /// Whitelisted word flags from the label parser. Never the words themselves.
    enum Cue: String, Encodable, Hashable, Sendable, CaseIterable, Comparable {
        case applianceWord = "appliance_word"
        case meterWord = "meter_word"
        case panelWord = "panel_word"

        static func < (lhs: Cue, rhs: Cue) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var step: Step
    var stuck: Stuck
    var tipTried: JevDeviceTip
    var seen: Seen
    var size: Size
    var onWall: OnWall
    var mainFail: Fail
    var light: Light
    var shake: Shake?
    var reads: Reads
    /// Sorted, no repeats.
    var cues: [Cue]

    init(
        step: Step,
        stuck: Stuck,
        tipTried: JevDeviceTip,
        seen: Seen,
        size: Size,
        onWall: OnWall,
        mainFail: Fail,
        light: Light,
        shake: Shake? = nil,
        reads: Reads,
        cues: [Cue]
    ) {
        self.step = step
        self.stuck = stuck
        self.tipTried = tipTried
        self.seen = seen
        self.size = size
        self.onWall = onWall
        self.mainFail = mainFail
        self.light = light
        self.shake = shake
        self.reads = reads
        self.cues = Array(Set(cues)).sorted()
    }

    init(step: Step, stuck: Stuck, tipTried: JevDeviceTip, scan: JevScanSignals) {
        self.init(
            step: step,
            stuck: stuck,
            tipTried: tipTried,
            seen: scan.seen,
            size: scan.size,
            onWall: scan.onWall,
            mainFail: scan.mainFail,
            light: scan.light,
            shake: scan.shake,
            reads: scan.reads,
            cues: scan.cues
        )
    }

    /// Every key the encoded state may carry. The privacy test checks the encoded JSON against it at every level.
    static let allowedKeys: Set<String> = [
        "step", "stuck", "tip_tried", "seen", "size", "on_wall", "main_fail", "light", "shake", "reads", "cues"
    ]

    /// Snake_case keys, sorted: the exact `state` bytes, also used for the cache key and the FrameLog record.
    func encoded() throws -> Data {
        try JevTransport.encodeBody(self, snakeCaseKeys: true)
    }

    var encodedString: String {
        (try? encoded()).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Cues that name the target of this step.
    var hasTargetWord: Bool {
        switch step {
        case .findMeter: cues.contains(.meterWord)
        case .findPanel: cues.contains(.panelWord)
        }
    }
}

// MARK: - The phone's own line

/// The line the phone shows on the bottom bar, as an id. Maps from the exact `CoachTip` copy
/// (`JevDeviceTip(copy: feedback.text)`), so the Jev layer needs no access to the view's private `CoachTip`.
enum JevDeviceTip: String, Encodable, Hashable, Sendable, CaseIterable {
    case pointAtMeter = "point_at_meter"
    case pointAtPanel = "point_at_panel"
    case closerToLabel = "closer_to_label"
    case getCloser = "get_closer"
    case stepBack = "step_back"
    case lookUp = "look_up"
    case pointDown = "point_down"
    case scootLeft = "scoot_left"
    case scootRight = "scoot_right"
    case faceLabel = "face_label"
    case addLight = "add_light"
    case shadeLabel = "shade_label"
    case holdStill = "hold_still"
    case aimAtWall = "aim_at_wall"
    case openPanelDoor = "open_panel_door"
    /// "Reading the number…" / "Reading the main breaker…": a skip rule, never sent.
    case reading
    case other

    /// `CoachTip` raw values as of integrate-3-step 0071159. Anything else is `.other`.
    static let copyTable: [String: JevDeviceTip] = [
        "Point at the meter": .pointAtMeter,
        "Point at the panel": .pointAtPanel,
        "Get closer to the label": .closerToLabel,
        "Get closer": .getCloser,
        "Take a few steps back": .stepBack,
        "Step back so the whole panel fits": .stepBack,
        "Look up at it": .lookUp,
        "Point your phone down": .pointDown,
        "Scoot left": .scootLeft,
        "Scoot right": .scootRight,
        "Turn so the label faces you": .faceLabel,
        "Too dark \u{2014} add light": .addLight,
        "Too bright \u{2014} shade the label": .shadeLabel,
        "Hold still": .holdStill,
        "Aim at the wall": .aimAtWall,
        "Open the panel door, not the cover": .openPanelDoor,
        "Reading the number\u{2026}": .reading,
        "Reading the main breaker\u{2026}": .reading
    ]

    init(copy: String) {
        self = Self.copyTable[copy] ?? .other
    }
}

// MARK: - What the view hands the coach

/// Reasons not to ask Jev, and not to keep a Jev tip on screen. The view sets them from state it already has.
struct JevLiveHolds: OptionSet, Sendable, Hashable {
    let rawValue: Int

    /// `statusMessage` or `cameraProblem` is set.
    static let error = JevLiveHolds(rawValue: 1 << 0)
    /// `pausedForCapture`.
    static let paused = JevLiveHolds(rawValue: 1 << 1)
    /// A tracking message is up, or tracking is not normal.
    static let tracking = JevLiveHolds(rawValue: 1 << 2)
    /// `coachingIsActive`.
    static let coaching = JevLiveHolds(rawValue: 1 << 3)
    /// `flashTip` is showing.
    static let flash = JevLiveHolds(rawValue: 1 << 4)
    /// `scanFeedback.detector != .ok`: the step ends in 10 s and nothing can be coached.
    static let detectorDown = JevLiveHolds(rawValue: 1 << 5)
    /// `labelBeingRead`.
    static let reading = JevLiveHolds(rawValue: 1 << 6)
    /// The step's target is already locked.
    static let locked = JevLiveHolds(rawValue: 1 << 7)
    /// Not visible, or leaving (`isLeaving`).
    static let leaving = JevLiveHolds(rawValue: 1 << 8)

    /// Holds that also take a Jev tip off the screen at once.
    static let clearing: JevLiveHolds = [.error, .paused, .tracking, .coaching, .leaving, .locked]

    var names: [String] {
        let all: [(JevLiveHolds, String)] = [
            (.error, "error"), (.paused, "paused"), (.tracking, "tracking"), (.coaching, "coaching"), (.flash, "flash"),
            (.detectorDown, "detector_down"), (.reading, "reading"), (.locked, "locked"), (.leaving, "leaving")
        ]
        return all.filter { contains($0.0) }.map(\.1)
    }
}

/// One look at the Live Survey, built by the view about once a second and whenever the bottom line changes.
struct JevLiveSnapshot: Sendable, Equatable {
    /// Nil on every step but findMeter and findPanel: the coach clears and idles.
    var step: JevLiveContext.Step?
    /// The phone's own line: `feedback(_:)` without the Jev slot. Never the Jev tip itself.
    var deviceTip: JevDeviceTip?
    /// That line came from the capture gate or detector (`scanFeedback.hint`), not from the step's motion line.
    /// By default a Jev tip never replaces it (`JevLiveTuning.mayReplaceCaptureHint`).
    var deviceTipIsCaptureHint: Bool
    var scan: JevScanSignals
    var holds: JevLiveHolds

    init(
        step: JevLiveContext.Step?,
        deviceTip: JevDeviceTip?,
        deviceTipIsCaptureHint: Bool,
        scan: JevScanSignals = JevScanSignals(),
        holds: JevLiveHolds = []
    ) {
        self.step = step
        self.deviceTip = deviceTip
        self.deviceTipIsCaptureHint = deviceTipIsCaptureHint
        self.scan = scan
        self.holds = holds
    }
}

// MARK: - On-device rings

/// The capture gate's verdict on one detector packet (one exit of `evaluateCapture`).
enum JevGateOutcome: String, Sendable, CaseIterable {
    case pass
    /// No target box, no meter box standing in, no text candidate.
    case noCandidate
    /// Tracking not normal or the packet's status not ok.
    case blocked
    case tooSmall, cutOff, offCenter, steep, dark, bright, blurry, notOnWall
    /// Height, separation, or the "Not the …" ban.
    case rejected

    var fail: JevLiveContext.Fail? {
        switch self {
        case .pass, .noCandidate, .blocked: nil
        case .tooSmall: .tooSmall
        case .cutOff: .cutOff
        case .offCenter: .offCenter
        case .steep: .steep
        case .dark: .dark
        case .bright: .bright
        case .blurry: .blurry
        case .notOnWall: .notOnWall
        case .rejected: .rejected
        }
    }

    /// The decision string `logCapture` already writes ("pass streak=…", "no-candidate", "not-on-wall", "banned",
    /// "rejected", "blocked", "fail:closerToLabel", …), so the integrator can feed the ring from that one call.
    init?(gateDecision decision: String) {
        if decision.hasPrefix("pass") { self = .pass; return }
        switch decision {
        case "no-candidate": self = .noCandidate; return
        case "blocked": self = .blocked; return
        case "not-on-wall": self = .notOnWall; return
        case "banned", "rejected": self = .rejected; return
        default: break
        }
        if decision.hasPrefix("rejected") { self = .rejected; return }
        guard decision.hasPrefix("fail:") else { return nil }
        switch decision.dropFirst("fail:".count) {
        case "closerToLabel": self = .tooSmall
        case "stepBack": self = .cutOff
        case "lookUp", "pointDown", "scootLeft", "scootRight": self = .offCenter
        case "faceLabel": self = .steep
        case "tooDark": self = .dark
        case "tooBright": self = .bright
        case "holdStill": self = .blurry
        case "aimAtWall": self = .notOnWall
        default: return nil
        }
    }
}

/// One packet, as the ring keeps it.
struct JevPacketSignal: Sendable, Equatable {
    /// A box of the step's kind at `captureMinConfidence` (0.25) or more was in the packet.
    var targetSeen: Bool
    var outcome: JevGateOutcome
    /// The candidate's area as a share of the screen. Nil with no candidate.
    var area: Double?
    /// The candidate landed on a wall (plane or depth). Nil with no candidate.
    var onWall: Bool?
    /// The gate's luma verdict on the candidate (or the center of the screen with no candidate).
    var light: JevLiveContext.Light?
    /// Pixels of motion blur, once the blur-risk gate computes it.
    var blurPixels: Double?

    init(
        targetSeen: Bool,
        outcome: JevGateOutcome,
        area: Double? = nil,
        onWall: Bool? = nil,
        light: JevLiveContext.Light? = nil,
        blurPixels: Double? = nil
    ) {
        self.targetSeen = targetSeen
        self.outcome = outcome
        self.area = area
        self.onWall = onWall
        self.light = light
        self.blurPixels = blurPixels
    }
}

/// One label read. The ring never holds the text or the digits: the caller says whether the value agreed.
enum JevReadOutcome: Sendable, Equatable {
    /// A good frame that read no value.
    case empty
    /// The label is an AC condenser or heat pump (`isApplianceLabel`).
    case appliance
    /// A value read; `agreesWithEarlier` is false when it differs from a value already in the read window.
    case value(agreesWithEarlier: Bool)
}

/// The bucketed scan signals the coach reads. Built by `JevScanRings.signals()`.
struct JevScanSignals: Sendable, Equatable {
    /// False until the controller's rings have recent packets. The coach does nothing without it: default buckets
    /// ("never seen") would otherwise send the user to another wall while the meter is in view.
    var available = false
    var seen: JevLiveContext.Seen = .never
    var size: JevLiveContext.Size = .noTarget
    var onWall: JevLiveContext.OnWall = .unknown
    var mainFail: JevLiveContext.Fail = .noDominant
    var light: JevLiveContext.Light = .ok
    var shake: JevLiveContext.Shake?
    var reads: JevLiveContext.Reads = .noReads
    var cues: [JevLiveContext.Cue] = []
    /// A gate pass in the last `JevLiveTuning.passQuiet` (3 s).
    var passedRecently = false
    /// A text-first read found text in the last `JevLiveTuning.textFirstRecent` (5 s).
    var textFirstReadRecently = false
}

/// Per-packet memory for the Jev lane, owned by `PlacementSceneController` (not view state: nothing here is
/// published at packet rate). Feed it from `evaluateCapture` / `absorbRead`, reset it with `resetCapture`, and hand
/// `signals()` to the view when it builds a snapshot.
struct JevScanRings: Sendable {
    private struct Packet: Sendable {
        let signal: JevPacketSignal
        let at: ContinuousClock.Instant
    }

    private struct Read: Sendable {
        let outcome: JevReadOutcome
        let cues: Set<JevLiveContext.Cue>
        let textFirst: Bool
        let at: ContinuousClock.Instant
    }

    private var packets: [Packet] = []
    private var reads: [Read] = []
    private var lastPassAt: ContinuousClock.Instant?
    private var lastTextFirstHitAt: ContinuousClock.Instant?
    /// Empty reads since the last value: the gate's own `emptyReads` rule (2 before it hints).
    private var emptyReadsSinceValue = 0

    init() {}

    mutating func record(_ signal: JevPacketSignal, now: ContinuousClock.Instant = .now) {
        packets.append(Packet(signal: signal, at: now))
        if packets.count > JevLiveTuning.ringPackets { packets.removeFirst(packets.count - JevLiveTuning.ringPackets) }
        if signal.outcome == .pass { lastPassAt = now }
    }

    mutating func record(
        read outcome: JevReadOutcome,
        cues: Set<JevLiveContext.Cue> = [],
        textFirst: Bool = false,
        now: ContinuousClock.Instant = .now
    ) {
        reads.append(Read(outcome: outcome, cues: cues, textFirst: textFirst, at: now))
        reads.removeAll { now - $0.at > JevLiveTuning.readMemory }
        switch outcome {
        case .empty: emptyReadsSinceValue += 1
        case .value, .appliance: emptyReadsSinceValue = 0
        }
        if textFirst, outcome != .empty || !cues.isEmpty { lastTextFirstHitAt = now }
    }

    /// The step's target changed, or the capture state reset.
    mutating func reset() {
        self = JevScanRings()
    }

    func signals(now: ContinuousClock.Instant = .now) -> JevScanSignals {
        var signals = JevScanSignals()
        // Packets stop while tracking is blocked or coaching is up; old ones say nothing about now.
        let ring = packets.filter { now - $0.at <= JevLiveTuning.ringMaxAge }
        guard !ring.isEmpty else { return signals }
        signals.available = true
        signals.seen = JevLiveContext.Seen(boxes: ring.filter(\.signal.targetSeen).count)
        // Framing from the latest packet that had a candidate, if it is recent.
        let recent = ring.filter { now - $0.at <= JevLiveTuning.framingMemory }
        if let framed = recent.last(where: { $0.signal.area != nil }) {
            signals.size = JevLiveContext.Size(area: framed.signal.area)
            signals.onWall = framed.signal.onWall.map { $0 ? .yes : .no } ?? .unknown
        }
        signals.light = recent.last(where: { $0.signal.light != nil })?.signal.light ?? .ok
        if let blur = recent.last(where: { $0.signal.blurPixels != nil })?.signal.blurPixels {
            signals.shake = JevLiveContext.Shake(blurPixels: blur)
        }
        signals.mainFail = Self.dominantFail(ring.map(\.signal.outcome))
        let liveReads = reads.filter { now - $0.at <= JevLiveTuning.readMemory }
        if liveReads.contains(where: { $0.outcome == .appliance }) {
            signals.reads = .appliance
        } else if liveReads.contains(where: { $0.outcome == .value(agreesWithEarlier: false) }) {
            signals.reads = .disagree
        } else if emptyReadsSinceValue >= JevLiveTuning.emptyReadsForEmpty {
            signals.reads = .empty
        }
        signals.cues = Array(liveReads.reduce(into: Set<JevLiveContext.Cue>()) { $0.formUnion($1.cues) }).sorted()
        signals.passedRecently = lastPassAt.map { now - $0 < JevLiveTuning.passQuiet } ?? false
        signals.textFirstReadRecently = lastTextFirstHitAt.map { now - $0 < JevLiveTuning.textFirstRecent } ?? false
        return signals
    }

    static func dominantFail(_ outcomes: [JevGateOutcome]) -> JevLiveContext.Fail {
        let fails = outcomes.compactMap(\.fail)
        guard fails.count >= JevLiveTuning.dominantPackets else { return .noDominant }
        let counts = Dictionary(fails.map { ($0, 1) }, uniquingKeysWith: +)
        // Ties (10 and 10) resolve by name, so the same ring always gives the same state.
        let top = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }
        if let top, top.value >= JevLiveTuning.dominantPackets {
            return top.key
        }
        return .mixed
    }
}
