# BaseAR Real-Time Guidance: Bot Workstreams

These are ready-to-assign implementation charters, not a claim that autonomous coding bots or a Jev service have been deployed. This review used two bounded research/audit agents; runtime implementation should begin only after the shared contracts below are accepted.

The team's human owners are Nikita for recognition, Firus for LiDAR/AR, and Logan for flow/survey/Jev ([team brief](https://app.notion.com/p/BaseAR-3e756197728880bba1a4f8609e6df29a)). One app should present one coherent hint, regardless of how many bots help build it.

## Integration rules

- **Branch base:** Start from `feat/guided-site-survey` after pulling the agreed integration commit; never overwrite a teammate's working tree.
- **Separate worktrees:** One branch/worktree per coding bot. Branch names below are proposed, not pre-created.
- **Shared ownership:** Logan or one nominated integrator alone edits `SurveySession.swift`, `SurveyStore.swift`, `SurveyExporting.swift`, `ContentView.swift` and `project.pbxproj`.
- **Contract freeze:** Agree observation IDs, scan generation, revision, measurement provenance, capture token, permitted actions and commit result before feature edits.
- **No unit tests:** Follow `AGENTS.md`; use static checks, a native build, documented manual/device scenarios and observed benchmark runs.
- **No unsolicited infrastructure:** Do not create paid services, use API keys in client code, deploy model servers, upload household frames, or claim Base submission without explicit approval.
- **Review boundary:** Bots do not merge their own work into main. The integrator reviews diffs, checks the native build, then performs the device pass.

## Bot A: Recognition and capture observations

**Human owner:** Nikita. **Proposed branch:** `feat/capture-observations`.

**Exclusive area:** `EquipmentDetecting.swift` and new recognition/quality components. Do not change `PlacementARView.swift`, shared session/store or the project file.

**Task:** Produce timestamped, generation-tagged observations for detected subject, bounding region, candidate label and measured quality indicators. Preserve the current meter/panel model until a separately verified export and licensing decision adds classes; distinguish detector failure from a confident no-detection result.

**Contract:** Return observation data only. Do not choose installation outcomes, advance survey state or create “measured clear” claims.

**Done:** Demonstrate stable candidate behavior, no stale packet after a step/scan change, bounded in-flight work and measured inference latency on the actual phone. Clearly label any quality heuristic rather than presenting it as a calibrated classifier.

## Bot B: Spatial truth and capture integrity

**Human owner:** Firus. **Proposed branch:** `fix/spatial-evidence-validity`.

**Exclusive area:** `PlacementARView.swift`, `PlacementMeasuring.swift`, `BatteryGeometry.swift`, and new spatial-evidence helper files. Coordinate measurement DTO changes with the integrator; do not edit the detector, store or rules independently.

**Task:** Fix the audited P0 issues: approximate placement is preview-only; missing coverage remains unknown; missing new measurements invalidate old passes; screenshot callbacks carry capture identity; old scan/model evidence cannot be accepted as current.

**Contract:** Emit one versioned placement-capture bundle containing scan ID, revision, battery model, snapshot time, measurement provenance/coverage and screenshot token/image. The integrator's commit API reports durable success or explicit failure.

**Done:** Manually demonstrate weak/no mesh, model change, reopening AR, changed placement after screenshot, screenshot failure and stale callback handling. No measured pass may depend solely on “no obstacle happened to be sampled.”

## Bot C: Local guide and UX

**Human owner:** Logan. **Proposed branch:** `feat/adaptive-guidance`.

**Exclusive area:** New `Guidance/` types/policy/presenter plus guided/electrical UI files assigned by the integrator. Do not modify Bot A/B files.

**Task:** Consume observations and select one fixed-copy corrective hint. Implement local fallback, expiry, hysteresis/cooldown, explicit confirmation, accessible visual feedback and optional non-repetitive haptics.

**Contract:** `ObservationSnapshot -> GuidanceDecision`; decisions include observation/revision/policy identity, allowed action and reason. Never set approval, erase missing evidence, or turn a model probability into a distance.

**Done:** Show wrong subject, unreadable label, weak tracking, conflicting observations, denial/offline and safe deferral. Prompt flicker and inappropriate movement instructions are failures.

## Bot D: Optional decision-provider experiment

**Human sponsor:** Logan. **Proposed branch:** `experiment/jev-guidance-provider`.

**Exclusive area:** Provider specification and a separate, explicitly approved server adapter folder. No app schema, AR, detector, project configuration or client secrets.

**Task:** Compare a local deterministic baseline with TypeSafe Jev over the same structured observations. Add a pinned OpenJev alternative only if its deployment, license and event eligibility are cleared; do not treat unrelated OpenJev projects as one dependency.

**Contract:** Validated allowed-action request/response. Deadline, malformed-output rejection, stale-result rejection, model-version recording, request cancellation and a fully usable offline fallback are required. Raw household images/addresses/meter identifiers are excluded by default.

**Done:** Provide observed p50/p95 request and end-to-end hint latency, action agreement, rejected-action rate and examples where the provider improves the next evidence request. If there is no demonstrated improvement, keep the experiment disabled.

## Bot E: Integration and acceptance

**Human owner:** One nominated integrator; Logan unless reassigned. **Proposed branch:** `chore/guidance-integration`.

**Exclusive area:** Shared session/store/export contracts, rules, root navigation, Xcode project references and validation documentation. This bot coordinates rather than rewriting other bots' implementations.

**Task:** Integrate A/B/C only after their contracts align. Keep provider D optional; verify existing guided draft migration, consent/privacy boundaries, durable capture commits and export consistency.

**Done:** Native Xcode build and observed LiDAR/non-LiDAR walkthrough, permission denial, interruption/resume, offline mode, screenshot-write failure and reviewer packet inspection. Record actual results separately from expected outcomes.

## Recommended concurrency

Start with B's P0 fixes and A's observation contract in parallel, with the integrator owning schema changes. C can build the policy/presenter against agreed observations; D stays a bounded comparison rather than a critical-path dependency.

Avoid five bots simultaneously touching the app before the contract is stable. Three implementation streams aligned with the existing three human owners are more useful than adding agent count without isolated responsibilities.
