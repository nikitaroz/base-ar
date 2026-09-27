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
- **Exception: optional TypeSafe Jev advisory.** When `TYPESAFE_API_KEY` is set, Review shows a collapsed "Jev advisory" card that can `POST https://api.typesafe.ai/v1/systemone` for readiness guidance. It is advisory only: it never changes a rule outcome, the placement tone, its color, or `survey.json`. No key means no card and no network call. Errors and timeouts show "Advisory unavailable". It sends check results and home answers only, never name, contact, address, location, meter number, or photos. Code: `BaseAR/Review/TypeSafeJev*.swift`.
- On-device equipment detection is allowed as a capture aid, never as a verdict (see Detector below).
- Do not add ERCOT data, satellite imagery, a Base integration, or production-grade permitting logic unless a later task explicitly asks for it.
- GPS is the phone's property fix (latitude, longitude, timestamp, reported horizontal accuracy) when location permission is granted. Do not describe it as the precise battery position.
- Don't delete main features. Dead code stays unless a task removes it on purpose.

## Flow

Splash → Welcome ("Start survey") → three steps. Every main feature stays reachable from one of them.

1. **Home Info.** First launch shows the onboarding wizard, then the full form: name, email, phone, address (MapKit suggestions), own or rent, solar, portable generator, whole-home standby generator, existing whole-home battery, planned battery count (1 or 2), the panel bus rating when solar or two batteries apply, and **"Gas meter outside: Yes / No / Not sure"**. Choices are `RadioChoice` radio buttons. The property location fix is shown on a map with its accuracy circle. Next is always enabled; anything missing shows up in Review.
2. **Live Survey.** The AR camera, kept minimal:
   - **No top bar.** No Done, no title, no ••• menu. Leave by swiping right from the left edge (VoiceOver's escape gesture also leaves). Leaving commits the scan so far.
   - **Exactly two lines of text.** One **top** line is the current task and changes as each job completes. One **bottom** line is the live feedback, with a `CoachTip` motion graphic (an animated SF Symbol). Both hide while ARKit's coaching overlay is up.
   - **No tapping or clicking to mark anything.** No buttons on the camera. The lines give instructions only. The app captures by itself when recognition is reliable and the image is good: a detector box on the target (or, with no box, the label found by OCR in the middle of the screen) that lands on a real wall or depth patch and passes the lock guards, a steady, sharp, well-exposed frame for 3 evaluations in a row, and the same label value (the meter number, or the rating beside MAIN) read twice. The meter and panel lock only through this capture gate (`PlacementSceneController.evaluateCapture`); the older detector-streak and center-dot hold locks are kept in the code but off. The gas meter is marked by holding the ring on it (about 1 s; 2 s on the ground by a wall), never by a tap.
   - **No raw feet on the camera.** Distances appear only in Review.
   - Order: meter (and its number), panel (and the main breaker size when its label reads), gas, look-around, battery. Anything the scan cannot capture shows up in Review, which has the typed and retake paths. The Home Info gas answer decides the gas step: **No** skips it and records the homeowner's statement (attested, not measured); **Yes** or **Not sure** keeps it. A gas meter marked on the scan wins over the answer.
   - The battery is **auto-accepted**: the app suggests a spot beside the meter wall, clear of the transfer-switch space and the gas meter, and accepts it by itself, tinted with the live tone.
   - **Auto-finish.** When the last job completes, the scan saves its screenshot and opens Review.
   - **No dead ends.** Every step ends by itself. A meter or panel that never captures moves on after 60 s (10 s with the detector down), unmarked, so its checks stay unknown and Review lists it; the next visit looks again. The gas step moves on unmarked after 25 s (45 s after "Yes"), the look-around after 40 s, and the battery step saves without a battery when no spot appears. The grace times are `static let`s at the top of `PlacementARView`.
   - If tracking stays initializing or lacks detail, the bottom line says the camera can't see anything and to point the back camera at the wall.
3. **Review & Export.** "What's missing" rows lead to the step or screen that fixes each item (Home Info, the Live Survey, or the Electrical screen for a retake or a typed number). Then property, electrical, site-measurement, and eligibility-check details; confirm numbers read by scan; the optional Jev card; the `survey.json` preview; Share (`survey.json`, photos, `scene.ply`); Start over.

Visual theme everywhere except the camera: main's `ToneStyle`, `BrandMark`, `PressableCardStyle`, `RadioChoice`, and system typography.

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
8. `gas-meter-clearance`: at least 3 ft from a gas meter. "No gas meter" is an attested pass.
9. `transfer-switch-space`: a 13 in wide, about 3 ft tall space beside the meter with 30 in out from the wall.
10. `meter-height`: meter 3–6 ft off the ground. Base publishes only the 6 ft maximum; the 3 ft minimum is an app choice the team has not settled.
11. `front-working-space`: about 30 × 36 in clear in front of the equipment.
12. `meter-panel-same-wall`: meter and panel on the same wall.

The placement preview is **green** only when every required check has measured evidence and passes. **Teal (attested)** means every check passed but at least one pass rests on the user's statement. **Amber** means unknown. **Red** means an observed conflict. The live battery tint uses the same full assessment, so the camera is never greener than Review.

## Evidence honesty

- Measured means the phone observed it: AR locks, LiDAR mesh, distances.
- **User statements are attested, not measured.** Typed answers, the panel bus rating typed from a label, "No gas meter", and pad or transfer-switch attestations. Never count them as measurements.
- **Numbers read by scan (OCR) are suggestions.** Label them "read by scan" and have the user confirm them in Review. Never show a scanned number as confirmed.
- Unknown stays unknown. Never fill a check from a guess or a nearby number.
- Output says "ready for Base review" at most, never "approved".

## Detector

`BaseAR/Placement/EquipmentScan.mlpackage` is YOLO26n (class 0 electric meter, class 1 breaker panel), run through Vision at up to 4 Hz. It is **assistive**: it proposes boxes, and a lock also needs the box to land on a real wall or LiDAR depth patch, a streak of agreeing samples, 0.3 m from the other lock, and a plausible height above the ground. Number capture is gated by Vision OCR. Scores use `VNRecognizedObjectObservation.confidence`; the draw and lock thresholds are provisional. The model was trained mostly on Commons photos and one demo wall: the panel class rarely fires elsewhere, and AC units can score as meters. It needs retraining on phone-captured frames from at least 3 houses. Training steps are in `README.md`.

## Base intake vs this app

Researched 26 September 2026. Full comparison: `reports/Base battery form vs app.md` (historical; it still mentions a breaker photo).

Base splits a battery request into two steps. [Get Started](https://www.basepowercompany.com/get-started) is a zip-gated join form. After signup, engineers judge the site from a separate photo kit. This app is a local stand-in for that photo-and-siting step, plus the Austin checks above. It writes `survey.json` on the phone and submits nothing to Base.

**Home form.** Record the typed answers Base asks before photos, plus the electrical numbers engineers need. Skip marketing SMS, "how did you hear about us," ESIID, and utility-account fields. Base's product filters stay on the survey for a person to read: renters are waitlisted, and an existing whole-home standby generator or third-party whole-home battery is treated as incompatible. They are not rules.

**Photos.** Base's kit is nine compositions: meter with a legible number, the meter area from at least 10 steps back, right, left, the adjacent wall, behind the fence, the breaker box, the main disconnect with amperage visible, and the area around the breaker box. The Live Survey captures the meter and panel photos by itself. The wide shots are next.

**AR owns height and spacing.** Meter height (6 ft), working space in front of the meter and panel (about 30 × 36 in), and whether the meter and panel share a wall are placement measurements; keep them off the home form. Footprint clearance and transfer-switch space are measured from the LiDAR mesh when enough of the area was seen (at least 60% of the cells). Without LiDAR, or with too little coverage, they stay unknown, and the footprint also needs a placed battery.

Official references:

- https://www.basepowercompany.com/specs/core
- https://help.basepowercompany.com/en/articles/10280705
- https://help.basepowercompany.com/en/articles/10280641

## Layout

- `BaseAR/Survey`: `SurveySession`, `SurveyStore`, `ToneStyle`
- `BaseAR/Onboarding`: first-launch Home Info wizard
- `BaseAR/Electrical`: meter-number scan, OCR, typed numbers
- `BaseAR/Placement`: Live Survey view, scene controller, detector, battery geometry, measurements
- `BaseAR/Rules`: `EligibilityRule`, `BaseRuleSet`, `SurveyEvaluating`
- `BaseAR/Review`: review screen, zipped export (survey.json, photos, scene.ply, scan capture), optional Jev advisory
- `BaseAR/Location`: one-shot property location, address suggestions
- `BaseAR/Grid`: ERCOT load-zone context and the one-versus-two Core decision card. Does not affect placement color; `gridContext` may appear in `survey.json`.
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
- The project lists every file explicitly. A new Swift file needs 4 pbxproj entries (PBXBuildFile, PBXFileReference, group child, Sources). Use your own 24-hex ID prefix, grep that it is unused, and run `plutil -lint`. In use on `main`: A1–AC, B1, B2, B7, C1, C2, D2, D7, E1, E2, E7, F9, FA.
- Never install on a phone from uncommitted patches. Commit (or check out a branch) first, so what is on the phone matches a commit.
- Device Hub or iPhone screen mirroring is not a camera problem. A black camera with the "can't see anything" hint means the back lens is covered or sees nothing.
- Don't commit agent logs or session notes at the repo root.

See `README.md` for device setup, what runs, and what is still stubbed.
