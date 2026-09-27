#if DEBUG
import Foundation

/// DEBUG test hooks for the live Jev lane. No curl: run them from Review → Jev advisory → "Live lane (DEBUG)",
/// or call them from a unit test. Each returns a report and also prints it to the Xcode console.
///
/// - `selfCheck()`: no network. Encodes every fixture, checks the privacy rules (allowed keys at every level, no
///   run of 3+ digits, no stored String), the option rules, and the body budget; checks the Review body too.
/// - `replay()`: no network. Drives a `.show` coach through a scripted 20 s stuck episode with a stub reply and
///   prints every decision, so the trigger / debounce / display policy can be read end to end.
/// - `probe()`: uses the real key. One live call per fixture that has 2+ options; prints status, round trip,
///   whether the connection was reused, model, tokens, request id, the answer, and the display verdict.
/// - `latency(calls:spacing:)`: uses the real key. N live calls spaced like real triggers (default 20 × 8 s),
///   p50 / p95 round trip, reuse count, failures. Run it at an outside wall on LTE before enabling `.show`.
@MainActor
enum JevLiveDebug {
    struct Fixture {
        let name: String
        let context: JevLiveContext
        var textFirstReadRecently = false
    }

    /// Stuck situations seen or expected at a meter or panel. Buckets only.
    static let fixtures: [Fixture] = [
        Fixture(name: "meter_small_dark_blurry", context: JevLiveContext(
            step: .findMeter, stuck: .s8to15, tipTried: .holdStill, seen: .often, size: .small, onWall: .yes,
            mainFail: .blurry, light: .dark, reads: .noReads, cues: [])),
        Fixture(name: "meter_glare_small", context: JevLiveContext(
            step: .findMeter, stuck: .s15to30, tipTried: .faceLabel, seen: .steady, size: .small, onWall: .yes,
            mainFail: .bright, light: .bright, reads: .empty, cues: [.meterWord])),
        Fixture(name: "meter_ac_unit", context: JevLiveContext(
            step: .findMeter, stuck: .s15to30, tipTried: .closerToLabel, seen: .steady, size: .ok, onWall: .yes,
            mainFail: .noDominant, light: .ok, reads: .appliance, cues: [.applianceWord])),
        Fixture(name: "meter_not_on_this_wall", context: JevLiveContext(
            step: .findMeter, stuck: .s30plus, tipTried: .pointAtMeter, seen: .never, size: .noTarget, onWall: .unknown,
            mainFail: .noDominant, light: .ok, reads: .noReads, cues: [])),
        Fixture(name: "meter_seen_off_wall_dim", context: JevLiveContext(
            step: .findMeter, stuck: .s8to15, tipTried: .aimAtWall, seen: .often, size: .tooSmall, onWall: .no,
            mainFail: .notOnWall, light: .dark, reads: .noReads, cues: [])),
        Fixture(name: "panel_nothing_seen", context: JevLiveContext(
            step: .findPanel, stuck: .s15to30, tipTried: .pointAtPanel, seen: .rarely, size: .noTarget, onWall: .unknown,
            mainFail: .noDominant, light: .ok, reads: .noReads, cues: [])),
        Fixture(name: "panel_door_closed_dark", context: JevLiveContext(
            step: .findPanel, stuck: .s15to30, tipTried: .pointAtPanel, seen: .steady, size: .ok, onWall: .yes,
            mainFail: .dark, light: .dark, reads: .empty, cues: [])),
        Fixture(name: "panel_cut_off_steep", context: JevLiveContext(
            step: .findPanel, stuck: .s8to15, tipTried: .openPanelDoor, seen: .steady, size: .cutOff, onWall: .yes,
            mainFail: .mixed, light: .ok, reads: .noReads, cues: [.panelWord]))
    ]

    // MARK: - Self-check (no network)

    @discardableResult
    static func selfCheck() -> String {
        var lines = ["Jev live self-check (no network) model=\(JevTransport.pinnedModel) questions_v=\(JevLiveQuestions.version)"]
        var failures = 0
        for fixture in fixtures {
            let problems = privacyProblems(fixture.context)
            failures += problems.count
            let options = JevLiveQuestions.options(for: fixture.context, textFirstReadRecently: fixture.textFirstReadRecently)
            let stateBytes = (try? fixture.context.encoded().count) ?? -1
            let bodyBytes = (try? JevLiveQuestions.requestBody(context: fixture.context, options: options).count) ?? -1
            let route = switch options.count {
            case 0: "nothing"
            case 1: "rule \(options[0].rawValue)"
            default: "ask jev"
            }
            let over = bodyBytes > JevLiveTuning.bodyBudgetBytes
            if over { failures += 1 }
            lines.append("\(fixture.name): options=[\(options.map(\.rawValue).joined(separator: ","))] → \(route); "
                + "state=\(stateBytes) B body=\(options.count >= 2 ? "\(bodyBytes) B" : "-")\(over ? " OVER BUDGET" : "")"
                + (problems.isEmpty ? "" : " PRIVACY: " + problems.joined(separator: "; ")))
        }
        let review = reviewProblems()
        failures += review.count
        lines.append(review.isEmpty ? "review body: ok" : "review body PRIVACY: " + review.joined(separator: "; "))
        lines.append(failures == 0 ? "PASS" : "FAIL (\(failures))")
        return report(lines)
    }

