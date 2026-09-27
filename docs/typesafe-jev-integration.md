# TypeSafe Jev in Base Site Survey

Status as of 26 Sep 2026, branch `claude/jev-live`.

Jev reads text only. It cannot see pixels, so it cannot make detection more accurate. On this app, accurate object and image detection comes from the phone itself:

- the detector, plus a check of what the detected object really is;
- physics gates for blur, readable text size, viewing angle and depth confidence;
- OCR on a sharp frame, with two reads that must agree;
- tracking across several frames.

Jev has a narrower job. Once the phone's own tip has stopped working, Jev combines those signals, already turned into words, into one recovery instruction that the app wrote. It can only be as good as the phone's signals.

Jev is always advisory. It never:

- changes a rule outcome, the placement tone or its colour;
- locks, captures or passes a step;
- moves a step clock.

Without a key it makes no call, and the app behaves exactly as it does without Jev.

## Measured facts (owner's session, 26 Sep 2026)

| Fact | Value |
|---|---|
| Endpoint | `POST https://api.typesafe.ai/v1/systemone` |
| `jev-latest` | Resolved to `jev-1.13.0`. The app now pins `jev-1.13.0`. |
| Round trip | 0.19–0.32 s from a Mac, 5 calls, all HTTP 200. Not measured on LTE. |
| Tokens | 1-question live request: about 873 in / 87 out. 4-question Review set: about 997 / 147. |
| Answer shapes | `noul`: a probability of yes (e.g. 0.12). `score`: a fractional value, with `legend` and `probabilities`. `choice`: `choice`, `confidence` and `probabilities`. |
| First live test | `next_instruction` on findPanel, 14 s on the step: `find_panel_label` p = 0.38, confidence 0.26, `no_change` p = 0.29. That is close to a tie, so Jev is noise without better phone signals. |
| Payload size | Measured on this Mac with no network, from the new code. State: 169–211 B. Body: 0.8–0.9 KB with 2 options, 1.26 KB with 5. Tokens are not published, so read `usage.input_tokens` from the first real call. |

## Files

All files are in `BaseAR/Review/`. Every live-lane file except `JevLiveCoach.swift` and the DEBUG hooks uses Foundation only.

| File | What it holds |
|---|---|
| `JevTransport.swift` | One warm ephemeral `URLSession` for both lanes, a time budget per call, retries, error mapping, `Retry-After`, request id, network metrics, and the response types. |
| `JevLiveContext.swift` | The `state` type, the phone's line as an id (`JevDeviceTip`), the snapshot the view builds, and the on-device rings (`JevScanRings`). |
| `JevLiveQuestions.swift` | Every tuning number (`JevLiveTuning`), the app-written instructions (`JevLiveInstruction`), the option rules, the Choice question, and the acceptance check. |
| `JevLiveCoach.swift` | The `@MainActor @Observable` coach: triggers, debounce, one request in flight, cancel on change, cache, backoff, display policy and log. The header comment is the integration guide for `PlacementARView`. |
| `JevLiveDebug.swift` | DEBUG test hooks. |
| `TypeSafeJevClient.swift` | The Review advisory, now "Review set v2". |

## Live mode

### Modes

The mode comes from the UserDefaults key `JevLiveMode`, set for example with the launch argument `-JevLiveMode show`.

| Mode | Behaviour |
|---|---|
| `off` | No calls. The Release default. |
| `shadow` | Ask Jev and log the answer, but show nothing. The DEBUG default. |
| `show` | Demo toggle. Jev tips, and one-option rule tips, appear on the bottom line. |

### When Jev is asked

Jev is asked only when all of these hold:

- The step is findMeter or findPanel.
- The phone's own tip has been on screen for 8 s or more. A change to that tip counts only after it holds for 1 s.
- No gate has passed in the last 3 s.
- Nothing is locked.
- The scan rings have recent packets (`scan.available`).

Jev is not asked while any of these hold:

- an error or camera problem;
- paused for capture;
- a tracking message;
- the coaching overlay;
- a flash confirmation;
- the detector is down;
- a label is being read;
- the phone is leaving the step.

### Options, built in code

