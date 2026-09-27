# Repo review snapshot, 26 September 2026

> Findings from a three-reviewer pass (spec vs main, AR step 2, build and merge state) run from Logan's Claude Code session. Reviewed `origin/main` at `a4c1bb6`; `main` has since moved (see `docs/context/repo-status-2026-09-26.md` for what is still open). Line numbers refer to the ref named.

## Bottom line at review time
- Home form, electrical capture, and review/export mostly match `AGENTS.md`.
- Step 2 (the live AR screen) could not complete a survey anywhere:
  - `main`: the tap handler ignores the battery (`PlacementARView.swift:815` `case .battery: break`), `commitAim` refuses it (:1216), `syncGuide` / `confirmBatterySpot` / `flipBatterySide` (:1972–2000) have no callers, and the tone passed to the view is hardcoded `.incomplete` (:184). `batteryPlaced` is always false, so green is unreachable.
  - Active Cursor branches: battery and footprint meshes removed (invisible placeholder), auto-placement stubbed, battery suggestion waits on a `gasResolved` flag nothing sets, Save stops at "Place the battery preview before saving." Footprint / working-space / transfer checks return `blocked ? false : nil` so they can never pass, and a required `programReview` rule is always unknown.
- All four active branches failed to build; `main` and `chore/guidance-integration` built.

## Build health (unsigned `generic/platform=iOS` build)
| ref | pbxproj | build | notes |
| --- | --- | --- | --- |
| main | OK | SUCCEEDED | 3 Vision Sendable warnings (`VisionMeterNumberRecognizer.swift:29`) |
| chore/guidance-integration | OK | SUCCEEDED | same warnings |
| logan/test | OK | FAILED (8) | `TypeSafeJevClient.swift:31,99`; duplicate `trackingInterrupted()` / `latestObservation` (EquipmentDetecting:348,354); uses removed `selectedBatteryModelId` / `BatteryCatalog.model` |
| logan/realtime-simple-ux | OK | FAILED (7) | TypeSafeJevClient; duplicate `cloud` (PlacementARView:1253), `pointCloudPLYData()` (:1928), `hasExportableMesh` (:1934), `setSelectedBatteryModel` (SurveyStore:292) |
| cursor/simplify-save-sheet-4ba1 | OK | FAILED (6) | same duplicates as realtime-simple-ux |
| cursor/logan-ux-simplify-5b1d | OK | FAILED (4+) | duplicate `cloud` (:1130); single-element labeled tuple (:116) breaks `@State`; passes `onGuide:` to a `bind()` with no such parameter (:1108, :1349) |

The shared error is `Review/TypeSafeJevClient.swift` (unhandled throwing call at :31, array literal used as `[String:String]` at :99), brought in from the TypeSafe Jev branch.