    /// Keys outside the allow-list at any level, runs of 3+ digits, or a stored String anywhere in the type.
    static func privacyProblems(_ context: JevLiveContext) -> [String] {
        var problems: [String] = []
        guard let data = try? context.encoded(),
              let json = String(data: data, encoding: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return ["does not encode"] }
        let keys = allKeys(in: object)
        let extra = keys.subtracting(JevLiveContext.allowedKeys)
        if !extra.isEmpty { problems.append("keys not allowed: \(extra.sorted().joined(separator: ","))") }
        if json.range(of: #"\d{3,}"#, options: .regularExpression) != nil { problems.append("3+ digit run") }
        let strings = storedStrings(in: context, path: "state")
        if !strings.isEmpty { problems.append("stored String at \(strings.joined(separator: ","))") }
        return problems
    }

    /// The Review body of an empty survey: no raw distance, no requirement sentence, no contact field.
    static func reviewProblems() -> [String] {
        var session = SurveySession.new(propertyIdentifier: "")
        session.placement.distanceToMeterFeet = 12.5
        guard let data = try? TypeSafeJevClient.requestBody(for: session),
              let object = try? JSONSerialization.jsonObject(with: data) else { return ["does not encode"] }
        let banned: Set<String> = ["meterFeet", "wallFeet", "gasFeet", "meterHeightFeet", "requirement", "email", "phone",
                                   "contactName", "propertyIdentifier", "propertyLocation", "meterNumber", "visit_ready"]
        let found = allKeys(in: object).intersection(banned)
        var problems = found.isEmpty ? [] : ["keys: \(found.sorted().joined(separator: ","))"]
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.contains("12.5") { problems.append("raw distance") }
        if !text.contains("\"model\":\"\(JevTransport.pinnedModel)\"") { problems.append("model not pinned") }
        return problems
    }

    static func allKeys(in object: Any) -> Set<String> {
        if let dictionary = object as? [String: Any] {
            return dictionary.reduce(into: Set(dictionary.keys)) { $0.formUnion(allKeys(in: $1.value)) }
        }
        if let array = object as? [Any] {
            return array.reduce(into: Set<String>()) { $0.formUnion(allKeys(in: $1)) }
        }
        return []
    }

    static func storedStrings(in value: Any, path: String) -> [String] {
        if value is String || value is Substring { return [path] }
        return Mirror(reflecting: value).children.flatMap { child in
            storedStrings(in: child.value, path: path + "." + (child.label ?? "_"))
        }
    }

    // MARK: - Replay (no network)

    /// A stub that answers every live call at once with a fixed Choice answer.
    final class StubSender: JevLiveSending, @unchecked Sendable {
        var answer: JevAnswer
        var failure: JevCallFailure?
        private(set) var calls = 0
        private(set) var bodies: [Data] = []

        init(answer: JevAnswer, failure: JevCallFailure? = nil) {
            self.answer = answer
            self.failure = failure
        }

        var isAvailable: Bool { true }

        func post(_ body: Data, profile: JevTransport.Profile) async -> JevCallResult {
            calls += 1
            bodies.append(body)
            if let failure { return .failure(failure) }
            return .success(JevReply(
                model: JevTransport.pinnedModel,
                answers: [JevLiveQuestions.questionID: answer],
                usage: JevUsage(inputTokens: nil, outputTokens: nil),
                requestID: "stub",
                status: 200,
                roundTrip: .milliseconds(1),
                attempts: 1,
                network: nil,
                requestBytes: body.count
            ))
        }

        func warmUp() async {}
    }

    /// 20 s on findMeter with "Hold still" up, the label small and dim. The stub picks add_light at 0.71.
    @discardableResult
    static func replay() async -> String {
        var now = ContinuousClock.now
        let stub = StubSender(answer: JevAnswer(
            type: "choice", choice: "add_light", confidence: 0.71,
            probabilities: ["add_light": 0.78, "closer_to_label": 0.15, "none": 0.07]
        ))
        let coach = JevLiveCoach(mode: .show, sender: stub, clock: { now })
        var lines: [String] = []
        coach.onRecord = { lines.append($0.line) }
        coach.begin(surveyID: UUID())
        let scan = JevScanSignals(
            available: true, seen: .often, size: .small, onWall: .yes, mainFail: .blurry, light: .dark,
            shake: nil, reads: .noReads, cues: [], passedRecently: false, textFirstReadRecently: false
        )
        for second in 0...20 {
            coach.update(JevLiveSnapshot(step: .findMeter, deviceTip: .holdStill, deviceTipIsCaptureHint: false, scan: scan))
            await coach.settle()
            if let tip = coach.suggestion { lines.append("t=\(second)s SHOWING \(tip.instruction.rawValue) (\(tip.source.rawValue))") }
            now += .seconds(1)
        }
        coach.end()
        lines.append("stub calls: \(stub.calls)")
        return report(["Jev live replay (stub, no network)"] + lines)
    }

    // MARK: - Probe and latency (real key)

    @discardableResult
    static func probe(transport: JevTransport = .shared) async -> String {
        guard transport.isAvailable else { return report(["Jev live probe: no key, nothing sent"]) }
        var lines = ["Jev live probe (real calls) model=\(JevTransport.pinnedModel)"]
        for fixture in fixtures {
            let options = JevLiveQuestions.options(for: fixture.context, textFirstReadRecently: fixture.textFirstReadRecently)
            guard options.count >= 2 else {
                lines.append("\(fixture.name): \(options.first.map { "rule \($0.rawValue)" } ?? "nothing"), no call")
                continue
            }
            guard let body = try? JevLiveQuestions.requestBody(context: fixture.context, options: options) else {
                lines.append("\(fixture.name): encode failed")
                continue
            }
            switch await transport.post(body, profile: .live) {
            case .success(let reply):
                lines.append("\(fixture.name): \(reply.logLine)")
                if let answer = JevLiveAnswer(reply.answers[JevLiveQuestions.questionID]) {
                    let verdict = switch JevLiveQuestions.verdict(answer, options: options) {
                    case .pass(let pick): "WOULD SHOW \(pick.rawValue): \"\(pick.copy(for: fixture.context.step))\""
                    case .reject(let reason): "reject \(reason.rawValue)"
                    }
                    lines.append("  choice=\(answer.choice) confidence=\(String(format: "%.2f", answer.confidence)) "
                        + "[\(answer.probabilitiesLine)] → \(verdict)")
                } else {
                    lines.append("  no next_try answer")
                }
            case .failure(let failure):
                lines.append("\(fixture.name): FAILED \(failure)")
            }
        }
        return report(lines)
    }

    @discardableResult
    static func latency(calls: Int = 20, spacing: Duration = .seconds(8), transport: JevTransport = .shared) async -> String {
        guard transport.isAvailable else { return report(["Jev live latency: no key, nothing sent"]) }
        let fixture = fixtures[0]
        let options = JevLiveQuestions.options(for: fixture.context, textFirstReadRecently: false)
        guard let body = try? JevLiveQuestions.requestBody(context: fixture.context, options: options) else {
            return report(["Jev live latency: encode failed"])
        }
        var times: [Int] = []
        var reused = 0
        var failures: [String] = []
        var lines = ["Jev live latency: \(calls) calls, \(JevTransport.milliseconds(spacing)) ms apart, body \(body.count) B"]
        for index in 0..<calls {
            if index > 0 { try? await Task.sleep(for: spacing) }
            switch await transport.post(body, profile: .live) {
            case .success(let reply):
                let ms = JevTransport.milliseconds(reply.roundTrip)
                times.append(ms)
                if reply.network?.reusedConnection == true { reused += 1 }
                lines.append("#\(index + 1) \(ms) ms \(reply.network?.summary ?? "net=-") in=\(reply.usage?.inputTokens.map(String.init) ?? "-")")
            case .failure(let failure):
                failures.append("#\(index + 1) \(failure)")
                lines.append("#\(index + 1) FAILED \(failure)")
            }
        }
        let sorted = times.sorted()
        func percentile(_ p: Double) -> Int {
            guard !sorted.isEmpty else { return -1 }
            return sorted[min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.up)) - 1)]
        }
        lines.append("p50=\(percentile(0.5)) ms p95=\(percentile(0.95)) ms max=\(sorted.last ?? -1) ms "
            + "reused=\(reused)/\(times.count) failures=\(failures.count) budget=\(JevTransport.milliseconds(transport.liveBudgetNow)) ms")
        return report(lines)
    }

    private static func report(_ lines: [String]) -> String {
        let text = lines.joined(separator: "\n")
        print(text)
        return text
    }
}
#endif
