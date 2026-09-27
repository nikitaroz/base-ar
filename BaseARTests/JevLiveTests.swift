import XCTest
@testable import BaseAR

/// The live Jev lane without a network: privacy of the payload, bucket edges, option rules, the acceptance check,
/// and the coach's trigger / display policy against a stub sender. No test here calls TypeSafe.
@MainActor
final class JevLiveTests: XCTestCase {
    override func setUp() async throws {
        JevLiveCoach.resetRunState()
    }

    func testPayloadIsPrivacySafeAndInBudget() throws {
        for fixture in JevLiveDebug.fixtures {
            XCTAssertEqual(JevLiveDebug.privacyProblems(fixture.context), [], fixture.name)
            let options = JevLiveQuestions.options(for: fixture.context, textFirstReadRecently: false)
            let body = try JevLiveQuestions.requestBody(context: fixture.context, options: options)
            XCTAssertLessThanOrEqual(body.count, JevLiveTuning.bodyBudgetBytes, fixture.name)
            let json = try XCTUnwrap(String(data: body, encoding: .utf8))
            XCTAssertTrue(json.contains("\"model\":\"jev-1.13.0\""))
            XCTAssertFalse(json.contains("seq"), "seq never goes in the request")
        }
        XCTAssertEqual(JevLiveDebug.reviewProblems(), [])
    }

    func testBucketEdgesMatchTheCaptureGate() {
        XCTAssertEqual(JevLiveContext.Size(area: nil), .noTarget)
        XCTAssertEqual(JevLiveContext.Size(area: 0.059), .tooSmall)
        XCTAssertEqual(JevLiveContext.Size(area: 0.06), .small)
        XCTAssertEqual(JevLiveContext.Size(area: 0.15), .ok)
        XCTAssertEqual(JevLiveContext.Size(area: 0.8), .ok)
        XCTAssertEqual(JevLiveContext.Size(area: 0.81), .cutOff)
        XCTAssertNil(JevLiveContext.Stuck(onScreenFor: .milliseconds(7999)))
        XCTAssertEqual(JevLiveContext.Stuck(onScreenFor: .seconds(8)), .s8to15)
        XCTAssertEqual(JevLiveContext.Stuck(onScreenFor: .seconds(15)), .s15to30)
        XCTAssertEqual(JevLiveContext.Stuck(onScreenFor: .seconds(30)), .s30plus)
        XCTAssertEqual(JevLiveContext.Seen(boxes: 0), .never)
        XCTAssertEqual(JevLiveContext.Seen(boxes: 5), .rarely)
        XCTAssertEqual(JevLiveContext.Seen(boxes: 6), .often)
        XCTAssertEqual(JevLiveContext.Seen(boxes: 15), .steady)
        XCTAssertEqual(JevScanRings.dominantFail(Array(repeating: .tooSmall, count: 10) + Array(repeating: .pass, count: 10)), .tooSmall)
        XCTAssertEqual(JevScanRings.dominantFail(Array(repeating: .tooSmall, count: 6) + Array(repeating: .dark, count: 6)), .mixed)
        XCTAssertEqual(JevScanRings.dominantFail(Array(repeating: .noCandidate, count: 20)), .noDominant)
        XCTAssertEqual(JevGateOutcome(gateDecision: "fail:holdStill"), .blurry)
        XCTAssertEqual(JevGateOutcome(gateDecision: "rejected meter-box height"), .rejected)
    }

    func testRingsStaySilentWithoutRecentPackets() {
        var rings = JevScanRings()
        let start = ContinuousClock.now
        XCTAssertFalse(rings.signals(now: start).available)
        rings.record(JevPacketSignal(targetSeen: true, outcome: .tooSmall, area: 0.05, onWall: true, light: .ok), now: start)
        XCTAssertTrue(rings.signals(now: start + .seconds(1)).available)
        XCTAssertFalse(rings.signals(now: start + .seconds(7)).available)
    }

    func testOptionRulesAndVetoes() {
        let away = JevLiveDebug.fixtures.first { $0.name == "meter_not_on_this_wall" }!.context
        XCTAssertEqual(JevLiveQuestions.options(for: away, textFirstReadRecently: false), [.tryOtherWall])
        // A meter word, or a text-first read in the last 5 s, means the meter may be right here.
        var worded = away
        worded.cues = [.meterWord]
        XCTAssertEqual(JevLiveQuestions.options(for: worded, textFirstReadRecently: false), [])
        XCTAssertEqual(JevLiveQuestions.options(for: away, textFirstReadRecently: true), [])
        var early = away
        early.stuck = .s8to15
        XCTAssertEqual(JevLiveQuestions.options(for: early, textFirstReadRecently: false), [])
        // The phone's own line is never offered back, and a tip that just left the screen is not either.
        let dim = JevLiveDebug.fixtures[0].context
        XCTAssertEqual(JevLiveQuestions.options(for: dim, textFirstReadRecently: false), [.addLight, .closerToLabel])
        XCTAssertEqual(JevLiveQuestions.options(for: dim, textFirstReadRecently: false, excluding: [.addLight]), [.closerToLabel])
        var small = dim
        small.tipTried = .getCloser
        XCTAssertFalse(JevLiveQuestions.options(for: small, textFirstReadRecently: false).contains(.closerToLabel))
    }

