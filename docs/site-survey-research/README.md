# Base Site Survey research and implementation context

This directory preserves the research and product decisions behind expanding the existing native iPhone app into an adaptive Base Power setup assistant. It is a documentation and research-data snapshot, not a new app implementation or an approved installation rule set.

Research date: September 26, 2026. Documentation branch base: `cf3f1e413b6c553e8a0f7fea639e94bf6f5da44c`; the individual reports retain the earlier repository snapshots they reviewed, so code-specific observations must be rechecked against the current app.

## Start here

| File | Purpose | Status |
|---|---|---|
| [Decision log](decision-log.md) | User intent, selected direction, rejected shortcuts, and scope boundaries | Current product context |
| [End-to-end expansion](end-to-end-expansion.md) | Utility programs, city/state process changes, placement constraints, adaptive capture, and repo mapping | Latest research synthesis |
| [Electrical capture and property data](electrical-capture-and-property-data.md) | Swift/ARKit/Vision capabilities, public Austin APIs, actual permit examples, and authorized utility data | Supporting research; code snapshot is older |
| [Implementation handoff](implementation-handoff.md) | Incremental workstreams, suggested interfaces, manual acceptance scenarios, and open questions | Proposed work, not implemented |
| [Rule catalog](data/rule-catalog.json) | 30 source-backed candidate rules, six program profiles, photo slots, and prohibited automatic outputs | Research data only |
| [Source inventory](data/source-inventory.csv) | 293 source records with URLs, retrieval status, timestamps, and available hashes | Retrieval index, not proof of current applicability |
| [Coverage](data/coverage.json) | Public-site collection coverage and limitations | Snapshot metadata |
| [Earlier idea selection](archive/idea-selection.md) | Enrollment versus physical design, Base OS, and Arbor-inspired offer comparison | Historical; not the current roadmap |
| [Original reviewed design input](archive/design-options-reviewed-input.md) | The supplied physical-design/options document that informed the early discussion | Preserved input; not independently revalidated by this save |

## Current direction

Keep `base-ar` and its SwiftUI, ARKit, RealityKit, Vision, and Core Location foundations. Expand the homeowner survey to select the right utility/program context, collect readable electrical evidence, identify possible siting conflicts, and export a packet that a Base reviewer can act on.

The target is a better next question or next photograph, not an automatic electrical diagnosis. Final output should say “ready for Base review,” not “installation approved.”

## How to interpret the research

- **Source layers:** Keep Base policy, utility design requirements, manufacturer instructions, model-code references, state/local process rules, and product recommendations separate.
- **Scope:** Apply rules by confirmed utility, Base program, jurisdiction, equipment model, configuration, project date, and source revision.
- **Evidence:** Distinguish historical permits, current photographs, user confirmation, AR measurements, user attestation, and professional decisions.
- **Uncertainty:** Missing evidence, unresolved source conflicts, and unknown model applicability must stay unknown.
- **Replacement decisions:** A meter photograph alone must not produce a mandatory meter/socket/service replacement recommendation.
- **Repository constraints:** This branch does not change [AGENTS.md](../../AGENTS.md), add runtime dependencies, introduce a backend, or generate unit tests.

The catalog's `installationApprovalAllowed` flag is false. Its `automation` and `scope` fields explicitly distinguish preliminary screens, capture prompts, professional-review routes, and disabled model-code enforcement.

## High-value primary links

- **Base capture kit:** [Photo-review instructions](https://help.basepowercompany.com/en/articles/10280641).
- **Base siting/electrical guidance:** [Equipment requirements](https://help.basepowercompany.com/en/articles/10280705).
- **Hardware versions:** [Core specifications](https://www.basepowercompany.com/specs/core) and [legacy ground-mounted specifications](https://www.basepowercompany.com/specs/ground-mounted).
- **Utility program routing:** [Austin Energy program](https://www.basepowercompany.com/austinenergy) and [general utility partnerships](https://www.basepowercompany.com/utilities).
- **Actual meter-change guidance:** [CenterPoint small-scale DER documentation](https://www.centerpointenergy.com/en-us/Documents/DistributedGenerationDocs/SmallScale-DER-Project-Documentation.pdf).
- **Texas regulatory change:** [TDLR explanation of SB 1252](https://www.tdlr.texas.gov/news/2025/08/14/sb-1252-changes-to-residential-energy-backup-system-regulations/).
- **Local process examples:** [Dallas Service First Bulletin 204](https://dallascityhall.com/departments/sustainabledevelopment/DCH%20documents/SFB%20%23204.pdf) and [Houston backup-power process](https://www.houstonpermittingcenter.org/news-events/notice-process-updates-residential-backup-power-systems).
- **Public property evidence:** [Austin electrical/construction permit dataset](https://data.austintexas.gov/Building-and-Development/Issued-Construction-Permits/3syk-w9eu).
- **Customer-authorized utility data:** [Smart Meter Texas data-access guide](https://www.smartmetertexas.com/commonapi/gethelpguide/help-guides/Smart_Meter_Texas_Data_Access_Interface_Guide%20-%20v2.pdf).

Exact source links for individual claims and tested API queries are retained inside the reports. Use the CSV inventory for broader discovery, not as a substitute for reading the relevant section and its exceptions.

## Coverage and exclusions

Collection enumerated 176 Base sitemap URLs and retrieved all 92 linked English FAQ articles; 165 sitemap pages exposed substantial text, while 11 exposed form-loading or document-wrapper content ([Base sitemap](https://www.basepowercompany.com/sitemap.xml), [Base help center](https://help.basepowercompany.com/en/)). Private installer documents, interactive form branches, videos, and every image/diagram were not exhaustively reviewed.

This branch includes interpreted findings and links rather than raw copyrighted website dumps. It excludes session logs, credentials, customer photos, property-specific private data, and unrelated personal context.

## Suggested branch strategy

Keep this as the shared research branch rather than splitting documents into competing sources of truth. Later implementation branches can independently address capture, rule/profile evaluation, and AR/review, following the interfaces in the handoff.

Nothing here authorizes a production permitting engine, a utility submission, or public claims of compliance. Obtain Base's current installation manual, approved program one-lines, and compatibility criteria before promoting research candidates into production requirements.
