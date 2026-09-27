# Repo status, 26 September 2026

As of `origin/main` at **`be3346c`** (committed 2026-09-26 19:33:45 -0500). Branch tips and PRs were fetched and checked at about 19:55 -0500 the same evening. The PR #12 branch moved to `ee94701` (19:49:36 -0500) while this check was running. The numbers below are for that commit.

Source: [`sources/repo-review-2026-09-26.md`](sources/repo-review-2026-09-26.md), a review snapshot taken at `a4c1bb6`. Every finding in it was checked again against the refs named here. Line numbers are for `origin/main` unless a ref is named (`ref:path:line`).

---

## 1. Status at a glance

| Question | Answer |
| --- | --- |
| Does `main` build? | **Yes.** Unsigned `generic/platform=iOS` build SUCCEEDED. It has 3 Vision `Sendable` warnings, all in the unused `BaseAR/Electrical/VisionMeterNumberRecognizer.swift:3,29`. |
| Does `logan/realtime-simple-ux` (`11f99c9`) build? | **No.** BUILD FAILED. A full-module typecheck finds 14 errors in 4 files. See section 4. |
| Does the PR #12 branch `cursor/logan-ux-simplify-5b1d` (`ee94701`) build? | **Yes, as of `ee94701`.** That commit fixed the TypeSafe Jev compile errors, the duplicate `setSelectedBatteryModel`, and the `upsertMesh` signature. |
| Can a survey be completed end to end on `main`? | **Only as a draft.** You can fill in Home and Electrical, run the AR scan (panel, then meter, then gas, then look around, then Submit), take the screenshot, open Review, and share `survey.json`, the photos, and `scene.ply`. The battery can never be placed, so: the preview can never turn green; 6 required checks always stay unknown (footprint, meter distance, wall distance, window, meter/panel access, working space), and gas distance does too unless the user taps "No gas meter"; the Site measurements tile never completes (`ContentView.swift:327-334`); and Review always lists "AR placement of the battery" as missing (`Rules/SurveyEvaluating.swift:83-84`). |
| Can one be completed on the PR #12 branch? | **No.** It builds, but the battery preview and auto-placement were deliberately removed, and Save stops at "Place the battery preview before saving." (`ee94701:BaseAR/Placement/PlacementARView.swift:1070`). |

**Top 3 blockers**

1. **Battery placement is unreachable on `main` and on every Step 2 branch.** On `main` the code exists but nothing calls it (P0-1). This is on purpose in the current scan-only screen (the comment at `PlacementARView.swift:41` says "This screen does not walk these steps"; `README.md:72, 75`). But it contradicts the `AGENTS.md` flow (tap to place, move, and rotate the battery, with a visible 3 ft footprint), and without it green cannot happen. On the branches the battery preview and auto-placement are stubbed out.
2. **Some evidence on `main` is weaker than its label says.** "No gas meter" counts as a measured pass (P0-2). The 200A panel rule decides from the main-breaker rating (P0-3). An OCR read fills the meter number with no confirm step (P0-4).
3. **No branch can simply be merged.** `main` and the branches differ by about 2,100 to 2,180 lines in `PlacementARView.swift` alone (2,177 for `ee94701`), and merging into `main` conflicts in 8 files. The branches also add an external API (TypeSafe Jev) and stricter rules that can never pass, so green is impossible there by design (section 5).

---

## 2. Step 2 (live AR) status on `main` `be3346c`

