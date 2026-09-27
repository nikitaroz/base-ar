# Project Instructions

- This is a hackathon project. Prioritize speed, simplicity, and rapid iteration over production-level architecture or overengineering.
- Do not write, add, or generate unit tests for this project.
- Read `docs/context/README.md` before working on the Live Survey (AR), electrical rules, or a merge. It lists where this file, the code, and Base disagree.

## Product

**Base Site Survey** is a native iPhone app for a three-person hackathon. Base Power asks homeowners for electrical and site photos; engineers review them and may request more evidence. The app is a guided capture flow that produces a useful preliminary survey and an AR battery-placement preview.

It is a prototype. Never present it as final electrical, code, or permitting approval.

The Xcode target is `BaseAR`. The home-screen name is Base Site Survey.

## Constraints

- Apple frameworks only: SwiftUI, ARKit, RealityKit, Vision/VisionKit, Core ML, Core Location, and standard camera APIs. No third-party dependencies.
- Target a physical iPhone. AR needs a device; the simulator can walk Home Info and Review without world tracking.
- No backend, accounts, or external datasets. The one exception is below.
- **Exception: optional TypeSafe Jev advisory.** When `TYPESAFE_API_KEY` is set, Review shows a collapsed "Jev advisory" card that can `POST https://api.typesafe.ai/v1/systemone` for readiness guidance. It is advisory only: it never changes a rule outcome, the placement tone, its color, or `survey.json`. No key means no card and no network call. Errors and timeouts show "Advisory unavailable". It sends check results and home answers only, never name, contact, address, location, meter number, or photos. Code: `BaseAR/Review/TypeSafeJev*.swift`. The same key turns on **live Jev tips** on the Live Survey's find steps (`BaseAR/Review/JevLive*.swift`, `JevTransport.swift`): when the phone's own tip has been up 8 s with no gate pass and nothing locked, Jev picks one of the app's own instructions from bucketed scan signals (never digits, label text, or photos). The tip is the bottom line's lowest cue (every error, tracking, confirmation, capture, and detector line wins), stays 3–8 s, and never locks, captures, passes a step, moves a clock, or changes a rule or tone. `-JevLiveShadow YES` asks and logs without showing; `-JevLiveMode off` turns it off. No key, no call.
- On-device equipment detection is allowed as a capture aid, never as a verdict (see Detector below).
- Do not add ERCOT data beyond the embedded sample in `BaseAR/Grid` (context only, never a rule or the placement color), satellite imagery, a Base integration, or production-grade permitting logic unless a later task explicitly asks for it.
- GPS is the phone's property fix (latitude, longitude, timestamp, reported horizontal accuracy) when location permission is granted. Do not describe it as the precise battery position.
- Don't delete main features. Dead code stays unless a task removes it on purpose.

## Flow

Splash → Welcome ("Start survey") → three steps. Every main feature stays reachable from one of them.