    func testVerdictThresholds() {
        let options: [JevLiveInstruction] = [.addLight, .closerToLabel]
        func answer(_ choice: String, _ confidence: Double, _ p: Double, none: Double) -> JevLiveAnswer {
            var probabilities = [choice: p]
            probabilities["none"] = none
            return JevLiveAnswer(choice: choice, confidence: confidence, probabilities: probabilities)
        }
        XCTAssertEqual(JevLiveQuestions.verdict(answer("add_light", 0.59, 0.8, none: 0.1), options: options), .reject(.lowConfidence))
        XCTAssertEqual(JevLiveQuestions.verdict(answer("add_light", 0.7, 0.40, none: 0.30), options: options), .reject(.lowMargin))
        XCTAssertEqual(JevLiveQuestions.verdict(answer("none", 0.9, 0.9, none: 0.9), options: options), .reject(.pickedNone))
        XCTAssertEqual(JevLiveQuestions.verdict(answer("hold_still", 0.9, 0.9, none: 0), options: options), .reject(.outOfSet))
        XCTAssertEqual(JevLiveQuestions.verdict(answer("add_light", 0.6, 0.6, none: 0.45), options: options), .pass(.addLight))
    }

    // MARK: - Coach

    private let stuckScan = JevScanSignals(
        available: true, seen: .often, size: .small, onWall: .yes, mainFail: .blurry, light: .dark,
        shake: nil, reads: .noReads, cues: [], passedRecently: false, textFirstReadRecently: false
    )

    private func snapshot(_ step: JevLiveContext.Step? = .findMeter, holds: JevLiveHolds = [], scan: JevScanSignals? = nil) -> JevLiveSnapshot {
        JevLiveSnapshot(step: step, deviceTip: .holdStill, deviceTipIsCaptureHint: false, scan: scan ?? stuckScan, holds: holds)
    }

    private func addLightStub() -> JevLiveDebug.StubSender {
        JevLiveDebug.StubSender(answer: JevAnswer(
            type: "choice", choice: "add_light", confidence: 0.71,
            probabilities: ["add_light": 0.78, "closer_to_label": 0.15, "none": 0.07]
        ))
    }

    func testCoachAsksOnceWhenStuckAndShowsOnlyInShowMode() async {
        var now = ContinuousClock.now
        let stub = addLightStub()
        let coach = JevLiveCoach(mode: .shadow, sender: stub, clock: { now })
        var decisions: [String] = []
        coach.onRecord = { entry in if entry.kind == .decision { decisions.append(entry.fields["decision"] ?? "?") } }
        coach.begin(surveyID: UUID())
        for _ in 0..<8 {
            coach.update(snapshot())
            await coach.settle()
            now += .seconds(1)
        }
        XCTAssertEqual(stub.calls, 0, "nothing before 8 s on the same tip")
        for _ in 0..<3 {
            coach.update(snapshot())
            await coach.settle()
            now += .seconds(1)
        }
        XCTAssertEqual(stub.calls, 1, "one call once stuck and debounced; the same state is not asked again")
        XCTAssertEqual(decisions, ["shadow_shown"])
        XCTAssertNil(coach.suggestion, "shadow mode shows nothing")
        coach.mode = .show
        XCTAssertEqual(coach.suggestion?.instruction, .addLight)
        XCTAssertEqual(coach.suggestion?.text, "Too dark \u{2014} add light")
        // A tracking hold clears it at once; a step change resets everything.
        coach.update(snapshot(holds: .tracking))
        XCTAssertNil(coach.suggestion)
        coach.update(snapshot(.findPanel))
        XCTAssertNil(coach.suggestion)
        coach.end()
    }

    func testCoachIsSilentWithoutKeyOrScanSignals() async {
        var now = ContinuousClock.now
        let keyless = JevLiveCoach(mode: .show, sender: JevTransport(apiKey: nil), clock: { now })
        XCTAssertFalse(keyless.isEnabled)
        let stub = addLightStub()
        let unwired = JevLiveCoach(mode: .show, sender: stub, clock: { now })
        for _ in 0..<20 {
            keyless.update(snapshot())
            unwired.update(snapshot(scan: JevScanSignals()))
            await unwired.settle()
            now += .seconds(1)
        }
        XCTAssertNil(keyless.suggestion)
        XCTAssertNil(unwired.suggestion)
        XCTAssertEqual(stub.calls, 0)
    }

    func testRejectedKeyTurnsTheLaneOffForTheRun() async {
        var now = ContinuousClock.now
        let stub = addLightStub()
        stub.failure = .http(status: 401, retryAfter: nil, requestID: nil, detail: nil)
        let coach = JevLiveCoach(mode: .show, sender: stub, clock: { now })
        for _ in 0..<12 {
            coach.update(snapshot())
            await coach.settle()
            now += .seconds(1)
        }
        XCTAssertEqual(stub.calls, 1)
        XCTAssertFalse(coach.isEnabled)
        XCTAssertFalse(JevLiveCoach(mode: .show, sender: stub).isEnabled)
    }

    func testCaptureHintOutranksJevByDefault() async {
        var now = ContinuousClock.now
        let stub = addLightStub()
        let coach = JevLiveCoach(mode: .show, sender: stub, clock: { now })
        for _ in 0..<12 {
            coach.update(JevLiveSnapshot(step: .findMeter, deviceTip: .holdStill, deviceTipIsCaptureHint: true, scan: stuckScan))
            await coach.settle()
            now += .seconds(1)
        }
        XCTAssertEqual(stub.calls, 1, "still asked, for the shadow log")
        XCTAssertNil(coach.suggestion, "a capture hint outranks a Jev tip unless the team decides otherwise")
    }
}
