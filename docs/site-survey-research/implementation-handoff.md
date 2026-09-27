# Implementation handoff

These are proposed incremental changes for the existing app, not features implemented by this branch. Follow the repository's `AGENTS.md`, preserve the native Apple-framework approach, and use manual acceptance checks rather than adding unit tests.

## First implementation slice

Prioritize a complete, well-labeled evidence packet before adding a backend or a general-purpose equipment detector. Keep the existing hub, live scan, AR placement, review, and local export.

- **Program selection:** Add explicit utility and Base program fields, with an unresolved state. GPS may suggest context but does not confirm a utility, unit, or meter.
- **Separate electrical observations:** Introduce panel-nameplate/bus evidence without overwriting `mainBreakerAmperage`. Keep meter serial, meter class, and display registers distinct.
- **Photo completeness:** Add the nine Base photo compositions, plus conditional slots for panel nameplate, relevant openings/obstacles, solar equipment, AC labels, and alternative placement.
- **Adaptive next actions:** Produce recapture, wider-context, alternate-location, and professional-review prompts from known evidence gaps.
- **Source-backed review:** Include rule ID, source URL, scope, research revision, evidence IDs, and uncertainty in the local export.

## Shared contracts

Suggested optional types should preserve existing survey decoding and current teammate interfaces. Do not replace the data model wholesale merely to match these names.

```text
PropertyContext
  confirmedAddress, unit
  utility, utilityConfirmationSource
  jurisdiction, jurisdictionConfirmationSource
  locationFix, accuracy

InstallationProfile
  baseProgram, batteryModel, batteryCount
  connectionTopology, approvedDesignReference
  ruleSetVersion, applicabilityStatus

PhotoEvidence
  id, slot, localFilename, capturedAt
  linkedEquipmentId, userConfirmed

EquipmentObservation
  id, equipmentId, field, value, unit
  rawText, imageRegion, sourcePhotoId
  confidence, confirmationState

ReviewAction
  id, category, reason
  requestedEvidenceSlots
  ruleIds, sourceUrls
  status
```

Observation states should distinguish candidate readings, user-confirmed readings, and professionally verified findings. AR distances need a capture method, reference points, tracking/measurement quality, and uncertainty separate from OCR confidence.

## Workstreams that fit the repo

| Workstream | Existing entry points | Deliverable |
|---|---|---|
| Capture and evidence | `ElectricalCaptureView`, `LiveLabelScanner`, `VisionElectricalRecognizer`, `SurveyStore` | Typed photo slots, label candidates, explicit confirmation, and targeted recapture |
| Profiles and rules | `SurveySession`, `BaseRuleSet`, `SurveyEvaluating` | Program/model-scoped preliminary screens with unknown/conflict states |
| Placement and handoff | `PlacementARView`, `PlacementMeasuring`, `ReviewView`, `SurveyExporting` | Obstacle/context evidence, alternative candidates, and auditable export |

Suggested future branch names are `feat/adaptive-capture`, `feat/program-aware-survey-rules`, and `feat/obstacle-aware-review`. These branches have not been created; one shared documentation branch avoids conflicting research copies.

## Rule-catalog integration constraints

The JSON catalog is a research artifact rather than a drop-in executable engine. Parse only reviewed fields and keep any rule with unresolved applicability in a review/capture-only state.

- **No universal Austin default:** Resolve the named program and confirm how Base intends its “Austin” range to be scoped.
- **No largest-number diagnosis:** A 225 A bus label cannot automatically become the main-breaker rating; numeric fragments from unrelated labels cannot be joined into a meter ID.
- **No “no detection means no hazard”:** A missing gas-meter/window detection is not a measured absence.
- **No borrowed gas-appliance threshold:** Unknown heater/vent relationships route to review.
- **No automatic source precedence by recency alone:** Check authority, equipment scope, adopted date, project date, and exceptions.
- **No approval wording:** Passing preliminary checks means the available evidence matches those checks, not that the system is code compliant.
- **No silent external submission:** Base uploads, utility access, permit filing, signatures, and customer-data sharing require actual integrations and appropriate authorization.

## Manual acceptance scenarios

| Scenario | Expected result |
|---|---|
| Utility not confirmed | Capture remains usable; program-specific conclusion stays unknown. |
| Meter serial readable, main rating absent | Save meter identity and request the main-disconnect close-up. |
| Meter face says class 200 | Record meter class, not main amperage. |
| Panel bus 225 A, main breaker 200 A | Preserve separate fields and review the applicable configuration. |
| Austin candidate has a 125 A main | Surface possible mismatch only after program applicability is confirmed; do not prescribe meter replacement. |
| CenterPoint candidate | Do not assume a new meter is necessary; utility/project review determines programming or hardware work. |
| Multiple meters or household units | Require explicit association with the surveyed unit. |
| Permit history conflicts with current label | Preserve both with dates and request review. |
| Closed operable window near placement | Do not treat closure as an exemption. |
| Unknown gas appliance or vent | Request label/context evidence and professional review. |
| AR tracking poor or threshold uncertainty overlaps | Request another measurement or leave unknown. |
| User confirms an overlay looks clear | Store attestation separately from measured dimensions. |
| Existing third-party battery | Consider the documented alternative energy-plan route rather than universal ineligibility. |
| Original preferred location blocked | Request adjacent-wall/behind-fence context and support another candidate. |
| Export complete | Say “ready for Base review”; include unresolved questions and sources. |

## Public-data enrichment as a separate slice

The electrical-data report contains tested Austin permit and utility-boundary queries. Before integrating them, define caching, query limits, source outages, address/unit confirmation, customer-data handling, and whether enrichment occurs on-device or through an approved backend.

Public permit history must not be merged silently into camera-confirmed facts. Utility consumption and meter metadata requiring customer authorization are a separate integration and must not be scraped from private accounts.

## Inputs required from Base

Obtain current, model-specific installation instructions; program one-lines; accepted meter/socket/service configurations; opening and gas-appliance policies; measurement reference definitions; and approved exception handling. The exact questions and source conflicts are detailed in the expansion report.

No physical-device build, accuracy validation, utility authorization, or Base installation approval was performed as part of this documentation save. Those remain explicit acceptance gates for future implementation.