1. **Home Info.** First launch shows the onboarding wizard, then the full form: name, email, phone, address (MapKit suggestions), own or rent, solar, portable generator, whole-home standby generator, existing whole-home battery, planned battery count (1 or 2), the panel bus rating when solar or two batteries apply, and **"Gas meter outside: Yes / No / Not sure"**. Choices are `RadioChoice` radio buttons. The property location fix is shown on a map with its accuracy circle. Next is always enabled; anything missing shows up in Review.
2. **Live Survey.** The AR camera, kept minimal:
   - **No top bar.** No Done, no title, no ••• menu. The one control is a small back chevron in the top-left corner, always shown (also during coaching and camera failures). Swiping right from the left edge and VoiceOver's escape gesture also leave. Leaving commits the scan so far, writes a checkpoint (`SurveyStore.checkpointScan()`), and goes back to the step the Live Survey was opened from (Review, or Home Info). If camera access is off or the AR session fails, both lines say so and stay up, and the step clocks stop.
   - **Exactly two lines of text.** One **top** line is the current task and changes as each job completes. One **bottom** line is the live feedback, with a `CoachTip` motion graphic (an animated SF Symbol), paced by `FeedbackPacer` so it does not flicker. Both hide while ARKit's coaching overlay is up.
   - **No tapping or clicking to mark anything.** No capture buttons (the back chevron is the only button), no gestures, no aiming ring, no battery drag. The lines give instructions only. The app captures by itself when recognition is reliable and the image is good: a detector box on the target (or, with no box, the label found by OCR in the middle of the screen) that lands on a real wall or depth patch and passes the lock guards, a steady, sharp, well-exposed frame for 3 evaluations in a row, and agreeing OCR reads (see OCR rules). The panel locks only through this capture gate (`PlacementSceneController.evaluateCapture`). The meter has no fallback (owner rule, 27 Sep): it advances only on a sharp meter photo with its number read twice alike; no clock moves it on without the number, and the left-edge swipe always leaves. The center-dot hold lock and "Mark it myself" are kept in the code but off. The gas meter is **shown**, not tapped (see Gas step).
   - **No raw feet on the camera.** Distances appear only in Review.
   - **Steps** (`LiveStep`): `findMeter → readMeter → findPanel → readBreaker → gas → lookAround → finish`. There is **no battery step**: the scan never asks anyone to place, slide, or confirm a battery. The battery spot is chosen in the background (see Battery spot), and the distance checks are measured at the early steps (see When each check is measured). Anything the scan cannot capture shows up in Review, which has the typed and retake paths. The Home Info gas answer decides the gas step: **No** skips it and records the homeowner's statement (attested, not measured); **Yes** or **Not sure** (or no answer) keeps it. A gas meter shown on the scan wins over the answer.
   - **Automatic finish.** On the first entry to `finish` in a visit: "Scanned" flashes, `finalizeBatterySuggestion()` plans the best candidate off the main thread and places it (its rig and transfer-switch box show), the scene is committed before and again once it is placed, the screen holds 1.5 s (`finishDwell`) from the placement, the scan is checkpointed, and Review opens. There is no scan screenshot: `placement.jpg` was dropped on main (b26886c) because the AR scan itself (`scene.ply` and the keyframes) is the placement evidence. A finished scan opened again says "Scan done" on top and "Scan done. Swipe from the left edge to go back" below; nothing advances by itself.
   - **No dead ends.** Every step ends by itself. The meter is the exception: it never times out. A panel that never captures moves on after 60 s (10 s with the detector down), unmarked, so its checks stay unknown and Review lists it; the next visit looks again. The panel's read step waits 3 s for the photo (4 s while a wider panel photo is pending); the meter's read step waits for the number. The gas step moves on unmarked after 40 s when Home Info said Yes and 15 s otherwise, plus 3 s if "Hold still" is showing at the deadline. The look-around moves on after 2 minutes on the step with the lines up (the time adds up across the clock's restarts and across visits); leaving during it runs the site check on what was scanned, and the look-around's own end runs it again. The grace times are `static let`s at the top of `PlacementARView`.
   - If tracking stays initializing or lacks detail, the bottom line says the camera can't see anything and to point the back camera at the wall.
3. **Review & Export.** "What's missing" rows lead to the step or screen that fixes each item (Home Info, the Live Survey, or the Electrical screen for a retake or a typed number). Then property, electrical, site-measurement, and eligibility-check details. Site measurements open with a **Suggested battery spot** card ("About X ft along the wall from the meter, on the panel side / on the other side. Y in from the wall.", or "No spot suggested: <reason>. An engineer will choose one."), then the pad rule rows (no scan photo; see Automatic finish). Confirm numbers read by scan; check the gas photo ("Shown on the scan: check the photo", with a "Not the gas meter" button); the optional Jev card; the `survey.json` preview; Share (one zip: `survey.json`, photos, `scene.ply`, and the `capture/` keyframes); Start over. Teal (attested) counts as ready in the readiness card. Debug builds add a "Test tools" card (see Frame recorder).

Visual theme everywhere except the camera: main's `ToneStyle`, `BrandMark`, `PressableCardStyle`, `RadioChoice`, and system typography.

## Battery spot (automatic)

The scan picks the battery spot by itself; nobody places it. `PlacementSceneController.updateBatterySuggestion()` runs in the background from the meter lock (once the meter wall hit and the ground are known). It recomputes at most once a second while the Live Survey runs, and only when the mesh sample count moved by 2% or more, a meter, panel, or gas mark changed, or a look-around flag changed. Scoring runs on a `Sendable` snapshot copy in `Task.detached`; stale results are dropped. Nothing is drawn until `finalizeBatterySuggestion()` at the finish.

- **Candidates:** along the snapped meter wall, cabinet centre at ±0.9, 1.4, 1.8, 2.7, and 3.6 m from the meter (10 spots), facing out.
- **Rejected, "wall ends":** fewer than 60% of the 10 cm along-wall bins across the cabinet width (0.1–1.5 m above the ground) hold a vertical face within 0.15 m of the meter plane. An unscanned stretch is "pending" during the scan and "not scanned" at the finish.
- **Rejected, "something between it and the meter":** 4 or more occupying faces in the corridor from the meter's edge to the pad's near edge (0.05–0.9 m out, 0.1–2.0 m high), not counting floor, ceiling, or faces on the meter plane (±0.15 m).
- **Rejected, "gas":** the pad centre is within 3.25 ft of the gas mark, horizontally.
- **Scored:** the rest go through `CorePlacementMeasurer.measure` with the battery set. Any pad-rule conflict rejects the spot. The winner has the fewest unknowns, then the smallest offset from the meter.
- **Finish:** with a winner, the rig is placed there, `batteryConfirmed` is set, and `placement.batterySpot.status` is `placed`. With none, the status is `noMeter`, `noWall`, or `allRejected`, nothing is placed, and the battery checks stay unknown. `resuggestBattery()` drops a finalized battery back to the background and recomputes; it runs when a meter lock is cleared or a gas mark is removed.

## When each check is measured

| Check | Measured when | Final at |
|---|---|---|
| `meter-height` | At the meter lock (floor median under the meter, then the plane raycast). Refined at the panel lock and at the end of the look-around if the floor median moved more than 2 cm with 20 or more floor samples | finish |
| `meter-panel-same-wall` | At the panel lock, from snapped wall normals | finish |
| `front-working-space` | From the meter lock. The working-space slab comes from the meter wall with no battery (the entity is never drawn). Recomputed on each emit | finish |
| `transfer-switch-space` | From the meter lock. Independent of the battery | finish |
| `planning-footprint`, `wall-distance`, `not-in-front-of-window`, `meter-panel-access`, `meter-distance` | Per candidate, in the background, during the look-around | chosen at finish |
| `gas-meter-clearance` | Per candidate once the gas mark exists | chosen at finish |

The view commits the scene at the meter lock and the panel lock, so the height and same-wall results are saved even if the scan is left early. Guards against false reds: a lock's normal snaps to the median of wall faces 0–0.35 m behind it; same-wall also passes when 60% of the wall bins between the two locks lie on the meter plane; the working space ignores the meter enclosure and slides up to 15 cm; the transfer-switch box starts at the enclosure edge (`meterHalfWidthMeters`, default 0.23 m); wall distance needs 3 or more faces on the plane behind the pad; a window check with no host wall from the mesh is unknown; a blocked footprint needs 4 or more samples spanning 10 cm of height.

## Gas step: "Show the gas meter"

Runs after `readBreaker` and before the look-around. Home Info "No" skips it (`gasStepOutcome = answeredNo`). There is no ring, no dot, and no tap.

- The top line is "Show the gas meter" after Yes, otherwise "Show the gas meter, if there is one".
- The controller samples the median depth point in the centre 15% of the view (9 × 9 grid, at least 60% medium or high confidence). It marks the gas meter when, all at once: 2 s have passed since the step began; the camera moved 0.75 m or the aim point moved 0.75 m from the first one; the range is 0.3–2.5 m; the point is 0.10–1.5 m above the ground (the ground itself never counts); it is more than 0.6 m from the meter and panel; it is within 1.0 m of a vertical plane; and the view held steady for 1.5 s (0.12 m drift, under 10°/s).
- Then: a medium haptic, `gasMarkSource = shownOnScan`, a 50% centre crop saved as `gas.jpg`, a frame-log lock frame, and a new battery suggestion. The bottom line flashes "Gas meter saved".
- Hints, by priority: "Hold still" when every gate holds, "Not the electric meter", "Point your phone down" (above 1.5 m), "Back up a little" (closer than 0.3 m), "Get closer" (beyond 2.5 m), else "Point your phone at it". After 10 s with no hint, "Gas meters sit low, where a pipe comes out of the ground" (Yes) or "None here? It moves on by itself".
- Timeout: `gasStepOutcome = timedOut`, flash "Not found. Review lists it" (Yes) or "No gas meter shown. Review asks". A timeout never sets `gasMeterNotPresent`; Review keeps its "Gas meter outside?" question.
- **Attested, not measured.** The scan does not recognize gas meters, so a shown mark passes `gas-meter-clearance` at 3 ft or more as an attested pass (teal): "Measured X ft from the pad to the spot you showed as the gas meter. The scan did not recognize it; check the gas photo." Under 3 ft is a conflict. No mark and no "No" answer is unknown. `recognized` is reserved for a detector that knows gas meters. Review's "Not the gas meter" (`rejectGasMark()`) clears the mark and `gas.jpg`, sets `rejectedInReview`, and re-suggests the battery.

## OCR rules

`ScanTextParser` (`CaptureQuality.swift`) and `ElectricalLabelParser` share one set of rules (ported from the 26 Sep OCR analysis; 41 real-photo cases in `BaseARTests`).

- **Clean-up:** Cyrillic and Greek look-alikes are folded to Latin before any word test; lines below 0.3 confidence are dropped; observations are grouped into printed rows.
- **Vetoes:** an amp number on a row that says stab, bus, max or maximum, min, rated, lugs, MLO, SCCR, kAIC, AWG, torque, volts, Hz, phase, load center, panelboard, catalog, model, type, total, branch, tandem, feeder, and similar words is never the main breaker. "Main lugs", "MLO", "main bus", and "non-main" mean there is no main breaker. `MAIN` must be a whole word ("maintain" does not match). Two or more label words (AWG, torque, install, codes, warning, listed, catalog, copper, wire, …) put the crop in **label mode**: a printed label, not a breaker face.
- **Paths:** (A) `MAIN` and one rating on the same row; (B) the rating alone directly above or below `MAIN`; (C) the largest handle print, which is off (`largestHandleEnabled = false`), so amps come only from beside MAIN. A and B accept 100, 125, 150, 175, 200, or 225 A. Two different MAIN values give nothing. `ElectricalLabelParser` uses A and B only.
- **Capture:** a panel read is `main:<amps>` or plain `panel` (label mode, 3 or more branch numerals, or panel words, and not a disconnect box). `main:` needs 2 identical reads from distinct frames at least 0.4 s apart within 4 s, by the same path (3 for path C). `panel` needs 3 agreeing reads and no pending `main:`; it locks the panel and keeps its photo with **no amps** ("The scan saw the panel but no main-breaker number. Type it from the big breaker at the top."). A different MAIN value in the window blocks capture until it ages out. The basis is saved as `electrical.mainBreakerAmperageBasis` and shown in Review ("read from the MAIN label", "read beside MAIN", or "read from the largest breaker", plus "Read by scan — check it"). After 2 empty panel reads the hint is "Step back so the whole panel fits" in label mode, otherwise "Open the panel door, not the cover".
- **Meter number:** look-alikes folded; the serial label accepts "sertal"; kWh, FCC, and model lines are skipped; runs of one repeated digit are rejected.

## Panel photo

OCR reads tight crops; the photo is made separately from the same copied frame. With a real panel box at least 3% from every edge and covering 10–70% of the frame, the photo is the box padded 20%; otherwise it is the full upright frame. It must pass the same sharpness and exposure checks, with the camera at most 45° off the panel. The panel locks only once that whole-panel photo exists (the padded box inside the frame edges, 10–70% of the frame, camera at least 0.5 m away; or the full frame from at least 0.7 m). Until then `ScanFeedback.widePanelPhotoPending` is set before the lock and the bottom line says what is missing ("Step back so the whole panel fits", "Point at the panel", "Turn so the label faces you", too dark, "Hold still"). A close-up of an inside label is never saved as `panel.jpg`, and no `photoOnly` capture is produced.

## Frame recorder (Debug only)

`BaseAR/Placement/FrameRecorder.swift` saves downsized upright JPEGs plus JSON (pose, intrinsics, detections, gate readings, the decision) under `Documents/FrameLog/<date>-<survey>/`, for detector tuning and retraining. Its file header lists the call sites.

- Compiled out of Release. **Off by default**, even in Debug: `FrameRecorder.isEnabled` reads the `FrameRecorderEnabled` default, `?? false`.
- Turn it on in Review's Debug-only "Test tools" card ("Save test frames on this phone"). It starts the next time the Live Survey opens.
- Files access is Debug only. The Debug configuration uses `BaseAR/Info-Debug.plist` (main's `Info.plist` plus `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`); Release uses `BaseAR/Info.plist`, which has neither. Frames are then in Files › On My iPhone › Base Site Survey › FrameLog. Check: `plutil -extract UIFileSharingEnabled raw <app>/Info.plist` prints true for Debug and fails for Release.
- Frames can show a house, a street, and people. Treat an exported FrameLog like any site photo.

## survey.json (schemaVersion 8)

New optional fields; older files still decode.

- `placement.gasMeterMarkSource`: `shownOnScan` (or `recognized`, reserved). Nil with no mark.
- `placement.gasStepOutcome`: `shown`, `timedOut`, `answeredNo`, or `rejectedInReview`. Nil when the step never ran.
- `placement.batterySpot`: `status` (`placed`, `noMeter`, `noWall`, `allRejected`), `source` (`autoSuggested`), `alongWallFeet` (positive toward the panel), `towardPanel`, `candidatesTried`, `rejections`.
- `electrical.gasMeterPhotoFilename`: `gas.jpg`, which is also in the export zip.
- `electrical.mainBreakerAmperageBasis`: `mainRow`, `mainNeighbor`, or `largestHandle`.

`SurveyStore.checkpointScan()` runs at the finish and on the left-edge exit. It writes `scene.ply` through the existing `writePointCloud()`, finalizes the keyframes (idempotent) so an unfinished run keeps `capture/frames.json`, and writes `survey.json`. Share does not overwrite `scene.ply` when there is no exportable mesh or when the live battery is more than 5 cm from `placement.batteryPosition`. It only calls Nikita's functions and changes no format; **it is awaiting Nikita's review.**

## Ownership

- **Nikita owns the point cloud.** Do not change `BaseAR/Placement/KeyframeRecorder.swift`, `BaseAR/Review/SurveyExporting.swift`, `tools/viewer/**`, or the `scene.ply` format, or these functions: `pointCloudPLYData`, `classifiedMeshes`, `classifiedMesh`, `MeshColorCache`, `upsertMesh(from:)`, `hasExportableMesh`, and all of `MeasurementOverlay`. Keep every keyframe hook (`keyframes.consider(frame)`, `keyframes.captureNext()`, `updateKeyframeGate()`), `scanning: true` on the scan screen, and the camera.fill photo badge. Do not rename, remove, or change the signatures of the snapshot fields and `CorePlacementMeasurer` methods that `MeasurementOverlay` calls (`measure`, `wallClearance`, `transferSwitchBox`, `transferSwitchOnLeft`); adding fields is fine. Before a merge, run `scratchpad/tools/pointcloud-guard.sh <repo> HEAD` from the session scratchpad; it compares against `origin/main` and must print `POINT-CLOUD GUARD: PASS`.
- **Firus owns `BaseAR/Grid/**` and `BatteryCountDecisionCard`.** Keep the card everywhere it appears (Home Info and Review).

## Parallel work

Keep a small shared data model and clear interfaces so three people can work independently. `SurveyStore` is the composition root. The workstreams meet at:

- **Electrical capture / OCR**: `MeterNumberRecognizing`, `VisionElectricalRecognizer`, `LiveLabelScanner`. Meter number and main-breaker amperage are distinct fields.
- **AR placement and measurements**: `PlacementARView` (the SwiftUI view and its step machine), `PlacementSceneController` (detection, locks, capture), and `PlacementMeasuring`.
- **Rules / review export**: `EligibilityRule`, `BaseRuleSet`, `SurveyEvaluating`, `SurveyExporting`, `ReviewView`.

## Rules and placement color

`EligibilityRule` checks return **pass, conflict, or unknown**. Implement only checks supported by captured evidence. `BaseRuleSet` has 12 required rules, all configurable constants (Austin guidance):

1. `austin-main-breaker`: main breaker 150–200 A.
2. `solar-or-two-batteries`: solar or two batteries need a 200 A panel. Decided only from the panel bus rating read off the panel label. **Never infer the panel bus rating from the main breaker.**
3. `planning-footprint`: the 3 ft × 3 ft pad is clear.
4. `meter-distance`: within 20 ft of the meter.
5. `wall-distance`: within 1 ft of the wall.
6. `not-in-front-of-window`: not in front of a window.
7. `meter-panel-access`: the battery stays out of the 30 × 36 in working space in front of the meter and the panel.
8. `gas-meter-clearance`: at least 3 ft from a gas meter. "No gas meter" is an attested pass. A gas meter shown on the scan is also attested at 3 ft or more (the scan did not recognize it); under 3 ft is a conflict.
9. `transfer-switch-space`: a 13 in wide, about 3 ft tall space beside the meter with 30 in out from the wall.
10. `meter-height`: meter 3–6 ft off the ground. Base publishes only the 6 ft maximum; the 3 ft minimum is an app choice the team has not settled.
11. `front-working-space`: about 30 × 36 in clear in front of the equipment.
12. `meter-panel-same-wall`: meter and panel on the same wall.

The placement preview is **green** only when every required check has measured evidence and passes. **Teal (attested)** means every check passed but at least one pass rests on the user's statement. **Amber** means unknown. **Red** means an observed conflict. The battery the scan shows at its finish is tinted from the same full assessment, so the camera is never greener than Review. Rules 1 and 2 always rest on the user's reading of a label (or their solar and battery answers), so today a complete survey reaches **teal at best**; green needs a measured breaker and panel rating, which the app does not produce. That is deliberate honesty, not a bug: do not mark either rule measured to get green. Whether the electrical rules should count toward the siting color is an open team call.

## Evidence honesty

- Measured means the phone observed it: AR locks, LiDAR mesh, distances.
- **User statements are attested, not measured.** Typed answers, the panel bus rating typed from a label, "No gas meter", a gas meter the user showed on the scan, and pad or transfer-switch attestations. Never count them as measurements.
- **Numbers read by scan (OCR) are suggestions.** Label them "read by scan" and have the user confirm them in Review. Never show a scanned number as confirmed. A panel the scan saw without a MAIN rating keeps no amps; never fill it from a stab, bus, or label number.
- Unknown stays unknown. Never fill a check from a guess or a nearby number.
- Output says "ready for Base review" at most, never "approved".

## Detector

`BaseAR/Placement/EquipmentScan.mlpackage` is YOLO26s (class 0 electric meter, class 1 breaker panel), run through Vision at up to 4 Hz, letterboxed (`scaleFit`, padding undone on the raw boxes); boxes draw at 0.40. It is **assistive**: it proposes boxes, and a lock also needs the box to land on a real wall or LiDAR depth patch, a streak of agreeing samples, 0.3 m from the other lock, and a plausible height above the ground. Capture is gated by Vision OCR: the same meter number or MAIN rating read twice, or, for a panel with no readable MAIN rating, three agreeing "panel" reads that lock it with no amps (see OCR rules). The meter has no detector-only fallback (owner rule, 27 Sep): no number read twice, no lock. The panel may also be identified by its detector box held at the lock score for 8 passing checks in a row (about 2 s), but it still locks only with the whole-panel photo. The detector runs only while a meter or panel is still unlocked. Scores use `VNRecognizedObjectObservation.confidence`; the draw and lock thresholds are provisional. The model was trained on Commons and Openverse photos plus one demo wall: the panel class may rarely fire elsewhere, and AC units can score as meters. It needs retraining on phone-captured frames from at least 3 houses. Training steps are in `README.md`: `scripts/` is the pipeline that trained the shipped model; `scripts/photoset/` is the separate 3-class open-photo pipeline.

## Base intake vs this app

Researched 26 September 2026. Full comparison: `reports/Base battery form vs app.md` (historical; it still mentions a breaker photo).

Base splits a battery request into two steps. [Get Started](https://www.basepowercompany.com/get-started) is a zip-gated join form. After signup, engineers judge the site from a separate photo kit. This app is a local stand-in for that photo-and-siting step, plus the Austin checks above. It writes `survey.json` on the phone and submits nothing to Base.

**Home form.** Record the typed answers Base asks before photos, plus the electrical numbers engineers need. Skip marketing SMS, "how did you hear about us," ESIID, and utility-account fields. Base's product filters stay on the survey for a person to read: renters are waitlisted, and an existing whole-home standby generator or third-party whole-home battery is treated as incompatible. They are not rules.

**Photos.** Base's kit is nine compositions: meter with a legible number, the meter area from at least 10 steps back, right, left, the adjacent wall, behind the fence, the breaker box, the main disconnect with amperage visible, and the area around the breaker box. The Live Survey captures the meter and panel photos by itself. The wide shots are next.

**AR owns height and spacing.** Meter height (6 ft), working space in front of the meter and panel (about 30 × 36 in), and whether the meter and panel share a wall are placement measurements; keep them off the home form. Footprint clearance and transfer-switch space are measured from the LiDAR mesh when enough of the area was seen (at least 60% of the cells). Without LiDAR, or with too little coverage, they stay unknown, and the footprint also needs a suggested battery spot.

Official references:

- https://www.basepowercompany.com/specs/core
- https://help.basepowercompany.com/en/articles/10280705
- https://help.basepowercompany.com/en/articles/10280641

## Layout

- `BaseAR/Survey`: `SurveySession`, `SurveyStore`, `ToneStyle`
- `BaseAR/Onboarding`: first-launch Home Info wizard
- `BaseAR/Electrical`: meter-number scan, OCR, typed numbers
- `BaseAR/Placement`: Live Survey view, scene controller, detector, capture gate and OCR (`CaptureQuality`), battery geometry, measurements, keyframes, the Debug frame recorder
- `BaseAR/Rules`: `EligibilityRule`, `BaseRuleSet`, `SurveyEvaluating`
- `BaseAR/Review`: review screen, zipped export (survey.json, photos, scene.ply, scan capture), optional Jev advisory
- `BaseAR/Location`: one-shot property location, address suggestions
- `BaseAR/Grid`: ERCOT load-zone context and the one-versus-two Core decision card. Does not affect placement color; `gridContext` may appear in `survey.json`.
- `BaseAR/Info.plist` (Release) and `BaseAR/Info-Debug.plist` (Debug: Files sharing on)
- `scripts/` and `dataset/`: detector training tooling and the committed photo attribution list (images stay out of git; see `README.md`)
- `docs/context`: 26 Sep context pack (start with its `README.md`); `docs/site-survey-research`: research snapshot, not implemented rules

## Signing and keys

Signing comes only from `Config/BaseAR.xcconfig`, which includes the gitignored `Config/Local.xcconfig` (`DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`, optional `TYPESAFE_API_KEY`). Create it with `./scripts/bootstrap-signing.sh` or from `Config/Local.xcconfig.example`. Never put a team ID in `project.pbxproj`. Never commit a key, and never read or commit `.secrets`.

## Branch and agent rules

- `main` is protected. Never push to it directly.
- One task per branch, cut from a fresh `main`: `claude/*`, `cursor/*`, or `logan/*`.
- One owner at a time for `PlacementARView.swift` and `project.pbxproj`. Say in the team chat before you start and when you are done.
- Rebase onto `main`, and resolve conflicts hunk by hunk. Never take a whole side of a file ("ours" or "theirs").
- A PR merges only with a pasted `BUILD SUCCEEDED` from:
  ```sh
  xcodebuild -project BaseAR.xcodeproj -scheme BaseAR -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
  ```
- The project lists every file explicitly. A new Swift file needs 4 pbxproj entries (PBXBuildFile, PBXFileReference, group child, Sources). Use your own 24-hex ID prefix, grep that it is unused, and run `plutil -lint`. In use on `main`: A1–AC, B1, B2, B7, C1, C2, D2, D7, E1, E2, E7, F1 (including F1C0), F2, F7, F8, F9, FA, FB, FC, FD.
- A branch that touches `Placement/`, `Review/`, or `Survey/` must pass the point-cloud guard (see Ownership) before it merges.
- Never install on a phone from uncommitted patches. Commit (or check out a branch) first, so what is on the phone matches a commit.
- Device Hub or iPhone screen mirroring is not a camera problem. A black camera with the "can't see anything" hint means the back lens is covered or sees nothing.
- Don't commit agent logs or session notes at the repo root.

See `README.md` for device setup, what runs, and what is still stubbed.
