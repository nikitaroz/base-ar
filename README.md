# Base Site Survey

A small iPhone app for a preliminary Base Power site survey. It collects meter and breaker photos, previews a Base Core in AR, and writes a local review. It is not an electrical inspection or installation approval.

The Xcode target is still `BaseAR`. The home-screen name is **Base Site Survey**.

## Xcode and device setup

1. Open `BaseAR.xcodeproj`.
2. Select the `BaseAR` scheme and a physical iPhone running iOS 17 or later.
4. Allow camera after choosing a photo task, and allow While Using location after tapping **Use current location**. Location is the phone’s property fix (latitude, longitude, time, and reported horizontal accuracy). It is not the battery position.
3. **(Optional)** To enable TypeSafe Jev advisory in the review screen, add `TYPESAFE_API_KEY` to the environment or Info.plist. Without the key, the advisory panel is hidden and the app works normally.
5. Run the app outdoors, or somewhere the phone can see the ground and a wall.

AR placement needs a physical iPhone. The simulator can open the survey, take library photos, and reach review, but world tracking stays unavailable there.

If command-line builds use Command Line Tools instead of Xcode:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project BaseAR.xcodeproj \
  -scheme BaseAR \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

Or select Xcode once with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

## Project structure

- `BaseAR/Survey` — shared `SurveySession` and `SurveyStore`
- `BaseAR/Electrical` — meter and breaker capture, live scan, and photo OCR
- `BaseAR/Placement` — AR placement, battery size, measurements
- `BaseAR/Rules` — `EligibilityRule`, `BaseRuleSet`, pass / conflict / unknown
- `BaseAR/Review` — review screen and JSON export
- `BaseAR/Location` — one-shot property location

`SurveyStore` is the composition root. The three workstreams meet at `MeterNumberRecognizing`, `PlacementMeasuring`, and `SurveyEvaluating`.

## What works

- One-screen welcome → four-tile hub (home and personal info, electrical meter, breaker box, battery placement). Every tile is open, shows completion progress, and saves as you go.
- Home and personal info stores a name, email, phone, property address or identifier, own or rent, solar, portable generator, whole-home standby generator, existing whole-home battery, planned battery count (1 or 2), and the phone’s property location fix when allowed. Those choices are radio buttons. The fix requests precise location and is shown on a map. Address suggestions come from MapKit as you type.
- Photograph the round meter and the main disconnect from separate hub tiles. The meter number and breaker amperage are different fields. On an iPhone, Scan highlights the number in a card-style frame and saves that photo. A normal photo can also fill an empty field. The typed value is the one that is kept.
- Outdoor `ARView` with horizontal and vertical plane detection. Placement is a short walkthrough: aim a dot, tap +, then drag and twist the Base Core placeholder (30.68 in W × 35.9 in H × 22 in D, on a 3 ft × 3 ft pad). Later steps mark the meter, measure like the Measure app, and ask one clearance question at a time.
- LiDAR occlusion when the phone supports it. Placement still uses plane raycasts without LiDAR. The mesh is not drawn on screen.
- Each measurement is one distance: battery to meter, battery to wall, battery to gas meter, and meter height. Battery distances start automatically at the battery's nearest base edge, so you only aim at the target; they are horizontal. Meter height is the vertical rise from the ground point to the meter face. Points prefer detected planes and fall back to estimated planes.
- Answering "No gas meter" is saved in `survey.json` (`gasMeterNotPresent`) and passes the gas-clearance check.
- One step places a 30 × 36 in working-space overlay. Separate steps ask whether that space is clear, whether the 3 × 3 ft pad is clear, whether transfer-switch space is available, and whether the meter and panel share a wall.
- Review is reachable from the hub (and after placement). It leads with grouped next actions, then provides collapsible property, electrical, placement, and rule details with edit links.
- A local `survey.json` is saved next to the photos and can be shared from the review screen.
- The battery preview is green only when every required check passed on measured evidence. Unknown stays amber. A measured conflict turns it red.

Siting numbers follow Base’s published guidance: Austin main breakers 150–200A, 200A when the home has solar or two batteries, a 3 ft × 3 ft footprint, within 20 ft of the meter, within 1 ft of the wall, at least 3 ft from a gas meter, and space for a transfer switch beside the meter.

- https://www.basepowercompany.com/specs/core
- https://help.basepowercompany.com/en/articles/10280705
- https://help.basepowercompany.com/en/articles/10280641

## How this maps to Base

Base’s public request is two steps, researched 26 September 2026. [Get Started](https://www.basepowercompany.com/get-started) collects ownership, energy setup, address, and contact. Engineers later judge the site from a [photo kit](https://help.basepowercompany.com/en/articles/10280641): meter with a legible number, wide shots around the meter (surrounding, left, right, adjacent wall, behind the fence), breaker box, disconnect amperage, and breaker-area context. The longer comparison is in `reports/Base battery form vs app.md`.

This app already asks the typed home-form questions and stores one meter photo, one breaker photo, typed meter number and amperage, and an AR screenshot. It does not yet capture Base’s wide meter-yard photos. Meter height (6 ft), working space in front of the meter and panel (about 30 × 36 in), and whether the meter and panel share a wall belong to AR placement, not the home form. The survey stays on the phone.


## TypeSafe Jev Advisory

When `TYPESAFE_API_KEY` is configured, the review screen includes an optional TypeSafe Jev advisory panel. It calls `POST https://api.typesafe.ai/v1/systemone` with a compact survey state (photos, distances, rule results, form summary, and Austin+Houston policy catalogs) and asks four questions:

- **visit_ready** (noul): Is the survey ready for a Base engineer visit?
- **next_action** (choice): What should the homeowner do next?
- **blocking_gap** (choice): Which missing or failing evidence is the highest-priority blocker?
- **readiness_score** (score 0-3): How ready is this survey for engineer review?

The advisory is **event-driven and throttled** — it fetches only when the user taps Refresh or when the review screen first appears, not on every AR frame or survey change. Gracefully degrades on 401/422/429/timeout to "advisoryUnavailable" without blocking survey completion. The panel is hidden when the key is missing.

**Advisory only** — it never overrides measured green/amber/red placement color or rule pass/conflict/unknown outcomes from `EligibilityRule`.
## What is stubbed

- AR measurements are preliminary raycast estimates and still need physical-device field verification; they do not replace an installer measurement.
- The wide photo kit (left, right, surrounding, adjacent wall, behind the fence, breaker-area context) is not captured.
- No ERCOT data, satellite imagery, automatic equipment detection, Base backend, or permitting logic.

## Next three tasks

1. **Electrical capture / OCR.** Done. Vision reads a meter number and main-breaker amperage from a photo, and a live card-style scan can fill either field. The typed value is still the one the user accepts.
2. **AR placement and measurements.** Measure pad clearance into `footprintIsClear`, and transfer-switch space beside the meter into `transferSwitchClearanceObserved`. Add meter height, front working space, and whether the meter and panel share a wall. Tighten wall distance against the LiDAR mesh when it exists.
3. **Rules and review export.** Extend `BaseRuleSet` only when those measurements exist. Keep each check at pass, conflict, or unknown, and keep green reserved for a full set of measured passes.