| Requirement | Status | Evidence |
| --- | --- | --- |
| Ground and wall plane detection | Done | `Placement/PlacementARView.swift:608` |
| LiDAR mesh with classification, guarded by device support | Done | `PlacementARView.swift:610-617` |
| Works without LiDAR | Partial. Plane raycasts still work, but the footprint, window, working-space, and transfer-switch checks stay unknown. | `Placement/PlacementMeasuring.swift:275, 340, 407, 457` |
| Place, move, and rotate the battery, with a visible 3 ft footprint | **Missing on screen.** The code exists but nothing calls it. | The tap handler ignores the battery (`PlacementARView.swift:815-816`) and `commitAim` refuses it (`:1217`). `syncGuide`, `confirmBatterySpot`, and `flipBatterySide` (`:1972-2001`) have no callers. `walkStep` is set to `.scan` at start and in `hideWorldBoxesIfNeeded` (`:511`, `:1160`), and to anything else only inside `syncGuide` (`:1973`), so the suggestion in `tickAim` (`:1270`) never runs. `batteryPosition` is written only after confirmation (`:2212-2221`). |
| Placement colour on the AR screen | None in practice. `tone: .incomplete` (amber) is hard-coded, and the tone only tints the battery and pad, which are never drawn. | `PlacementARView.swift:184, 913-923` |
| Meter and panel marks | Measured: the detector locks after 5 hits within about 15 cm | `PlacementARView.swift:367-392, 1790` |
| Within 20 ft of the meter | Code is there, but it needs a battery | `PlacementMeasuring.swift:192` |
| Within 1 ft of the wall | Code is there, but it needs a battery | `PlacementMeasuring.swift:262` |
| At least 3 ft from a gas meter | The distance needs a battery. "No gas meter" returns a **measured** `.pass`. | `Rules/BaseRuleSet.swift:171-172` |
| Meter height of 6 ft or less | Measured from the meter lock. The ground under the meter can come from an estimated plane. The rule also enforces a 3 ft minimum that Base's requirements page does not list (section 5). | `PlacementARView.swift:2082`; `BaseRuleSet.swift:14, 194` |
| Meter and panel on the same wall | Measured | `PlacementMeasuring.swift:493` |
| Transfer-switch space | Measured with LiDAR at 60% or more wall coverage. It does not need a battery. | `PlacementMeasuring.swift:443-467` |
| 30 × 36 in working space and footprint clearance | Code measures both at 60% or more coverage, but both need a battery. The working space also needs its own position. The box is 30 in wide × 36 in deep, while Base's page says "30 in high x 36 inches wide" (section 5). | `PlacementMeasuring.swift:274, 406`; `BaseRuleSet.swift:16-17` |
| Not in front of a window; meter and panel access | Code is there, but it needs a battery | `PlacementMeasuring.swift:339, 308` |
| Capture | One `arView.snapshot` on Submit, plus a PLY export. No video, on any branch. | `PlacementARView.swift:927` |
| Tracking and relocalization | Tracking-state messages only. There is no interruption handling. The world root is `AnchorEntity(world: .zero)` with no ARAnchors. | `PlacementARView.swift:648, 955` |
| GPS | Used only as the property fix, never as the battery position (OK) | `Location/PropertyLocationProvider.swift:4` |

---

## 3. Open issues on `main`

### P0: stops a valid survey or breaks the evidence rules