An instruction is offered only if all three hold:

- its one-field condition holds in `state`;
- it is not the phone's own line;
- it has not been on screen in the last 15 s.

| Id | Copy | Condition |
|---|---|---|
| `hold_still` | Hold still | `shake` is high, or `main_fail` is blurry |
| `add_light` | Too dark — add light | `light` is dark, or `main_fail` is dark |
| `shade_label` | Too bright — shade the label | `light` is bright, or `main_fail` is bright |
| `face_label` | Turn so the label faces you | `main_fail` is steep |
| `aim_at_wall` | Aim at the wall | `seen` is often or steady, and `on_wall` is no |
| `step_back` | Take a few steps back | `size` is cut_off |
| `closer_to_label` | Get closer to the label | `size` is too_small or small, or (meter only) `reads` is empty while `size` is ok |
| `not_that_box` | **NEW:** That’s not the meter. Look for the glass dial / That’s not the panel. Look for a gray metal door | `reads` is appliance, or `cues` has appliance_word with no meter or panel word |
| `open_panel_door` | Open the panel door, not the cover | Panel only: seen often or steady, size ok, reads none or empty, no cues |
| `try_other_wall` | **NEW:** Try another outside wall | `seen` is never or rarely, stuck 15 s or more, no meter or panel word, and no text-first read in the last 5 s |
| `panel_indoors` | **NEW:** Check the garage or utility room | Panel only, with the same condition as `try_other_wall` |

**New copy needs approval.** The three NEW lines have never been approved.

How many options remain decides what happens:

| Options | What happens |
|---|---|
| 0 | Nothing is shown. |
| 1 | The phone shows it without asking Jev. This is the fixed-rule baseline. |
| 2 or more | One Choice question, `next_try`, over those options plus `none`. |

The question text is fixed per step. Each option's rubric has `what` and `not_for` fields, and each names one state field. Question ids are never sent to the model.

### The `state` payload (`JevLiveContext`)

The encoded `state` has these keys:

- `step`
- `stuck` (8_15s | 15_30s | 30s_plus)
- `tip_tried`
- `seen` (never | rarely | often | steady, from the last 20 packets)
- `size` (none | too_small | small | ok | cut_off; edges 0.06, 0.15 and 0.8)
- `on_wall`
- `main_fail` (the failure in 10 or more of the last 20 packets, or mixed, or none)
- `light` (dark | ok | bright)
- `shake` (optional, low | high; sent only once the blur-risk gate exists)
- `reads` (none | empty | disagree | appliance)
- `cues` (meter_word, panel_word, appliance_word)

Encoding rules:

- Enums only.
- snake_case keys, sorted.
- nil fields drop out.
- No `seq`, survey id or version in the state.

### Cadence and transport

**Pacing:**

- The freshness key is (step epoch, `tip_tried`, `main_fail`, `seen`, option set).
- The key must hold for 750 ms before a send.
- Jev is asked again when the `stuck` bucket changes or the key changes.
- One request is in flight at a time, and it is cancelled when the key or the step changes.
- Sends are at least 3 s apart.
- At most 6 sends per step and 20 per survey.
- A cache of 32 replies, keyed by the exact request bytes, per survey.

**Transport:**

| Setting | Live | Review |
|---|---|---|
| Time budget | 2.0 s total on a non-expensive path; 2.5 s on an expensive or unknown path | 5 s idle, 15 s total |
| Low Data Mode | Off | Allowed |
| Retries | One, only when a reused connection was reset | One, on 408, 429, 529 or 5xx, honouring `retry-after-ms` or `Retry-After` up to 3 s |

**Warm-up:** when the Live Survey opens with the lane on, the app sends one `GET /v1/models`. It uses no tokens.

**Failures:**

| Response | Behaviour |
|---|---|
| 429, 529, 5xx, timeout or offline | Rest 30 s, or for `Retry-After` if longer (cap 60 s) |
| Low Data Mode | Rest 60 s |
| 401 or 403 | Off for this app run |
| 422 | Off for this question-set version |

### Display policy

**Accepting a reply.** A reply is accepted only if all of these hold:

- the step epoch and freshness key are the same as at the send;
- no skip rule holds;
- the pick is one of the options sent, and not `none`;
- `confidence` is 0.60 or more;
- our own margin, p(pick) − p(none), is 0.15 or more;
- the pick's condition still holds on the current state (this is the veto).

**Where the tip sits.** The tip sits below error, tracking, flash, capture feedback and the detector hint, and above the step's motion line only.

- By default a Jev tip never replaces a capture or detector hint (`mayReplaceCaptureHint = false`; spec §8 Q2). Such replies are logged as `outranked`.

**Dwell and stability:**

- A tip stays on screen for 3–8 s. The same tip is not shown again for 15 s.
- A re-ask that picks the same tip keeps it while `confidence` stays at 0.45 or more.
- A different Jev pick replaces the tip only after 3 s on screen, and only with a margin of 0.25 or more. A weaker different pick clears the old tip.

**What clears a tip:**

- a step change;
- a lock or capture;
- a gate pass;
- a tracking or error hold;
- a change of the phone's line that holds for 1 s.

No confidence number is ever shown live.

### Log

Every event is logged: begin, step, request, reply, decision, skip, clear, outcome, progress, failure, cancel and end.

Each event goes to:

- `os_log` in DEBUG (subsystem `BaseAR`, category `JevLive`);
- `coach.onRecord`, for FrameRecorder metadata.

Each entry carries:

- `seq` and the step epoch;
- the trigger;
- whether it was a cache hit;
- round-trip ms, HTTP status, `model`, `usage` and the request id;
- network metrics: protocol, reused connection, expensive path;
- the encoded state;
- the options and the baseline pick;
- choice, confidence, margin and all probabilities;
- the decision code (`shown`, `shadow_shown`, `kept`, `none`, `out_of_set`, `low_confidence`, `low_margin`, `stale`, `held`, `outranked` or `unstable`);
- dwell ms and what cleared the tip;
- the outcome within 10 s (lock, capture, step_changed or none_in_10s).

`noteProgress` also logs which tip was up and which failure held just before a lock or capture. These are the weak labels used to score shadow picks.

## Privacy

**Sent:**

- the step;
- time on the tip, as a bucket;
- the id of the phone's line;
- geometry and light, as buckets;
- read outcome, as a bucket;
- three word flags (meter, panel, appliance).

**Never sent:**

- name, email, phone, address, GPS or heading;
- OCR text, digits, digit count or grouping;
- timestamps;
- device model, survey id or `seq`;
- poses or dimensions;
- photos, crops or embeddings.

The server still sees the request time and the phone's IP address, which gives a coarse location. One survey's requests also arrive in a row. TypeSafe keeps requests "as long as necessary", so assume every request is kept.

**Enforcement** (`JevLiveTests`, and the DEBUG self-check):

- The keys at every level must equal an allow-list.
- No run of 3 or more digits.
- No stored String anywhere in the type.

**Review set v2 changes:**

- sends rule statuses, without the requirement sentences;
- sends a "measured" flag instead of each raw distance;
- drops `visit_ready`;
- still sends no contact fields, meter number or photos.

**Open risks:**

- The key can be pulled out of `Info.plist`.
- The rate limit (1,200/min) is shared with Review, dev testing and any replay. Don't replay during the demo, and rotate the key after the hackathon.
- FrameLog (on the recorder branch) holds photos of the house and the meter number in pixels. Nothing leaves the phone without a team decision, only team members label, frames are deleted after labelling, and `UIFileSharingEnabled` must be Debug-only.

## Review advisory (Review set v2)

The question set:

- `next_action`: proceed / need_more_photos / conflict / other.
- `blocking_gap`: unchanged.
- `readiness_score`: unchanged.

Readiness itself comes from the Review readiness card, which computes it in code. The card shows "N% confidence" for Choice and Score answers, which is not a probability of yes. With `visit_ready` gone, no yes/no (Noul) question is left. If one is added, band its answer at 0.8 and 0.2 and label it as a probability.

A DEBUG line shows the model, input tokens, round-trip ms and request id.

## Test hooks (DEBUG, no curl)