## Branch relationships
- All four active branches fork from `b092b7e`; none contains another.
- `logan/test` is superseded: 22 of its 23 commits are rebased copies inside `logan/realtime-simple-ux`.
- `cursor/simplify-save-sheet-4ba1` converged with `logan/realtime-simple-ux` (identical trees at `6c44f27`); both independently built "meter → panel auto-lock + coach banner" (`0240a89` vs PR #11 `11f99c9`).
- `cursor/logan-ux-simplify-5b1d` (PR #12) differs by one commit (`2a6bf53`), conflicts with both, does not compile, and its view never receives guide updates, so the flow stalls after the meter lock.
- Each active branch rewrites ~1,440–1,565 lines of `PlacementARView.swift`; `main`'s `a4c1bb6` rewrote ~1,314 lines of the same file. The branches differ from `main` by ~2,100 lines there, so integration is a hand port, not a conflict resolution.
- Clean against `main`: PR #10 (cloud-agent-swift-check), PR #1 (gap-analysis), `docs/site-survey-research-2026-09-26`.
- Stale (21 behind, no PR): `chore/guidance-integration`, `feat/capture-observations`, `feat/guided-site-survey`, `cursor/phone-test-stack-7460`. Duplicate pair: `fix/spatial-evidence-validity` and `cursor/fix-spatial-evidence-validity-1810` (PR #5).
- Open PRs (all by logbx): #12, #10, #9, #7, #5, #4, #2, #1.

## AR (step 2) on main vs spec
| Requirement | Status at a4c1bb6 | Evidence |
| --- | --- | --- |
| Ground + wall plane detection | Done | PlacementARView:608 |
| LiDAR mesh, support-guarded | Done | :610–621 |
| Works without LiDAR | Partial: plane fallback, mesh checks stay unknown | PlacementMeasuring:275,407,457 |
| Place / move / rotate battery, visible 3 ft footprint | Missing on screen (code exists, uncalled) | :815, :2003 |
| Meter mark | Measured (detector lock or hold-to-lock) | :1790 |
| ≤ 20 ft to meter | Measured, needs a battery | Measuring:192 |
| ≤ 1 ft to wall | Measured (mesh, then vertical plane) | Measuring:262 |
| ≥ 3 ft from gas meter | Measured; "no gas meter" returns a measured `.pass` | BaseRuleSet:168 |
| Meter height ≤ 6 ft | Measured; ground can come from an estimated plane (:2082); unsupported 3 ft minimum | BaseRuleSet:14,191 |
| Meter and panel share a wall | Measured (normals + plane offset) | Measuring:493 |
| 30 × 36 in working space, transfer-switch space, footprint clearance | Measured at ≥ 60% coverage | Measuring:406,456,274 |
| Not in front of a window; meter/panel access | Measured (new in a4c1bb6) | Measuring:308,339 |

Other AR risks: mesh processing on the main thread (:968–993); no session interruption / relocalization handling; camera denial only surfaces through `didFailWithError` (:1007); wall locks default the normal to (0,0,1) without a plane anchor (:2203); world root is `AnchorEntity(world: .zero)` with no ARAnchors, so marks drift on relocalization; units consistent (meters internally, /0.3048). No branch records video: capture is one `arView.snapshot` plus a PLY export.

## Rules, data, and review on main
- P0 `BaseRuleSet.swift:168`: "No gas meter" is `.pass`, which sets `usedMeasuredEvidence: true` (`EligibilityRule.swift:19-20`), so one tap counts as a measurement.
- P0 `BaseRuleSet.swift:59`: "Solar or two batteries needs a 200A panel" passes from the main-breaker rating. `AGENTS.md` forbids inferring panel bus rating from main-breaker amperage.
- P0 OCR: `SurveyStore.swift:174-175` writes the OCR read into `meterNumber`; `SurveyEvaluating.swift:55-57` treats the field as satisfied with no confirm step; `ElectricalCaptureView.swift:207` saves live-scan reads with the default (manual) source.
- P1 `PlacementMeasuring.swift:151-169` `applying()` keeps an old `true` for footprint / window / working space / transfer when the new value is nil (e.g. after the battery moves).
- P1 Renter, standby generator and third-party battery answers are plain Yes/No on Review (`ReviewView.swift:182, 207-208`) and not flagged in JSON.
- P1 Hub copy "Your answers save as you go" (`ContentView.swift:235`) is false: `survey.json` is written only on Review open or share.
- P1 Onboarding covers only name, address, own/rent, battery count, and an `@AppStorage` gate hides it on every later survey, including after Start over.
- P1 No breaker photo field; photo kit coverage is 1 of Base's 9 compositions plus the AR screenshot.
- P2 Review readiness card turns green when nothing is missing even if tone is attested or unknown (`ReviewView.swift:351-354`); typed amperage shows a green "Confirmed" check.
- P2 Review `.task` rebuilds the ASCII `scene.ply` on the main thread each open (`SurveyExporting.swift:59-84`).
- P2 Declining precise location loops "failed, try again" (500 m guard, `PropertyLocationProvider.swift:82`).
- P2 Dead code: `VisionMeterNumberRecognizer` (never resumes on throw, unused), `UnimplementedMeterNumberRecognizer`, `setFootprintClearAttested`, `setTransferSwitchSpaceAttested`, `retryPropertyLocation`, `frontWorkspaceWidth/DepthInches`; duplicate fields `meterAndPanelSameWall` / `meterAndPanelShareWall`.
- P2 Camera permission string still mentions a breaker photo; `DEVELOPMENT_TEAM = AGWR7PG3MN` hardcoded in pbxproj; a `BaseARTests` stub exists despite the no-tests rule.

## Spec and policy conflicts
- `EquipmentScan.mlpackage` (YOLO) ships on `main` (`EquipmentDetecting.swift:34,67`), while `AGENTS.md` forbids automatic equipment detection.
- TypeSafe Jev (branches only) posts survey data to an external API, against the no-backend rule, and is the shared compile error.
- An `attested` (teal) tone exists; the spec defines only green / amber / red.
- `AGENTS.md` and README say footprint and transfer-switch space are unmeasured so the preview cannot turn green; `main` now measures both. `AGENTS.md` lists 8 rules, the code has 12. `reports/Base battery form vs app.md` and `research_notes/.../app_inventory.md` are stale.