| ID | Issue | Where | One-line fix |
| --- | --- | --- | --- |
| P0-1 | The battery is never placed, so green is unreachable and the placement tile never completes. Deliberate in the scan-only screen (`:41`, `README.md:72, 75`), but it breaks the `AGENTS.md` flow. | `PlacementARView.swift:184, 815-816, 1160, 1217, 1972-2001` | Add a `.battery` cue after `.lookAround` that calls `store.placementController?.syncGuide(step: .battery, gasResolved: true)`, enables input, shows Confirm and Flip buttons wired to `confirmBatterySpot()` and `flipBatterySide()`, and passes `store.assessment(applying: scene).placementTone` instead of `.incomplete`. The live tone stays safe because an unconfirmed spot goes to `suggestedBatteryPosition`, not `batteryPosition` (`:2212-2221`). This restores the suggested wall-side spot and dragging it along the wall (`:835-851`, needs `inputEnabled`). Tap-to-place stays off (`:815-816`). |
| P0-2 | "No gas meter" returns `.pass`, which sets `usedMeasuredEvidence: true`, so one tap counts as a measurement. | `BaseRuleSet.swift:171-172`; `Rules/EligibilityRule.swift:19-20` | Return `RuleOutcome(status: .pass, usedMeasuredEvidence: false, …)` or `.unknown`. This is a team decision (section 5). |
| P0-3 | "Solar or two batteries needs a 200A panel" decides from the main-breaker rating: a 200A breaker passes (`:59-60`), and a smaller one is a conflict (`:64-66`). Base's page asks for a panel "rated 200A" ([Base requirements](https://help.basepowercompany.com/en/articles/10280705)), and the main breaker is not the panel rating. `main`'s `AGENTS.md` has no explicit rule on this. Only the branch copy says "Do not … infer panel bus rating from main-breaker amperage" (`ee94701:AGENTS.md:25`). | `BaseRuleSet.swift:59-66` | When there is solar or two batteries, return `.unknown` until a panel rating is captured. The branches already do this (`ee94701:BaseAR/Rules/BaseRuleSet.swift:75-78`). |
| P0-4 | The photo OCR read is written straight into `meterNumber` and counts as present, with no confirm step. Live-scan reads are saved with the default `.manual` source. | `Survey/SurveyStore.swift:174-175`; `Rules/SurveyEvaluating.swift:55-57`; `Electrical/ElectricalCaptureView.swift:210` | Keep OCR text as a suggestion until the user taps Confirm, and pass `source: .ocr` from `applyScan`. |

### P1: wrong results or misleading UI

| ID | Issue | Where | One-line fix |
| --- | --- | --- | --- |
| P1-1 | `applying()` still keeps an old `true` for transfer-switch space when the new value is nil (partly fixed in `be3346c`; see "Fixed since `a4c1bb6`"). | `PlacementMeasuring.swift:167-169` | Assign `measured.transferSwitchClearanceObserved` directly. It is always nil without a mesh anyway (`:457`), so the keep-if-unchanged pattern used for the other checks adds nothing here. |
| P1-2 | **New, not device-tested.** AR "Start over" clears the scene but not `session.placement`. If nothing is marked again, `commitLiveScene` skips the commit, and Review keeps the old meter height, same-wall, and transfer results. | `PlacementARView.swift:314-318, 333-334` | Add `SurveyStore.resetPlacement()` and call it from `restart()`. |
| P1-3 | Review shows own or rent, standby generator, and existing whole-home battery as plain values with no product-filter flag, and `survey.json` has no flag either. Only the Home form and onboarding say renters are waitlisted (`ContentView.swift:602`; `Onboarding/OnboardingPages.swift:247`). | `Review/ReviewView.swift:182, 207-208` | Add a "Base product filters" block and a flag list to `survey.json`. Keep them out of the placement colour (`AGENTS.md`). |
| P1-4 | The hub says "Your answers save as you go." That is false: `survey.json` is written only when Review opens or on Share. The README says the same thing. | `ContentView.swift:235`; `README.md:69`; writes at `ReviewView.swift:54, 312` | Write the JSON in `refreshAssessment()`, debounced, or change the copy. |
| P1-5 | Onboarding covers only name, address, own or rent, and battery count. An `@AppStorage` gate skips it on every later survey, including after Start over. | `Onboarding/OnboardingContainerView.swift:92-97`; `ContentView.swift:23, 95` | Gate onboarding per survey, or reset the flag on Start over. |
| P1-6 | There is no breaker photo field. The photo kit covers 1 of Base's 9 shots, plus the AR screenshot. | `ElectricalCaptureView.swift:5-9` | Add breaker and disconnect photo slots, or state the gap on Review. |
| P1-7 | Mesh classification runs on the main thread, because the ARSession delegate has no `delegateQueue`. The effect on frame rate is not measured. | `PlacementARView.swift:624, 968-993` | Set a serial background `delegateQueue`. The handlers already hop to `MainActor`. |

### P2: cleanup and polish

