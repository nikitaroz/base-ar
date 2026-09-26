# Base Site Survey

A small iPhone app for a preliminary Base Power site survey. It collects meter and breaker photos, previews a Base Core in AR, and writes a local review. It is not an electrical inspection or installation approval.

The Xcode target is still `BaseAR`. The home-screen name is **Base Site Survey**.

## Xcode and device setup

1. Open `BaseAR.xcodeproj`.
2. Select the `BaseAR` scheme and a physical iPhone running iOS 17 or later.
3. Allow camera and While Using location when asked. Location is the phone’s property fix (latitude, longitude, time, and reported horizontal accuracy). It is not the battery position.
4. Run the app outdoors, or somewhere the phone can see the ground and a wall.

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
- `BaseAR/Electrical` — meter and breaker capture, manual amperage, OCR hook
- `BaseAR/Placement` — AR placement, battery size, measurements
- `BaseAR/Rules` — `EligibilityRule`, `BaseRuleSet`, pass / conflict / unknown
- `BaseAR/Review` — review screen and JSON export
- `BaseAR/Location` — one-shot property location

`SurveyStore` is the composition root. The three workstreams meet at `MeterNumberRecognizing`, `PlacementMeasuring`, and `SurveyEvaluating`.

## What works

- Splash → intro → four-tile hub (home and personal info, electrical meter, breaker box, battery placement). Every tile is open; nothing is locked yet.
- Home and personal info stores a name, email, phone, property address or identifier, own or rent, solar, portable generator, whole-home standby generator, existing whole-home battery, planned battery count (1 or 2), and the phone’s property location fix when allowed. Those choices are radio buttons. The fix requests precise location and is shown on a map. Address suggestions come from MapKit as you type.
- Photograph the round meter and the main disconnect from separate hub tiles. The meter number and breaker amperage are different fields.
- Outdoor `ARView` with horizontal and vertical plane detection. Tap to place, drag to move, and rotate a Base Core placeholder at 30.68 in W × 35.9 in H × 22 in D, with a separate 3 ft × 3 ft pad. Mark the electric meter, and optionally the gas meter.
- LiDAR scene mesh and occlusion when the phone supports it. Placement still uses plane raycasts without LiDAR.
- Review is reachable from the hub (and after placement). It shows both photos, the confirmed breaker value, the home-form answers, the AR screenshot, rule results, and what is still missing.
- A local `survey.json` is saved next to the photos and can be shared from the review screen.
- The battery preview is green only when every required check passed on measured evidence. Unknown stays amber. A measured conflict turns it red.

Siting numbers follow Base’s published guidance: Austin main breakers 150–200A, 200A when the home has solar or two batteries, a 3 ft × 3 ft footprint, within 20 ft of the meter, within 1 ft of the wall, at least 3 ft from a gas meter, and space for a transfer switch beside the meter.

- https://www.basepowercompany.com/specs/core
- https://help.basepowercompany.com/en/articles/10280705
- https://help.basepowercompany.com/en/articles/10280641

## How this maps to Base

Base’s public request is two steps, researched 26 September 2026. [Get Started](https://www.basepowercompany.com/get-started) collects ownership, energy setup, address, and contact. Engineers later judge the site from a [photo kit](https://help.basepowercompany.com/en/articles/10280641): meter with a legible number, wide shots around the meter (surrounding, left, right, adjacent wall, behind the fence), breaker box, disconnect amperage, and breaker-area context. The longer comparison is in `reports/Base battery form vs app.md`.

This app already asks the typed home-form questions and stores one meter photo, one breaker photo, typed meter number and amperage, and an AR screenshot. It does not yet capture Base’s wide meter-yard photos. Meter height (6 ft), working space in front of the meter and panel (about 30 × 36 in), and whether the meter and panel share a wall belong to AR placement, not the home form. The survey stays on the phone.

## What is stubbed

- Meter OCR always returns nil. The number is typed by hand.
- Footprint clearance (`footprintIsClear`) and transfer-switch space (`transferSwitchClearanceObserved`) are never set, so those required checks stay unknown and the preview does not turn green yet.
- Meter height, front working space, and same-wall meter/panel are not measured yet. They are AR work, not form fields.
- The wide photo kit (left, right, surrounding, adjacent wall, behind the fence, breaker-area context) is not captured.
- No ERCOT data, satellite imagery, automatic equipment detection, Base backend, or permitting logic.

## Next three tasks

1. **Electrical capture / OCR.** Implement `MeterNumberRecognizing` with Vision. Keep the typed meter number and breaker amperage as the values the user accepts.
2. **AR placement and measurements.** Measure pad clearance into `footprintIsClear`, and transfer-switch space beside the meter into `transferSwitchClearanceObserved`. Add meter height, front working space, and whether the meter and panel share a wall. Tighten wall distance against the LiDAR mesh when it exists.
3. **Rules and review export.** Extend `BaseRuleSet` only when those measurements exist. Keep each check at pass, conflict, or unknown, and keep green reserved for a full set of measured passes.
