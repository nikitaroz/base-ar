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

## Conservative interpretation

Spatial rules require identified observations with normal tracking for the selected model. The user reporting no visible gas meter now leaves clearance unknown, rather than passing a check for an unobserved object.

The earlier program/local-requirements check remains unknown. “Saved together” describes evidence consistency, not electrical safety, regulatory compliance, engineering accuracy or installation approval.

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
| Save succeeds | JSON and image identify the same scan, revision, model and capture |
| Detector model fails to load/infer | Explicit failure state, not a confident “no equipment present” result |
| Scan disabled/re-enabled or orientation changes during inference | Prior-generation results are discarded |
| Detector takes longer than a capture interval | No unbounded queue; latest valid results only |
| Detector output is delayed | Expired result cannot place equipment in the current scene |
| Phone has no LiDAR | Missing measurements remain unknown; supported capture/deferral paths remain usable |

## What this does not prove

The changes do not establish measured phone latency, thermal behavior, optical recognition accuracy, geometric coverage completeness or native build success. Those require an actual device run, independent evidence review and recorded results rather than stronger wording in the interface.
