# Project Instructions

- This is a hackathon project. Prioritize speed, simplicity, and rapid iteration over production-level architecture or overengineering.
- Do not write, add, or generate unit tests for this project.

## Product

**Base Site Survey** is a native iPhone app for a three-person hackathon. Base Power asks homeowners for electrical and site photos; engineers review them and may request more evidence. The app is a guided capture flow that produces a useful preliminary survey and an AR battery-placement preview.

It is a prototype. Never present it as final electrical, code, or permitting approval.

The Xcode target is `BaseAR`. The home-screen name is Base Site Survey.

## Constraints

- Apple frameworks only: SwiftUI, ARKit, RealityKit, Vision/VisionKit where needed, Core Location, and standard camera APIs.
- Target a physical iPhone. AR placement needs a device; the simulator can walk the survey without world tracking.
- No backend, accounts, external datasets, or third-party dependencies.
- **OpenJEV exception:** Optional advisory via HTTPS to `api.openjev.sh`. This is strictly advisory guidance that does NOT override measured rule-based checks. The feature is feature-flagged and gracefully degrades when the API key is not configured or the service is unavailable.
- Do not add ERCOT data, satellite imagery, automatic equipment detection, a Base integration, or production-grade permitting logic unless a later task explicitly asks for it.
- GPS is the phone’s property fix (latitude, longitude, timestamp, reported horizontal accuracy) when location permission is granted. Do not describe it as the precise battery position.

## Flow

1. **Splash.** Brief branded start (home-screen name: Base Site Survey).
2. **Intro.** Setup-assistant screen (“Let’s get your battery placement”) that opens a new `SurveySession`.
3. **Hub.** Four tiles, all available at once (debug layout; a forced step-by-step wizard may come later):
   - **Home and personal info** — name, email, phone, address or property identifier, own or rent, solar, portable generator, whole-home standby generator, existing whole-home battery, and planned battery count (1 or 2). Those choices use radio buttons. The phone’s property location fix requests precise location and is shown on a map, with the reported accuracy drawn as a circle.
   - **Electrical Meter** — round meter photo and meter number.
   - **Breaker box** — main disconnect/breaker photo and amperage. Meter number and amperage stay distinct fields.
   - **Battery placement** — outdoor `ARView` with ground and wall plane detection. Tap the ground to place, move, and rotate a simple 3D Base Core placeholder at about **30.68 in W × 35.9 in H × 22 in D**, with a separately visible **3 ft × 3 ft** planning footprint. Mark the meter in the scene. Use LiDAR mesh when supported; placement must still work without LiDAR.
4. **Review.** Reachable from the hub (and after placement). Show both images, the confirmed breaker value, the solar answer, an AR placement screenshot, and what is still missing. Save a local JSON survey and make the review screen shareable.

## Parallel work

Keep a small shared data model and clear interfaces so three people can work independently. `SurveyStore` is the composition root. The workstreams meet at:

- **Electrical capture / OCR** — `MeterNumberRecognizing`. Typed meter number and breaker amperage stay the values the user accepts.
- **AR placement and measurements** — `PlacementMeasuring`. Battery size, footprint, meter mark, wall and gas distances, meter height, front working space, and whether the meter and panel share a wall.
- **Rules / review export** — `SurveyEvaluating` and `SurveyExporting`. `EligibilityRule`, `BaseRuleSet`, review UI, local JSON.

## Rules and placement color

`EligibilityRule` checks return **pass, conflict, or unknown**. Implement only checks supported by actual captured evidence.

Configurable Base guidance (Austin):

- Main breaker 150–200A.
- Solar or two batteries requires a 200A panel.
- 3 ft × 3 ft battery footprint.
- Within 20 ft of the meter.
- Within 1 ft of the wall.
- At least 3 ft from a gas meter.
- Space for a transfer switch beside the meter.

The placement preview is **green** only when every required check has measured evidence and passes. **Amber** means unknown. **Red** means an observed conflict.

**OpenJEV advisory:** The Review screen shows an optional OpenJEV advisory panel when the API key is configured. This panel sends survey state and current BaseRuleSet pass/conflict/unknown results to `api.openjev.sh/v1/systemone` with model `openjev`, asking typed questions about visit readiness, next action, and priority gaps. The advisory is strictly guidance and does NOT override the measured green/amber/red from EligibilityRule. The panel gracefully hides or shows "advisory unavailable" when offline, unauthorized, or timed out.

Official references:

- https://www.basepowercompany.com/specs/core
- https://help.basepowercompany.com/en/articles/10280705
- https://help.basepowercompany.com/en/articles/10280641

## Base intake vs this app

Researched 26 September 2026. Full comparison: `reports/Base battery form vs app.md`.

Base splits a battery request into two steps. [Get Started](https://www.basepowercompany.com/get-started) is a zip-gated join form (own or rent, energy setup, address, name, phone, email). After signup, engineers judge the site from a separate photo kit. This app is a local stand-in for that photo-and-siting step, plus the Austin checks above. It writes `survey.json` on the phone. It does not submit anything to Base.

**Home form.** Record the typed answers Base asks before photos, plus the electrical numbers engineers need: name, email, phone, address, own or rent, solar, portable generator, whole-home standby generator, existing whole-home battery, and planned battery count. Skip marketing SMS, “how did you hear about us,” ESIID, and utility-account fields.

Base’s product filters stay on the survey for a person to read. Renters are waitlisted. An existing whole-home standby generator and a third-party whole-home battery are treated as incompatible. Placement color stays on measured siting checks.

**Photos.** Base’s published kit is nine compositions: a meter photo with a legible number, the surrounding meter area from about 10 steps back, the area to the right, the area to the left, the adjacent wall corner to corner, behind the fence when that applies, the breaker box, the main disconnect with amperage visible, and the area around the breaker box. This app still stores one meter photo, one breaker photo, and one AR screenshot. Typed meter number and breaker amperage remain the values the user accepts.

**AR owns height and spacing.** Meter height (published limit 6 ft), working space in front of the meter and panel (about 30 × 36 in), and whether the meter and panel share a wall are placement measurements. Keep them off the home form. The same workstream still owns the 3 ft × 3 ft footprint, the 20 ft meter distance, the 1 ft wall distance, the 3 ft gas-meter distance, and transfer-switch space beside the meter. Footprint clearance and transfer-switch space are still unmeasured, so the preview cannot turn green yet.

## Layout

- `BaseAR/Survey` — `SurveySession`, `SurveyStore`
- `BaseAR/Electrical` — meter and breaker capture, amperage, OCR hook
- `BaseAR/Placement` — AR placement, battery geometry, measurements
- `BaseAR/Rules` — `EligibilityRule`, `BaseRuleSet`
- `BaseAR/Review` — review screen, JSON export, and optional OpenJEV advisory
- `BaseAR/Location` — one-shot property location

See `README.md` for device setup, what already runs, and what is still stubbed.
