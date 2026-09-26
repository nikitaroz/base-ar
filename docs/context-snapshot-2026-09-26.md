# BaseAR Context Snapshot: Team Brief and Vision Discussion

Captured September 26, 2026. This document preserves the newly supplied context without treating brainstormed requirements or another assistant's claims as validated engineering facts.

## Sources read

- **Team brief:** [BaseAR Notion page](https://app.notion.com/p/BaseAR-3e756197728880bba1a4f8609e6df29a). Read through the browser; the connected Notion fetch returned a workspace/page-access error, but the supplied browser page exposed the content.
- **Technical discussion:** [iPhone Vision Models, shared ChatGPT conversation](https://chatgpt.com/share/6ab82c15-e9a8-83ea-b024-81385d6cfde1). Read the full visible exchange through the browser after the content crawler failed.
- **Implementation baseline:** Main `727c9817a85884b12ca343ccf3ff2ecb370b412a`, with guided-survey implementation `9cc7dbc9cc2a1e9baf33724254333ff4557e938e` on `feat/guided-site-survey`. The repository remains the implementation source of truth, not this snapshot.

## Team intent and ownership

The team describes a manual Base onboarding process with photo review, complex instructions and repeated requests for evidence, and proposes an iPhone AR/AI assistant to improve capture and preview battery placement ([team brief](https://app.notion.com/p/BaseAR-3e756197728880bba1a4f8609e6df29a)). These are the team's stated problem assumptions; no measured review-time or conversion improvement has been provided.

The recorded ownership is **Nikita: object recognition; Firus: LiDAR and AR; Logan: flow, survey, and Jev real-time guidance** ([team brief](https://app.notion.com/p/BaseAR-3e756197728880bba1a4f8609e6df29a)). Bot work should support those boundaries rather than create multiple owners for the AR view or shared session schema.

The brief's intended journey is breaker/panel reading, electric meter capture, AR placement, and a final Base-team review packet containing location information ([team brief](https://app.notion.com/p/BaseAR-3e756197728880bba1a4f8609e6df29a)). The current app's actual handoff is local JSON/images through the iOS share sheet, not an automatic Base submission.

## Requirements retained as context

- **Product family:** The brief discusses legacy single/double ground-mounted batteries and Base Core, including a two-Core configuration; model-specific dimensions and requirements must remain separate ([team brief](https://app.notion.com/p/BaseAR-3e756197728880bba1a4f8609e6df29a)).
- **Siting candidates:** It lists a planning footprint, meter/wall/gas distances, transfer-switch space, windows and obstructions; these are candidate rules that need source, model, program and geometric-reference validation ([team brief](https://app.notion.com/p/BaseAR-3e756197728880bba1a4f8609e6df29a)).
- **Electrical candidates:** It distinguishes main-breaker range, solar/two-battery panel requirements, number/location of panels, same-wall context, maximum meter height, and visible equipment condition ([team brief](https://app.notion.com/p/BaseAR-3e756197728880bba1a4f8609e6df29a)).
- **Expansion ideas:** Location-tagged evidence, potential satellite prequalification and optional ERCOT enrichment are brainstormed, not shipped functionality ([team brief](https://app.notion.com/p/BaseAR-3e756197728880bba1a4f8609e6df29a)).

## Corrections and unresolved assumptions

### Location is useful, but not exact equipment positioning

The brief characterizes phone location as an exact location and more authoritative than an address ([team brief](https://app.notion.com/p/BaseAR-3e756197728880bba1a4f8609e6df29a)). Do not carry that wording into the app: retain address confirmation, reported phone accuracy, capture time, property association, and local AR geometry as distinct evidence; a phone fix does not certify a meter coordinate, parcel boundary or permit-ready site survey.

### A green preview must not mean approved

The brief proposes a green battery when placement rules pass ([team brief](https://app.notion.com/p/BaseAR-3e756197728880bba1a4f8609e6df29a)). Keep separate states for visual preview, captured evidence, preliminary measured checks, unknown/unobserved areas, and qualified installation approval; the feature branch intentionally retains a required unknown program/local-review check.

### The vision discussion is useful architecture, not a benchmark

The shared conversation recommends YOLOE/Core ML for detection, Vision OCR for labels, ARKit depth/geometry for spatial evidence, and an optional Jev layer over observations ([shared discussion](https://chatgpt.com/share/6ab82c15-e9a8-83ea-b024-81385d6cfde1)). Preserve that separation, but do not adopt its proposed frame rates as measured BaseAR performance or confuse its answer about YOLOE with a claim that Jev runs locally on an iPhone.

YOLOE export fixes the configured classes into the exported model; new prompts require re-exporting, and prompts describe appearance rather than arbitrary relationships or conditions such as damage ([YOLOE documentation](https://docs.ultralytics.com/models/yoloe/)). The inspected BaseAR detector currently maps only electric meter and breaker panel, so windows, vents, gas equipment and AC units are not automatically supported merely because the architecture could detect them later.

The discussion suggests RoomPlan for structural recognition, but Apple's product page describes room floor plans, not an outdoor electrical-site survey system ([Apple RoomPlan](https://developer.apple.com/augmented-reality/roomplan/)). Treat outdoor recognition and measurement as their own engineering problem.

ARKit depth associates pixels with estimated distances and exposes a confidence map that can filter lower-accuracy data ([Apple ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata)). Mapping an object mask to depth is plausible; calling the resulting point a compliant nearest-surface clearance still requires geometry, reference-point and uncertainty handling.

### “OpenJev” is not one unambiguous dependency

TypeSafe Jev currently accepts text/structured text state, not direct images, audio or video ([TypeSafe state](https://docs.typesafe.ai/concepts/state)). The independent `razorback16/openjev` server and the Hugging Face `openjev/openjev` 27B checkpoint are different projects with different serving and licensing conditions ([decision server](https://github.com/razorback16/openjev), [27B model card](https://huggingface.co/openjev/openjev)).

Do not add an “OpenJev” dependency without recording the exact repository, model identifier, revision, artifact license and execution location. See [the assessment](realtime-guidance-assessment.pplx.md) and [bot workstreams](realtime-agent-workstreams.md) for the recommended next steps.