| ID | Issue | Where | One-line fix |
| --- | --- | --- | --- |
| P2-1 | The Review readiness card turns green when nothing is missing, whatever the tone. A typed amperage shows a green "Confirmed" check. | `ReviewView.swift:351-354`; `ElectricalCaptureView.swift:178-181` | Colour the card from `placementTone`, and label the amperage "Entered". |
| P2-2 | Each time Review opens, `.task` rebuilds the ASCII `scene.ply` on the main thread. | `ReviewView.swift:53-55` → `SurveyStore.swift:217-263` → `Review/SurveyExporting.swift:59-84` | Build the PLY only on Share, off the main actor. |
| P2-3 | If the user declines temporary precise location, every retry ends in "The property fix failed. Try again." A reduced-accuracy fix is usually coarser than the 500 m guard (a [third-party write-up](https://radar.com/blog/understanding-approximate-location-in-ios-14) puts it at 1 to 20 km; not checked against Apple docs). Not device-tested. | `PropertyLocationProvider.swift:48-55, 82-86` | Say "Precise location is off" and show the approximate fix, or link to Settings. |
| P2-4 | A wall hit with no plane anchor falls back to the normal `(0,0,1)`. Low risk: both callers raycast `.existingPlaneGeometry`, which should return a plane anchor. | `PlacementARView.swift:2181, 2188, 2197` | Reject the hit when `hit.anchor` is not an `ARPlaneAnchor`. |
| P2-5 | Dead code: `VisionMeterNumberRecognizer` is unused, is the source of the build warnings, and never resumes if `perform` throws (`:29`). Also unused: `UnimplementedMeterNumberRecognizer` (`MeterNumberRecognizing.swift:11`), `retryPropertyLocation` (`SurveyStore.swift:70`), `setFootprintClearAttested` and `setTransferSwitchSpaceAttested` (`:201, 206`), and `frontWorkspaceWidth/DepthInches` (`SurveySession.swift:210-211`). Not dead but duplicated: `meterAndPanelShareWall` (`SurveySession.swift:224`, comment says "Explicit homeowner observation", but it is set from geometry at `PlacementMeasuring.swift:227`) repeats `meterAndPanelSameWall`, and `SurveyEvaluating.swift:114` reads it. | as listed | Delete the unused ones. Fold `meterAndPanelShareWall` into `meterAndPanelSameWall` and update `SurveyEvaluating.swift:114`. Do not just delete it. |
| P2-6 | The camera permission string still mentions a breaker photo. | `BaseAR.xcodeproj/project.pbxproj:446, 481` | Remove "and main breaker", or add the photo (P1-6). |
| P2-7 | `DEVELOPMENT_TEAM` is hard-coded in the target settings, which override the ignored `Config/Local.xcconfig`. `be3346c` changed it from `AGWR7PG3MN` to `62JVG6DVVU`, so it now flips with each committer and adds pbxproj conflicts. | `project.pbxproj:440, 475`; `Config/BaseAR.xcconfig:2` | Delete the target-level line and let `Local.xcconfig` set it. |
| P2-8 | A `BaseARTests` stub exists despite the no-tests rule. | `BaseARTests/BaseARTests.swift` | Remove the target, or accept it as a stub. |

### Fixed since `a4c1bb6`

- **Stale footprint, window, and working-space results** (`be3346c`). With a mesh, a nil result now clears the old answer. Without a mesh, the old answer is kept only if the battery (and the working space) did not move: `PlacementMeasuring.swift:150-166`. Transfer-switch space is **not** fixed (P1-1).
- **The window rule** returns unknown until a battery is placed (`be3346c`): `BaseRuleSet.swift:135-137`.
- **The manual meter-number button** now focuses the field after it appears (`be3346c`): `ElectricalCaptureView.swift:128-134`.
- **PR #12 branch now builds** (`ee94701`, branch only): the TypeSafe Jev `try` and criteria type, the duplicate `setSelectedBatteryModel`, and the `upsertMesh(frame:)` call are fixed. Earlier commits on that branch also fixed the `onGuide` wiring the snapshot flagged. `bind()` now takes `onGuide` (`ee94701:BaseAR/Placement/PlacementARView.swift:1471`) and the controller calls it (`:2888`).
- **Not fixed** on `main` by `be3346c` or anything later: the battery wiring (P0-1), the gas-meter pass (P0-2), the panel-rating rule (P0-3), the OCR confirm (P0-4), and every other P1 and P2 finding above.

---

## 4. Branches and PRs

Ahead and behind counts are against `origin/main` `be3346c`. "Merge" is the result of `git merge-tree --write-tree`. All times are UTC, on 27 Sep unless marked 26 Sep.

| Branch | PR | Ahead / behind | Last commit | Merge into main | Build |
| --- | --- | --- | --- | --- | --- |
| `cursor/logan-ux-simplify-5b1d` | #12 → `cursor/simplify-save-sheet-4ba1` | 38 / 15 | 00:49 `ee94701` | Conflicts: pbxproj, ContentView, ElectricalCaptureView, PlacementARView, PlacementMeasuring, ReviewView, SurveyStore, README | **SUCCEEDED** |
| `logan/realtime-simple-ux` | #9 draft → `logan/test` | 28 / 15 | 00:27 `11f99c9` (squash of PR #11) | Same 8 files | **FAILED**, 14 errors (below) |
| `cursor/simplify-save-sheet-4ba1` | #11 merged into realtime-simple-ux | 32 / 15 | 00:23 `0240a89` | Same 8 files | Same tree as `11f99c9` (`6c44f27`), so it FAILS too |
| `logan/test` | #7 draft → `chore/guidance-integration` | 23 / 15 | 26 Sep 23:33 `9d03313` | Same 8 files | **FAILED** (rebuilt: `xcodebuild` reports 15 errors, incl. TypeSafe Jev, duplicate `trackingInterrupted()`, missing `selectedBatteryModelId`) |
| `chore/guidance-integration` | none | 8 / 22 | 26 Sep 21:15 `c49194e` | 9 files (no pbxproj; adds EquipmentDetecting, SurveySession) | **SUCCEEDED** (rebuilt) |
| `cursor/phone-test-stack-7460` | #6 closed, not merged | 12 / 22 | 26 Sep 21:35 | 10 files | not built; external API (TypeSafe Jev) |
| `feat/capture-observations` | none | 3 / 22 | 26 Sep 21:08 | 8 files | not built; all commits are in guidance-integration |
| `feat/guided-site-survey` | none | 2 / 22 | 26 Sep 20:58 | 7 files | ancestor of guidance-integration |
| `fix/spatial-evidence-validity` | none | 4 / 22 | 26 Sep 21:12 | 8 files | 3 of its 4 commits are in guidance-integration; the 4th (`82e8d99`) has a same-titled but different commit there (`10f9345`) |
| `cursor/fix-spatial-evidence-validity-1810` | #5 draft | 5 / 22 | 26 Sep 21:25 | 8 files | Not a copy of the branch above. It shares the same 2 base commits, then has a different fix (`3d11a49`) plus two docs |
| `cursor/typesafe-jev-realtime-e9fb` | #4 draft | 2 / 23 | 26 Sep 21:03 | pbxproj, README | not built; external API |
| `jev/openjev-eligibility` | #2 | 1 / 31 | 26 Sep 16:02 | ReviewView, SurveyStore, README | not built; external API (`api.openjev.sh`) |
| `cursor/cloud-agent-swift-check-b95d` | #10 draft | 1 / 16 | 26 Sep 22:58 | clean | adds only scripts and AGENTS.md lines |
| `cursor/gap-analysis-2c9f` | #1 draft | 1 / 31 | 26 Sep 15:49 | clean | docs only |
| `docs/site-survey-research-2026-09-26` | none | 1 / 23 | 26 Sep 20:28 | clean | docs only |

Open PRs (all by logbx): #12, #10, #9, #7, #5, #4, #2, #1. Merged since the snapshot: #11 (into `logan/realtime-simple-ux`). #8 (`feature/ux-improvements`) was merged into `main` earlier. #6 (`cursor/phone-test-stack-7460`) and #3 (`cursor/typesafe-systemone-e9fb`) were closed without merging.

**`logan/realtime-simple-ux` errors at `11f99c9`.** `xcodebuild` reported 7 of them in this run. `swiftc -typecheck -continue-building-after-errors` finds all 14:

- `Review/TypeSafeJevClient.swift:31` (unhandled `throws`) and `:99` (array literal used as `[String:String]`)
- `Placement/PlacementARView.swift:1253` duplicate `cloud`; `:1928` duplicate `pointCloudPLYData()`; `:1934` duplicate `hasExportableMesh`; `:1930` `MeasurementOverlay` not in scope; `:1831` extra `frame:` in the `upsertMesh(from:)` call; `:1865` `classifiedMeshes(from:)` missing `frame:` and `colors:`; `:3601` `MeshDrawBuffers` missing `cloud:`; `:366` ambiguous `setSelectedBatteryModel`
- `Survey/SurveyStore.swift:292` duplicate `setSelectedBatteryModel`; `:522` ambiguous `pointCloudPLYData()`
- `Review/ReviewView.swift:275` and `:361` ambiguous `hasExportableMesh`

**What the Step 2 branches (`11f99c9`, `ee94701`) still do wrong:**

- The battery body and footprint meshes are removed (`ee94701:…/PlacementARView.swift:2008`), `autoPlaceIfPossible` returns at once (`:2028-2030`), and a battery tap is ignored (`:1631-1632`).
- The view sets `walkStep` (`:356`), but `gasResolved` is never set (`:1369`), so `suggestBatterySpotIfNeeded` never runs (`:3111`). `confirmBatterySpot` and `flipBatterySide` (`:3090, 3098`) have no callers. There is no `syncGuide` on the branch.
- The footprint, working-space, and transfer checks return `blocked ? false : nil` (`ee94701:BaseAR/Placement/PlacementMeasuring.swift:277, 305, 319`), so they can never pass.
- The required `programReview` rule is always unknown (`ee94701:BaseAR/Rules/BaseRuleSet.swift:34-42`), and "No gas meter" returns unknown (`:146-147`). The breaker and "no solar" passes are marked `usedMeasuredEvidence: false` (`:61, 80`), so even without `programReview` the best tone would be attested, never green.
- The branch rule list has no window or meter/panel-access rule (`ee94701:BaseAR/Rules/BaseRuleSet.swift:18-30`; they came to `main` in `a4c1bb6`), and its `AGENTS.md` drops "Not in front of a window".
- Review always creates a `TypeSafeJevClient` (`ee94701:BaseAR/Review/ReviewView.swift:14`). When `TYPESAFE_API_KEY` is set (environment or Info.plist), it POSTs a compact survey state (flags, distances, rule results, form answers, no name or address) to `https://api.typesafe.ai/v1/systemone` (`TypeSafeJevClient.swift:7, 12-18, 49-55`). No key is hard-coded.
- Some things are better on the branches: the tone comes from the live assessment (`ee94701:…/PlacementARView.swift:388, 404`), and the panel rule no longer infers the bus rating (`ee94701:BaseAR/Rules/BaseRuleSet.swift:75-78`).

### Recommended consolidation order (recommendation only)

1. **Fix `main`'s P0-2, P0-3, and P0-4 on `main` first.** They are small and independent, and `BaseRuleSet.swift` merges without conflicts. Doing them first also means each rule change is decided on its own, instead of arriving wholesale with the port.
2. **Use `ee94701` as the consolidation tip, not `11f99c9`.** It is `0240a89` (the same tree as `11f99c9`) plus 6 commits, and it builds. PR #12 fast-forwards onto its base, `cursor/simplify-save-sheet-4ba1`. A plain merge of `ee94701` into `logan/realtime-simple-ux` conflicts in `PlacementARView.swift` and `RealtimeSurveyView.swift`, because the squash commit hides the shared history. Take `ee94701`'s tree rather than resolving those hunks by hand.
3. **On that tip, before any port to `main`:** restore the battery mesh and placement, set `gasResolved` when the step changes (the branch has no `syncGuide`; port `main`'s from `PlacementARView.swift:1972-1981`, or set it next to `walkStep` at `ee94701:…/PlacementARView.swift:356`), and wire Confirm and Flip. Replace `blocked ? false : nil` with `main`'s coverage-based pass (the `ScanIndex` code at `PlacementMeasuring.swift:274-304` and `406-467`). Settle the `programReview`, gas, and TypeSafe Jev decisions in section 5.
4. **Hand-port the result onto `main`**, keeping `main`'s onboarding (`08ea1a7`, `56e3fce`), window and access checks (`a4c1bb6`), and `be3346c`. This is a port, not a conflict resolution: about 2,180 changed lines in `PlacementARView.swift`. Keep `main`'s `AGENTS.md`: the branch copy drops the window rule and adds a TypeSafe Jev exception (`ee94701:AGENTS.md:20`). Leave the branch's root-level notes out of `main` (`COMPLETION_SUMMARY.md`, `RADICAL_SIMPLIFICATION_COMPLETE.md`, `MOBILE_UX_POLISH_BRANCH.md`, `XCODE_PROJECT_SETUP.md`, `PHONE_TEST_NOTES.md`).
5. **Docs PRs merge cleanly, but check them first.** `docs/site-survey-research-2026-09-26` marks itself as research, not implemented behaviour. #1 (`docs/GAP_ANALYSIS.md`) is 31 commits old and says OCR is stubbed. Merge it only if it is labelled historical. Merge #10 only if the team accepts a Linux script under the no-tests rule.

### Cleanup (recommendation only, do not delete without the team)

- **Close as superseded:** `logan/test` / #7 (22 of its 23 commits are rebased copies in `logan/realtime-simple-ux`), `cursor/simplify-save-sheet-4ba1` (merged through #11, identical tree), `feat/guided-site-survey` (ancestor), `feat/capture-observations` (contained).
- **Pick one of the two competing spatial-evidence fixes**: `fix/spatial-evidence-validity` (already folded into `chore/guidance-integration`) or `cursor/fix-spatial-evidence-validity-1810` (#5, a different patch). Close both if `chore/guidance-integration` is dropped.
- **Hold #4 and #2** (external APIs) and `cursor/phone-test-stack-7460` until the no-backend decision is made.
- **Retarget or close #9 and #12 after step 2 above.** Their current bases (`logan/test`, `cursor/simplify-save-sheet-4ba1`) are themselves superseded.

---

## 5. Spec and policy decisions the team must make

| Decision | Facts | Options |
| --- | --- | --- |
| **YOLO equipment detector vs `AGENTS.md`** | `AGENTS.md` says "Do not add … automatic equipment detection". `main` ships `Placement/EquipmentScan.mlpackage` and locks the meter and panel from it (`Placement/EquipmentDetecting.swift:34, 67`). The app runs it on device with Core ML and Vision. It is trained offline with ultralytics on Wikimedia Commons photos (`README.md:88-94`). | Update `AGENTS.md` to allow on-device detection as a marking aid, or go back to tap-to-mark. |
| **TypeSafe Jev and OpenJEV vs no backend** | `AGENTS.md`: "No backend, accounts, external datasets, or third-party dependencies." The branches POST survey state to `api.typesafe.ai` (#4, #7, #9, #12, phone-test-stack), and their `AGENTS.md` already adds an exception for it (`ee94701:AGENTS.md:20`). #2 calls `api.openjev.sh`. Both are advisory only and need a key. | Drop them before merging to `main`; or keep them behind a compile flag, off by default; or amend `main`'s `AGENTS.md`. |
| **Attested (teal) tone** | The spec defines green, amber, and red only. `main` has `.attested` (`Survey/SurveySession.swift:239-247`; `Rules/EligibilityRule.swift:47-49`), but its setters have no UI (P2-5), so it cannot be reached today. How P0-2 is fixed decides whether it comes back. | Drop `.attested` and treat attestations as amber, or add it to the spec. |
| **What "No gas meter" means** | `main` counts it as a measured pass (P0-2). The branches make it unknown, so a house with no gas can never be green. | Measured pass (current), attested pass, or "not applicable" excluded from the required checks. |
| **Can green ever happen?** | On `main`, only after P0-1, and only on a LiDAR phone: footprint, window, working space, and transfer stay unknown without a mesh (`PlacementMeasuring.swift:275, 340, 407, 457`). The branches add a required `programReview` rule that is always unknown, clearance checks that never return true, and non-measured breaker and solar passes (section 4). Under the spec, that means the branch preview can never be green. | Make `programReview` non-required (an advisory note), or change the spec. |
| **Does a typed answer count as measured evidence?** | On `main`, the breaker and solar rules use `.pass`, which sets `usedMeasuredEvidence: true` (`BaseRuleSet.swift:44, 60, 69`; `EligibilityRule.swift:19-20`). So a typed amperage and Yes/No answers count toward green, and a typed 100A breaker turns the placement preview red. `AGENTS.md` says "Placement color stays on measured siting checks." The branches mark these passes non-measured (`ee94701:BaseAR/Rules/BaseRuleSet.swift:61, 80`). | Report electrical rules next to the placement colour, not inside it; or accept confirmed typed values as evidence and say so in `AGENTS.md`. |
| **Working-space shape** | Base's page says "In front of the meter and main breaker box there must be a clear space of 30 in high x 36 inches wide" ([Base requirements](https://help.basepowercompany.com/en/articles/10280705), fetched 26 Sep). The app models a box 30 in wide × 36 in deep in front of the equipment (`BaseRuleSet.swift:16-17`; `PlacementMeasuring.swift:419-420, 432-433`), and `AGENTS.md` says only "about 30 × 36 in". | Ask Base which reading is right, or show the assumption on Review. |
| **Meter height minimum** | The rule enforces 3–6 ft (`BaseRuleSet.swift:14, 187`). Base's page lists only a maximum: "The meter must be installed no higher than 6 feet off the ground" ([Base requirements](https://help.basepowercompany.com/en/articles/10280705)). `AGENTS.md` and the README cite only the 6 ft maximum. The branches already dropped the minimum (`ee94701:BaseAR/Rules/BaseRuleSet.swift:14`). | Remove the minimum, or cite a source for it. |
| **Stale docs** | `AGENTS.md` lists 8 rules; `BaseRuleSet.rules` has 12 (`BaseRuleSet.swift:19-32`). `AGENTS.md` says footprint and transfer-switch space are unmeasured; `main` measures both, but the flow can't reach the footprint check. README "Next three tasks" #2 lists work that is done (`README.md:113`), and `README.md:69` repeats "saves as you go". `reports/Base battery form vs app.md` (which `AGENTS.md` calls the "Full comparison") and `research_notes/Base battery form vs app/app_inventory.md` still describe stubbed fields, a breaker photo, and nil OCR. | Refresh `AGENTS.md` and README after the port. Mark the two research files as historical. |

---

### How this was checked

- **Fetch and inspect:** `git fetch --prune origin`, then `git show`, `git diff`, `git cherry`, and `git merge-tree --write-tree` against `origin/main` and each branch tip. Code was read at `be3346c`.
- **Builds:** `xcodebuild -project BaseAR.xcodeproj -scheme BaseAR -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`, run in throwaway copies of `be3346c`, `11f99c9`, `ee94701`, `9d03313`, and `c49194e`.
- **Complete error lists:** `swiftc -typecheck -continue-building-after-errors` against the iOS SDK.
- **PR list:** `gh pr list -R nikitaroz/base-ar --state all`.
- **Base numbers:** re-read from [Base's electrical and spacing requirements](https://help.basepowercompany.com/en/articles/10280705) on 26 Sep.
- **Not verified:** nothing here was run on a device. Device-only claims (P1-2, P1-7, P2-3, P2-4) are marked as such. AR distances are preliminary estimates, not installer measurements, and nothing here is approval.
