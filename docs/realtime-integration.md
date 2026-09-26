# BaseAR: Spatial Evidence and Observation Integration

This work integrates two isolated coding streams with the shared survey/store contract. It changes evidence correctness and observation freshness; it does not add Jev, a backend, a blur classifier or an installation-approval engine.

## Branch ownership

- **`fix/spatial-evidence-validity`:** Spatial measurements, AR lifecycle, capture request identity and screenshot callback handling.
- **`feat/capture-observations`:** Detector result/status metadata, observation identity and bounded processing.
- **`chore/guidance-integration`:** Combined app plus shared schema, durable save, rule gates, review presentation and validation documentation. Use this branch for the integrated handoff; workstream branches may depend on shared integration changes.

The original `feat/guided-site-survey` and `main` are not modified by this integration. Bot commits are reviewed and incorporated into the integration branch rather than merged into `main`.

## Shared evidence contract

The scene snapshot identifies its scan, revision, battery model and current tracking state. The store records these as an optional `PlacementObservationIdentity` containing:

```text
scanID: UUID
revision: UInt64
batteryModelID: String
trackingIsNormal: Bool
observedAt: Date
```

A saved screenshot additionally requires a `PlacementCaptureIdentity`:

```text
captureID: UUID
scanID: UUID
revision: UInt64
batteryModelID: String
capturedAt: Date
```

These optional Codable fields keep older packets decodable under schema 6. A legacy packet without spatial provenance can still be inspected, but its spatial checks cannot become measured passes and it does not satisfy the version-matched capture requirement.

## Durable capture commit

`SurveyStore.commitPlacementCapture(_:image:identity:)` is the shared boundary. It rejects mismatched scan/revision/model, non-normal tracking and a live scene that no longer matches the requested observation.

On a valid request, the store calculates the candidate measurements and rule results without mutating the current observable session. It writes an image with a unique capture-derived filename, then atomically replaces the JSON packet, and only then installs the candidate session in memory.

A write failure removes the new, unreferenced image and returns false. The old packet remains the record on disk; the view must display a retry state rather than navigating on success, and a crash between image creation and JSON replacement can leave an unreferenced image rather than mismatched accepted evidence.

Changing the live scan/revision/model invalidates accepted image association and previous clearance attestations. A model change clears the current capture; new observations and a new capture are required.

After a successful durable save, navigation does not recommit later live geometry over the accepted capture. Leaving without a successful save still commits the current observation, with its invalidation rules.

The screenshot path uses strict scene/mesh revision matching, a request token, a callback epoch and a five-second timeout. This deliberately favors rejection over mixing observations; continuously changing mesh revisions may cause repeated capture retries on a device. That usability risk remains unmeasured.

## Fresh equipment observations

`EquipmentScanObservation` identifies each result with a UUID, generation, monotonic capture/completion times, processing duration and explicit status. Supported statuses are `success`, `noDetections`, `modelUnavailable`, `inferenceFailed` and `frameUnavailable`; “no detections” never means the physical scene is clear.

The bridge admits one AR frame at a time and runs image/depth copying and Vision inference on a serial background queue. It retains that frame to keep its image, pose, depth and orientation together, rather than queuing an unbounded backlog.

Enable, viewport and tracking changes invalidate prior generations. Both publication and consumption reject expired or wrong-generation results; the default maximum observation age is two seconds, a configurable policy rather than a measured latency guarantee. Running Vision work is not forcibly cancelled, but its invalidated result is discarded.

The AR interface displays unavailable/waiting/no-detection states and clears expired transient boxes and incomplete equipment-lock samples. Already locked world markers are not erased merely because a later frame has no detection; they remain recorded scene observations, not fresh recognition claims.

## Conservative interpretation

Spatial rules require identified observations with normal tracking for the selected model. The user reporting no visible gas meter now leaves clearance unknown, rather than passing a check for an unobserved object.

Automatic placement requires a detected ground surface rather than an invented camera-relative ground position. Missing current clearance results replace prior values with unknown; estimated-plane measurements are excluded from confirmed evidence. An observed blocker may produce a conflict, but an absence of sampled mesh blockers does not prove clearance. Comprehensive coverage estimation is not implemented.

The earlier program/local-requirements check remains unknown. “Saved together” describes evidence consistency, not electrical safety, regulatory compliance, engineering accuracy or installation approval.

## Validation performed

Source review and static validation were performed on September 26, 2026. All 26 Swift source files were parsed and compared with baseline commit `9f297ebb07e55b39cb825b983133df2e4195e94f`; there were no new tree-sitter parser errors. Two pre-existing empty-operator parser warnings in `SurveySession.swift` remain unchanged.

The Xcode project file parsed successfully, and `git diff --check` passed. These checks are not a Swift type check or an Xcode build. No unit tests were added or run, and neither Xcode compilation nor physical-device acceptance was available in this Linux environment.

Workstream provenance:

- **Observation bot:** `45fa0284797ab0695cd42ad529eb1898d6001d80`, integrated as `2d15348`.
- **Spatial bot:** `4606d5a95db12148ba518b2fce8a6bff72a58fa2` and `82e8d996d14221f0cd517a0ef76945145a53d60a`, integrated as `c415f7a` and `10f9345`.
- **Shared integration:** `aa57892` supplies persisted identities, durable capture commit and rule/review gates; `5776cf8` wires detector status and transient overlay expiry into AR.

## Required manual acceptance

No unit tests are added, following `AGENTS.md`. Static parsing and source review do not establish native compilation or device behavior; the following scenarios must be observed on the Mac/iPhone build before treating the feature as verified.

| Scenario | Required result |
| --- | --- |
| Legacy schema-5 draft | Opens without losing readable evidence; no unproven spatial pass or accepted version-matched capture |
| No detected ground plane | No invented ground position presented as measured placement |
| Sparse mesh or missing coverage | No “measured clear” based solely on absence of sampled obstacles |
| New snapshot has no prior clearance evidence | Prior clear result becomes unknown |
| Battery model changes | Old capture is invalidated and old model measurements cannot pass |
| Tracking becomes limited or unavailable | Pending capture is rejected/cancelled; live spatial checks do not retain measured passes |
| Scene changes while screenshot is pending | Old callback cannot commit as the current observation |
| Screenshot or JSON write fails | User remains in capture with a retry/error state; no false success |
| Screenshot callback arrives after leaving AR | No navigation or evidence mutation from the stale callback |
| Save succeeds | JSON and image identify the same scan, revision, model and capture; departure does not overwrite that capture |
| Mesh continues refining while saving | Stale capture is rejected; record retry rate and whether a usable capture can be completed |
| Detector model fails to load/infer | Explicit failure state, not a confident “no equipment present” result |
| Scan disabled/re-enabled or orientation changes during inference | Prior-generation results are discarded |
| Detector takes longer than a capture interval | No unbounded queue; latest valid results only |
| Detector output is delayed | Expired result cannot place equipment in the current scene |
| Phone has no LiDAR | Missing measurements remain unknown; supported capture/deferral paths remain usable |

## What this does not prove

The changes do not establish measured phone latency, thermal behavior, optical recognition accuracy, geometric coverage completeness or native build success. Those require an actual device run, independent evidence review and recorded results rather than stronger wording in the interface.

Ordinary-camera adaptive quality coaching, the remaining OCR interruption issues, asynchronous survey persistence and a Jev decision-provider pilot are outside this patch. The next release gate is a Mac build followed by the manual scenarios above on LiDAR and non-LiDAR iPhones, not a higher readiness score based on source changes alone.