Open Review → Jev advisory (a key must be set) → **Live lane (DEBUG)**. Each report also prints to the Xcode console.

| Button | Network | What it does |
|---|---|---|
| Self-check | none | Checks privacy, option routing and body size for 8 fixtures, and checks the Review body |
| Replay | none (stub) | Runs a scripted 20 s stuck episode through a `.show` coach and prints every decision |
| Probe | real key | Sends one live call per fixture that has 2 or more options. Prints status, ms, protocol, reused connection, model, tokens, request id, choice, confidence, probabilities, and the verdict (`WOULD SHOW …` or `reject …`) |
| Latency ×20 | real key | Sends 20 live calls 8 s apart. Prints p50, p95, max, reused count and failures |

**To check on the device with the real key:**

1. Run Probe on Wi-Fi.
   - Check that `model=jev-1.13.0`.
   - Check `in_tokens` for each fixture. The estimate is well under the 873 of the owner's 1-question test; record the real number here.
   - Check whether the verdicts look sensible.
2. Run Latency ×20 on LTE at an outside wall.
   - Record p50 and p95.
   - Check `reused=`. If most calls are not reused, the radio is waking and TLS is being redone.
   - Keep the 2.0 / 2.5 s budget only if p95 is 1.0 s or less.
3. Run a Live Survey with `-JevLiveMode shadow`, once `PlacementARView` is wired as the coach header describes. Filter Console for `JevLive`, then check:
   - requests fire only after 8 s on one tip;
   - there are no bursts;
   - decisions and outcomes are logged.
4. Switch to `-JevLiveMode show` for the demo toggle.

## Offline evaluation

**Data.** The shadow logs produce, for each stuck episode:

- the encoded state;
- the options;
- the baseline pick;
- Jev's full distribution;
- the display decision;
- the outcome within 10 s.

`noteProgress` adds automatic weak labels: the failure that cleared just before a capture, or a timeout.

**Replay tool.** A Mac CLI can compile `JevTransport.swift`, `JevLiveContext.swift` and `JevLiveQuestions.swift` as they are, so replayed payloads match the app byte for byte. This was checked on this Mac with `swiftc -swift-version 6`.

**Metrics.** Compare Jev with the fixed-rule baseline (the first option in `JevLiveInstruction.priority`) at equal coverage:

| Metric | Target |
|---|---|
| Precision of tips shown | 0.8 or more |
| Harmful tips | 0.05 or less |
| Flaps | 2 or fewer per minute |
| p95 latency on LTE | 1.0 s or less |

**Decision.** If Jev does not beat the baseline, ship the baseline, keep Jev for Review only, and leave the live lane on `shadow` or `off`.

**Tuning.**

- Tune only against the pinned `jev-1.13.0`, and re-tune if TypeSafe ships a new version.
- Every number is in `JevLiveTuning` and is marked "tune on device".
- Add `examples` to the criteria only once real FrameLog contexts exist.

## What the phone still needs

The coach stays silent until these exist:

| # | Needed | Where |
|---|---|---|
| a | `JevScanRings` owned by `PlacementSceneController`, plus `jevScanSignals()` | Controller |
| b | One `JevPacketSignal` per `evaluateCapture` exit: target seen, outcome, area, on-wall, light | `evaluateCapture` |
| c | Read outcomes. `.appliance` needs `isApplianceLabel` exposed; today an AC label counts as an empty read and the phone says "Get closer to the label". Also agreement with earlier reads, and cue flags from the parser. | `absorbRead`, `ScanTextParser` |
| d | `jevRings.reset()` | `resetCapture()` |
| e | Blur risk (\|ω\| × exposure × fx) | Later |
| f | The `feedbackAboveJev` / `deviceFeedback` split, and the Jev slot above the step line | `PlacementARView.feedback(_:)` |
| g | Point `onRecord` at FrameRecorder periodic-frame metadata, recording no extra frames | Optional |

On-device fixes worth more than Jev (spec §7):

- the blur-risk gate;
- the readable-size gate from the depth median;
- quality measured on the target's own box, where today `quality == nil` becomes "Hold still";
- a deterministic tip for height and ban rejects;
- `captureHighResolutionFrame` on lock.
