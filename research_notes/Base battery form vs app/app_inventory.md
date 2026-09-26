# App field inventory and first-pass gap list (Base Site Survey iPhone app)

Scope: local hackathon app at `/Users/nikita/workspace/base-ar` plus the project’s own stated Base guidance. Another researcher is covering Base’s live website form; this note does not inventory that form. No code was changed. Facts below are from the repo as read on 2026-09-26.

Prototype status (project’s own words): this is a preliminary survey, not an electrical inspection or installation approval. Several model fields exist but are never asked or measured.

---

## What fields exist on SurveySession, ElectricalEvidence, PlacementEvidence, GeoFix, RuleResult?

### Takeaway
The shared contract is `SurveySession` plus nested `ElectricalEvidence`, `PlacementEvidence`, optional `GeoFix`, and derived `[RuleResult]`. Related enums on the same file are `CheckStatus` and `PlacementTone`. Positions use `PlacementAnchor` (`x`, `y`, `z`).

### Cited Findings
- `SurveySession` properties, in declaration order: `schemaVersion` (Int, default `1`), `id` (UUID), `createdAt` (Date), `propertyIdentifier` (String), `propertyLocationDisclaimer` (String), `prototypeDisclaimer` (String), `propertyLocation` (`GeoFix?`), `electrical` (`ElectricalEvidence`), `placement` (`PlacementEvidence`), `ruleResults` (`[RuleResult]`), `missingInformation` (`[String]`), `placementTone` (`PlacementTone`). Comment on `propertyLocation`: “Phone fix for the property. This is not the battery position.” — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift)
- Static disclaimer strings on `SurveySession`: `locationDisclaimer` = `"Latitude, longitude, timestamp, and horizontal accuracy are the phone's reported property location, not the battery position."`; `prototypeDisclaimer` = `"Preliminary survey only. This is not an electrical inspection, a code review, or installation approval."` — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift)
- `SurveySession.new(propertyIdentifier:)` starts a session with `propertyLocation: nil`, empty `ElectricalEvidence()`, empty `PlacementEvidence()`, `ruleResults: []`, `missingInformation: []`, `placementTone: .incomplete`. — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift)
- `GeoFix` properties: `latitude` (Double), `longitude` (Double), `timestamp` (Date), `horizontalAccuracyMeters` (Double). Comment: “Meters, as reported by Core Location. Not a survey-grade battery coordinate.” — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift)
- `ElectricalEvidence` properties: `meterPhotoFilename` (String?), `breakerPhotoFilename` (String?), `meterNumber` (String?; “Distinct from mainBreakerAmperage. Manual until OCR is connected.”), `mainBreakerAmperage` (Int?; “Confirmed by the user. Distinct from meterNumber.”), `hasSolar` (Bool?; “Nil means the question has not been answered.”), `plannedBatteryCount` (Int?; “Nil until capture asks how many batteries are planned.”). — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift)
- `PlacementAnchor` properties: `x`, `y`, `z` (Float). — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift)
- `PlacementEvidence` properties: `screenshotFilename` (String?), `batteryPlaced` (Bool, default `false`), `meterMarked` (Bool, default `false`), `gasMeterMarked` (Bool, default `false`), `lidarMeshAvailable` (Bool, default `false`), `distanceToMeterFeet` (Double?), `distanceToWallFeet` (Double?), `distanceToGasMeterFeet` (Double?), `footprintIsClear` (Bool?; “Set by the placement workstream after a real clearance measurement. Nil stays unknown.”), `transferSwitchClearanceObserved` (Bool?; “Set after transfer-switch space beside the meter is actually measured. Nil stays unknown.”), `batteryPosition` (`PlacementAnchor?`), `meterPosition` (`PlacementAnchor?`), `gasMeterPosition` (`PlacementAnchor?`), `batteryYawRadians` (Float?). — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift)
- `CheckStatus` raw values: `pass`, `conflict`, `unknown`. `PlacementTone` raw values: `clear` (“Every required check passed on measured evidence.”), `incomplete` (“A required check has no measurement yet, and none conflict.”), `conflict` (“At least one check observed a conflict.”). — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift)
- `RuleResult` properties: `id` (String), `title` (String), `requirement` (String), `status` (`CheckStatus`), `usedMeasuredEvidence` (Bool), `isRequired` (Bool), `explanation` (String). — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift)
- `SurveyStore` also holds in-memory images that are **not** Codable session fields: `meterImage`, `breakerImage`, `placementImage` (`UIImage?`), plus `exportURLs`, `lastExportError`, and `directory`. — [SurveyStore.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveyStore.swift)
- Transient AR types (not on `SurveySession`): `PlacementSceneSnapshot` (`batteryPosition`, `batteryYawRadians`, `meterPosition`, `gasMeterPosition`, `verticalPlanes`, `lidarMeshAvailable`); `PlacementMeasurements` (same distances/flags as evidence except it has **no** `footprintIsClear` or `transferSwitchClearanceObserved`); `PlaneSample` (id, center, axes, width, length). — [PlacementMeasuring.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Placement/PlacementMeasuring.swift)

### Inferences
- Anything the JSON exporter writes is exactly the Codable `SurveySession` tree above; derived rule results and missing-item strings ride along with captured evidence.
- `footprintIsClear` and `transferSwitchClearanceObserved` were designed as later measurement slots: they exist on the model so rules can stay `unknown` until a teammate fills them.

### Gaps
- No other survey model structs were found under `BaseAR/` (18 Swift files total). If a field is not listed here, it is not on the current session contract.

---

## Which of those are collected in the UI today vs exist on the model but are stubbed/unasked?

### Takeaway
The hub collects home/address + GPS, meter photo + typed meter number, breaker photo + typed amperage + solar, and AR placement (battery / meter / optional gas) with live distances. Three model fields are never written by any UI or measurer: `plannedBatteryCount`, `footprintIsClear`, and `transferSwitchClearanceObserved`. Meter OCR is wired but always returns nil.

### Cited Findings

**Collected in UI or automatically filled**

- Hub tile labels (all open; nothing locked): `"Home information"` / subtitle `"Address and location"`; `"Electrical meter"` / `"A photo and the meter number"`; `"Breaker box"` / `"Photo, breaker size, and solar"`; `"Battery placement"` / `"See where it could go"`; button `"Review survey"`. Tile status labels: `"Done"` or `"Not started"`. — [ContentView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/ContentView.swift)
- Home information (`HomeInformationView`, nav title `"Home information"`): TextField placeholder `"Property address or identifier"` writes `propertyIdentifier` via `setPropertyIdentifier`. Location section labels: `"Coordinates"` (`latitude, longitude` to 6 decimals), `"Captured"` (`timestamp`), `"Accuracy"` (`horizontalAccuracyMeters` as `"%.1f m"`). Empty state: `"Waiting for a property fix, or location was not available."` — [ContentView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/ContentView.swift)
- `propertyLocation` is requested once when `SurveyStore` is created (`PropertyLocationProvider.request()`), not typed. Accuracy target: `kCLLocationAccuracyNearestTenMeters`. Writes `latitude`, `longitude`, `timestamp`, `horizontalAccuracyMeters` only when `horizontalAccuracy >= 0`. Denied/unavailable location leaves `propertyLocation` nil. — [SurveyStore.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveyStore.swift); [PropertyLocationProvider.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Location/PropertyLocationProvider.swift)
- Meter screen (nav title `"Electrical Meter"`, section `"Round electric meter"`): buttons `"Photograph meter"` / `"Retake meter photo"` → `attachMeterPhoto` → `meterPhotoFilename = "meter.jpg"`. TextField `"Meter number"` → `setMeterNumber` → `meterNumber`. Helper: `"The meter number is separate from the breaker amperage. Reading it from the photo is not connected yet."` — [ElectricalCaptureView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Electrical/ElectricalCaptureView.swift); [SurveyStore.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveyStore.swift)
- Breaker screen (nav title `"Breaker box"`, section `"Main disconnect / breaker"`): `"Photograph main breaker"` / `"Retake breaker photo"` → `breakerPhotoFilename = "breaker.jpg"`. TextField `"Main breaker amperage"` (digits only) → `setMainBreakerAmperage` → `mainBreakerAmperage`. Confirmation labels: `"Confirmed main breaker: \(amps) A"` or `"No amperage confirmed yet."` Helper: `"Austin checks use 150–200A. Confirm the number printed on the breaker."` — [ElectricalCaptureView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Electrical/ElectricalCaptureView.swift)
- Solar section label `"Solar"`; segmented picker titles: `"Not answered"`, `"No solar"`, `"Has solar"` mapping to `hasSolar` `nil` / `false` / `true`. — [ElectricalCaptureView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Electrical/ElectricalCaptureView.swift)
- Electrical Done helper: `"You can leave blanks. Review lists what is still missing."` — [ElectricalCaptureView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Electrical/ElectricalCaptureView.swift)
- Placement (`PlacementARView`, nav title `"Placement"`): segmented picker `"Place"` with titles `"Battery"`, `"Meter"`, `"Gas"`. Hints: `"Tap the ground to place the battery. Drag to move it. Twist with two fingers to rotate."`; `"Tap the ground where the electric meter is."`; `"Tap the ground at the gas meter if you can see one."` Buttons: `"Rotate left"`, `"Rotate right"`, `"Save placement and review"`. Live readout labels: `"Meter"`, `"Wall"`, `"Gas"` distances. — [PlacementARView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Placement/PlacementARView.swift)
- `CorePlacementMeasurer.applying` writes onto `PlacementEvidence`: `batteryPlaced`, `meterMarked`, `gasMeterMarked`, `lidarMeshAvailable`, `distanceToMeterFeet`, `distanceToWallFeet`, `distanceToGasMeterFeet`, `batteryPosition`, `meterPosition`, `gasMeterPosition`, `batteryYawRadians`. It does **not** assign `footprintIsClear` or `transferSwitchClearanceObserved`. Distances are horizontal (x/z) feet; wall clearance is nearest bottom-corner distance to a vertical AR plane ≥ 0.2 m on each side, with 0.5 m margin. — [PlacementMeasuring.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Placement/PlacementMeasuring.swift)
- Review (`ReviewView`, nav title `"Review"`) can also edit `"Property address or identifier"`. It **displays** (does not collect) `"Meter number"`, `"Main breaker"`, `"Solar"`, `"Planned batteries"`, `"LiDAR mesh"` (`"Used"` / `"Not available"`), `"Battery placed"` (`"Yes"` / `"No"`), `"Meter distance"`, `"Wall clearance"`, `"Gas meter distance"`. Planned-batteries empty text: `"Not captured"`. — [ReviewView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Review/ReviewView.swift)
- `ruleResults`, `missingInformation`, and `placementTone` are overwritten on every `refreshAssessment()` from `BaseSurveyEvaluator`, not typed by the user. — [SurveyStore.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveyStore.swift); [SurveyEvaluating.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Rules/SurveyEvaluating.swift)
- `schemaVersion`, `id`, `createdAt`, and both disclaimer strings are set at session creation and are not edited in UI. — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift)

**On the model but stubbed / unasked**

- `plannedBatteryCount`: comment says nil until capture asks; README: “Planned battery count is on the model but not asked in the UI.” Grep shows no setter and no input control; Review only displays `"Not captured"`. — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift); [README.md](file:///Users/nikita/workspace/base-ar/README.md); [ReviewView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Review/ReviewView.swift)
- `footprintIsClear`: never assigned in Swift sources except the struct declaration. README: “Footprint clearance (`footprintIsClear`) and transfer-switch space (`transferSwitchClearanceObserved`) are never set.” The 3 ft pad is drawn in AR but not measured. — [README.md](file:///Users/nikita/workspace/base-ar/README.md); [PlacementARView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Placement/PlacementARView.swift); [PlacementMeasuring.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Placement/PlacementMeasuring.swift)
- `transferSwitchClearanceObserved`: same as above; no UI and no measurer write. — [README.md](file:///Users/nikita/workspace/base-ar/README.md); [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift)
- Meter OCR: `UnimplementedMeterNumberRecognizer.recognizeMeterNumber` always returns `nil`. `attachMeterPhoto` will auto-fill `meterNumber` only if OCR returns a value and the typed field is empty — that path never fires. UI copy: “Reading it from the photo is not connected yet.” — [MeterNumberRecognizing.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Electrical/MeterNumberRecognizing.swift); [SurveyStore.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveyStore.swift); [ElectricalCaptureView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Electrical/ElectricalCaptureView.swift)
- Simulator / no-AR: photo picker falls back to the library; world tracking unsupported screen says the battery preview, meter mark, and placement photo stay empty. — [CameraImagePicker.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Electrical/CameraImagePicker.swift); [PlacementARView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Placement/PlacementARView.swift); [README.md](file:///Users/nikita/workspace/base-ar/README.md)

**Hub “Done” heuristics (not the same as complete evidence)**

- Home done if `propertyIdentifier` is non-blank **or** `propertyLocation != nil`. Meter done if photo **or** non-blank meter number. Breaker done if photo **or** amperage **or** solar answered. Placement done if `batteryPlaced` **or** screenshot exists. — [ContentView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/ContentView.swift)

### Inferences
- A user can mark hub tiles “Done” while required rule evidence is still missing (e.g. address without GPS, photo without amperage).
- Because `plannedBatteryCount` is never captured, the solar / two-battery rule can only fully resolve today when amperage is 200A, or when solar is yes and amperage is not 200A (conflict), or when amperage is missing (unknown). A “no solar, one battery” pass is unreachable.

### Gaps
- No UI exists for number-of-batteries, footprint-blocked/clear, or transfer-switch space (yes/no or measurement). Those gaps are explicit in README “What is stubbed,” not inferred from missing files.

---

## What photos/screenshots are captured?

### Takeaway
Exactly three image files can be written: `meter.jpg`, `breaker.jpg`, and `placement.jpg`. Camera on device; photo library on simulator. No other photo slots exist.

### Cited Findings
- `attachMeterPhoto` writes JPEG quality 0.8 as `"meter.jpg"` and sets `electrical.meterPhotoFilename`. — [SurveyStore.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveyStore.swift)
- `attachBreakerPhoto` writes `"breaker.jpg"` and sets `electrical.breakerPhotoFilename`. — [SurveyStore.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveyStore.swift)
- `attachPlacementScreenshot` writes `"placement.jpg"` and sets `placement.screenshotFilename`. Triggered from AR `arView.snapshot` after `"Save placement and review"`. — [SurveyStore.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveyStore.swift); [PlacementARView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Placement/PlacementARView.swift)
- Files live under Documents/`Surveys`/`{session.id}/`. Images are orientation-normalized before write. — [SurveyStore.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveyStore.swift)
- Review labels: `"Round electric meter"`, `"Main disconnect or breaker"`, `"Placement screenshot"`; missing image text is `"{label}: not saved"`. — [ReviewView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Review/ReviewView.swift)
- Camera usage string: `"Base Site Survey uses the camera to photograph the electric meter and main breaker and to preview battery placement."` Photo library fallback: `"If the camera is unavailable, Base Site Survey can choose a photo from the library."` — [project.pbxproj](file:///Users/nikita/workspace/base-ar/BaseAR.xcodeproj/project.pbxproj)
- AGENTS.md intended Review contents: “Show both images, the confirmed breaker value, the solar answer, an AR placement screenshot, and what is still missing.” Matches the three-image design. — [AGENTS.md](file:///Users/nikita/workspace/base-ar/AGENTS.md)
- `CameraImagePicker` uses `UIImagePickerController` camera when available, else `.photoLibrary`; `allowsEditing = false`; uses `.originalImage`. — [CameraImagePicker.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Electrical/CameraImagePicker.swift)

### Inferences
- The app captures only the two electrical stills plus one AR snapshot. There is no slot for extra engineer-requested photos, house elevation, panel interior close-ups beyond the breaker photo, or a dedicated transfer-switch / gas-meter photo.

### Gaps
- JPEG quality, pixel size, and EXIF stripping beyond orientation fix were not measured at runtime. Filenames and write path are from source only.

---

## What eligibility checks does BaseRuleSet implement, and which stay unknown because evidence is missing?

### Takeaway
Seven required checks. Breaker and (sometimes) solar/200A can resolve from typed electrical fields. Meter, wall, and gas distances resolve only when AR marks/planes exist. Footprint and transfer-switch checks stay unknown in this build because their evidence fields are never set. Green (`PlacementTone.clear`) is therefore unreachable.

### Cited Findings

**Threshold constants** (`BaseRuleSet`): `austinMainBreakerRange = 150...200`; `panelAmpsForSolarOrTwoBatteries = 200`; `maxMeterDistanceFeet = 20.0`; `maxWallDistanceFeet = 1.0`; `minGasMeterDistanceFeet = 3.0`; `footprintSideFeet = 3.0`. — [BaseRuleSet.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Rules/BaseRuleSet.swift)

**The seven rules** (all `isRequired: true` in the helper that builds `RuleResult`):

| `id` | `title` | `requirement` | Evidence used | Unknown when |
|---|---|---|---|---|
| `austin-main-breaker` | `"Austin main breaker"` | `"In Austin the main breaker must be 150–200A."` | `mainBreakerAmperage` | amperage nil — explanation `"Main breaker amperage has not been confirmed."` |
| `solar-or-two-batteries` | `"Solar or two batteries"` | `"Solar, or two batteries, requires a 200A panel."` | `mainBreakerAmperage`, `hasSolar`, `plannedBatteryCount` | amperage nil; **or** amps ≠ 200 and solar/count not enough to decide |
| `planning-footprint` | `"3 ft × 3 ft footprint"` | `"Each battery needs a 3 ft × 3 ft planning footprint."` | `batteryPlaced`, `footprintIsClear` | battery not placed; **or** `footprintIsClear == nil` (“Clearance inside that pad was not measured.”) |
| `meter-distance` | `"Within 20 ft of the meter"` | `"The battery should be within 20 ft of the electric meter."` | `distanceToMeterFeet` | `"The battery and electric meter have not both been placed, so this distance was not measured."` |
| `wall-distance` | `"Within 1 ft of the wall"` | `"The battery should be within 1 ft of the wall."` | `distanceToWallFeet` | `"No wall plane was close enough to measure clearance from the battery."` |
| `gas-meter-clearance` | `"At least 3 ft from a gas meter"` | `"The battery must be at least 3 ft from a gas meter."` | `distanceToGasMeterFeet` | `"The gas meter was not marked, so clearance was not measured."` |
| `transfer-switch-space` | `"Transfer switch beside the meter"` | `"Leave space for a transfer switch on the wall beside the meter."` | `transferSwitchClearanceObserved` | `"Space for a transfer switch beside the meter was not measured."` |

— [BaseRuleSet.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Rules/BaseRuleSet.swift)

**Pass / conflict logic (implemented, evidence-gated)**

- Austin breaker: pass if amps in 150…200; conflict if confirmed and outside that range. — [BaseRuleSet.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Rules/BaseRuleSet.swift)
- Solar / two batteries: if amps == 200 → pass (“covers solar and a two-battery system”). If `hasSolar == true` **or** `(plannedBatteryCount ?? 0) >= 2` and amps ≠ 200 → conflict. If `hasSolar == false` **and** `plannedBatteryCount` exists and is `< 2` → pass (200A “does not apply”). Otherwise unknown: `"Confirmed main breaker is \(amps)A. Solar or planned battery count is still missing, so the 200A requirement cannot be decided."` — [BaseRuleSet.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Rules/BaseRuleSet.swift)
- Footprint: pass/conflict only if `footprintIsClear` is true/false. In this build that stays nil. — [BaseRuleSet.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Rules/BaseRuleSet.swift); [README.md](file:///Users/nikita/workspace/base-ar/README.md)
- Distances: pass/conflict from measured feet vs 20 / 1 / 3 ft thresholds. — [BaseRuleSet.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Rules/BaseRuleSet.swift)
- Transfer switch: pass/conflict only if `transferSwitchClearanceObserved` is set. Stays nil. — [BaseRuleSet.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Rules/BaseRuleSet.swift); [README.md](file:///Users/nikita/workspace/base-ar/README.md)

**Tone policy**

- Any required `conflict` → `PlacementTone.conflict` (red). Else every required check must be `pass` **and** `usedMeasuredEvidence` → `clear` (green). Otherwise `incomplete` (amber). — [EligibilityRule.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Rules/EligibilityRule.swift)
- Review copy: `"Green means every required check passed on measured evidence. Amber means a required check is still unknown. Red means a measured conflict. Footprint clearance and transfer-switch space are not measured in this build, so a placement with no conflict stays amber."` — [ReviewView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Review/ReviewView.swift)
- Tone UI titles: `"All required checks passed"`, `"Needs measurements"`, `"Measured conflict"`. Status titles: `"Pass"`, `"Conflict"`, `"Unknown"`. — [ToneStyle.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/ToneStyle.swift)
- AGENTS.md / README: green only when every required check has measured evidence and passes; amber = unknown; red = observed conflict. — [AGENTS.md](file:///Users/nikita/workspace/base-ar/AGENTS.md); [README.md](file:///Users/nikita/workspace/base-ar/README.md)

**`MissingInformation.list` strings (review “Still missing”)**

- `"Property address or identifier"`
- `"Phone location for the property: latitude, longitude, time, and horizontal accuracy"`
- `"Photo of the round electric meter"`
- `"Photo of the main disconnect or breaker"`
- `"Meter number"`
- `"Confirmed main breaker amperage"`
- `"Whether the home has solar"`
- `"Planned battery count"`
- `"AR placement screenshot"`
- `"AR placement of the battery"`
- if battery placed: `"Electric meter marked in AR, for the 20 ft check"`; `"Wall clearance. No nearby wall plane was measured"`; `"Gas meter marked in AR, for the 3 ft check"`; `"Clearance inside the 3 ft × 3 ft planning footprint"`
- always if unset: `"Space for a transfer switch beside the meter"`

Empty review copy: `"Nothing else is missing for this prototype."` — [SurveyEvaluating.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Rules/SurveyEvaluating.swift); [ReviewView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Review/ReviewView.swift)

### Inferences
- In a normal complete-looking walkthrough (address, GPS, both photos, meter number, amps, solar, battery + meter placed, wall seen), **at least** footprint and transfer-switch remain unknown; if solar is “No solar”, planned battery count also stays missing and the 200A rule stays unknown unless amps are 200. Gas stays unknown unless the user optionally marks it.
- Therefore `PlacementTone.clear` cannot occur with current stubs, matching Review and README.

### Gaps
- Runtime behavior of wall-distance measurement (how often a plane is “close enough”) was not executed on a device for this note. Logic is as coded: needs a vertical plane facing a battery bottom corner.
- Whether Base’s published articles treat gas-meter clearance as optional-if-no-gas vs required-to-mark was **not** taken from the live site (other researcher). In **this app**, unmarked gas ⇒ unknown, not pass.

---

## What does survey.json export include?

### Takeaway
Export encodes the entire `SurveySession` as pretty-printed, key-sorted JSON with ISO-8601 dates, filename `survey.json`. Sharing attaches that file plus any of `meter.jpg`, `breaker.jpg`, `placement.jpg` that exist. No network upload.

### Cited Findings
- `JSONSurveyExporter.write` uses `JSONEncoder` with `[.prettyPrinted, .sortedKeys]`, `dateEncodingStrategy = .iso8601`, writes `directory/survey.json`. Protocol comment: “Writes the local survey packet. No network.” — [SurveyExporting.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Review/SurveyExporting.swift)
- `SurveySession` is `Codable`, so JSON keys match property names: `schemaVersion`, `id`, `createdAt`, `propertyIdentifier`, `propertyLocationDisclaimer`, `prototypeDisclaimer`, `propertyLocation` (`latitude`, `longitude`, `timestamp`, `horizontalAccuracyMeters` or null), `electrical` (all six evidence fields), `placement` (all fourteen evidence fields), `ruleResults` (each result’s six-plus fields), `missingInformation`, `placementTone`. — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift); [SurveyExporting.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Review/SurveyExporting.swift)
- `SurveyStore.exportForSharing` refreshes assessment, writes JSON, then appends sibling files named by `meterPhotoFilename`, `breakerPhotoFilename`, `screenshotFilename` if present on disk. Review auto-exports in `.task` and offers `"Share survey"`. Saved-copy label: `"Saved on this iPhone as survey.json, with any photos beside it."` — [SurveyStore.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveyStore.swift); [ReviewView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Review/ReviewView.swift)
- Image bytes are **not** inlined in JSON; only filenames. In-memory `UIImage` properties are not encoded. — [SurveyStore.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveyStore.swift)
- README: “A local `survey.json` is saved next to the photos and can be shared from the review screen.” — [README.md](file:///Users/nikita/workspace/base-ar/README.md)

### Inferences
- A shared packet is: one JSON snapshot of the session (including current rule verdicts and missing list) plus up to three JPEGs. Stubbed fields appear as JSON `null`.
- Re-opening Review rewrites `survey.json` after a fresh evaluation.

### Gaps
- No sample `survey.json` was present in the repo to quote a real encoded file. Key names above follow Swift `Codable` synthesized keys (property names), which is the encoder used.

---

## What does AGENTS.md / README.md say Base guidance requires (breaker, solar, footprint, meter/wall/gas distances, transfer switch)?

### Takeaway
The project treats Austin Base guidance as seven configurable checks: 150–200A main breaker; 200A panel if solar or two batteries; 3 ft × 3 ft footprint; within 20 ft of the meter; within 1 ft of the wall; at least 3 ft from a gas meter; space for a transfer switch beside the meter. Official URLs are cited but not re-scraped here.

### Cited Findings
- AGENTS.md “Configurable Base guidance (Austin)”: “Main breaker 150–200A.” “Solar or two batteries requires a 200A panel.” “3 ft × 3 ft battery footprint.” “Within 20 ft of the meter.” “Within 1 ft of the wall.” “At least 3 ft from a gas meter.” “Space for a transfer switch beside the meter.” Implement only checks supported by actual captured evidence. Outcomes: **pass, conflict, or unknown**. — [AGENTS.md](file:///Users/nikita/workspace/base-ar/AGENTS.md)
- README repeats the same siting numbers: “Austin main breakers 150–200A, 200A when the home has solar or two batteries, a 3 ft × 3 ft footprint, within 20 ft of the meter, within 1 ft of the wall, at least 3 ft from a gas meter, and space for a transfer switch beside the meter.” — [README.md](file:///Users/nikita/workspace/base-ar/README.md)
- Official references listed in both files (not fetched for this app-side note): https://www.basepowercompany.com/specs/core ; https://help.basepowercompany.com/en/articles/10280705 ; https://help.basepowercompany.com/en/articles/10280641 — [AGENTS.md](file:///Users/nikita/workspace/base-ar/AGENTS.md); [README.md](file:///Users/nikita/workspace/base-ar/README.md)
- Code comment on `BaseRuleSet`: “Austin main-breaker range and the solar / two-battery panel rule come from Base's electrical requirements. Distances and the 3 ft pad come from Base's siting guidance.” — [BaseRuleSet.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Rules/BaseRuleSet.swift)
- Battery placeholder size in AGENTS/README/code: about **30.68 in W × 35.9 in H × 22 in D**, with a separately visible **3 ft × 3 ft** planning pad. Constants: `BatteryGeometry.widthInches = 30.68`, `heightInches = 35.9`, `depthInches = 22`. Placement readout: `"Preview 30.68 in W × 35.9 in H × 22 in D, on a 3 ft × 3 ft pad."` — [AGENTS.md](file:///Users/nikita/workspace/base-ar/AGENTS.md); [BatteryGeometry.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Placement/BatteryGeometry.swift); [PlacementARView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Placement/PlacementARView.swift)
- Product framing: Base asks homeowners for electrical and site photos; engineers review and may request more evidence. App goal: preliminary survey + AR placement preview. Explicitly out of scope unless a later task asks: ERCOT data, satellite imagery, automatic equipment detection, Base integration, production-grade permitting. — [AGENTS.md](file:///Users/nikita/workspace/base-ar/AGENTS.md); [README.md](file:///Users/nikita/workspace/base-ar/README.md)
- Intended capture flow fields (AGENTS): Home — address / property identifier + phone property GPS. Meter — round meter photo + meter number. Breaker — main disconnect/breaker photo, amperage, solar unanswered/no/yes (meter number and amperage stay distinct). Placement — AR ground/wall planes, place/move/rotate Core, 3×3 pad, mark meter, LiDAR mesh when supported. Review — both images, confirmed breaker, solar, AR screenshot, missing list, local JSON, shareable. — [AGENTS.md](file:///Users/nikita/workspace/base-ar/AGENTS.md)
- Next-three-tasks (README) still pending: Vision OCR + confirmed `plannedBatteryCount`; measure `footprintIsClear` and `transferSwitchClearanceObserved`; extend `BaseRuleSet` only when those measurements exist. — [README.md](file:///Users/nikita/workspace/base-ar/README.md)

### Inferences
- The app’s rule IDs are a direct encoding of the AGENTS.md Austin list. Gaps vs **project-intended** Base guidance are therefore: (1) two-battery count not collected; (2) footprint clearance not measured (pad is visual only); (3) transfer-switch space not measured; (4) OCR not connected; (5) green preview reserved until those exist.

### Gaps
- This note does **not** independently verify the three Base URLs against live copy. Use the parallel website-form research for that. Project text is the source of “intended guidance” here.

---

## What disclaimers does the app make (GPS is not battery position, not a final approval)?

### Takeaway
Two canonical session strings are reused on intro, hub, home, and review. Placement and review add extra GPS-vs-battery and “not installation approval” lines. System permission prompts repeat the GPS disclaimer.

### Cited Findings
- Canonical prototype disclaimer (stored on every session as `prototypeDisclaimer`): `"Preliminary survey only. This is not an electrical inspection, a code review, or installation approval."` Shown on Intro, Hub, Home information, and Review (orange callout). — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift); [ContentView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/ContentView.swift); [ReviewView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Review/ReviewView.swift)
- Canonical location disclaimer (`propertyLocationDisclaimer` / `locationDisclaimer`): `"Latitude, longitude, timestamp, and horizontal accuracy are the phone's reported property location, not the battery position."` Shown on Home information Location section and Review location summary (whether or not a fix exists). — [SurveySession.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Survey/SurveySession.swift); [ContentView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/ContentView.swift); [ReviewView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Review/ReviewView.swift)
- Review AR section extra line: `"GPS above is the phone's property fix, not where the battery was placed."` — [ReviewView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Review/ReviewView.swift)
- Placement readout: `"Green only when every required check has measured evidence and passes. This is not installation approval."` Unsupported-AR: `"AR placement needs a physical iPhone."` — [PlacementARView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Placement/PlacementARView.swift)
- Intro body (not the static constant): `"Take photos of your home, meter, and breaker, then see where a Base Core could sit outside. An engineer may still ask for more photos."` Splash: `"Base Site Survey"` / `"A first look at your home for a Base Power battery"`. Intro title: `"Let’s get your battery placement"`. — [ContentView.swift](file:///Users/nikita/workspace/base-ar/BaseAR/ContentView.swift)
- Info.plist location prompt: `"Base Site Survey records this phone location for the property. This is not the battery position."` — [project.pbxproj](file:///Users/nikita/workspace/base-ar/BaseAR.xcodeproj/project.pbxproj)
- AGENTS.md: “It is a prototype. Never present it as final electrical, code, or permitting approval.” “GPS is the phone’s property fix … Do not describe it as the precise battery position.” — [AGENTS.md](file:///Users/nikita/workspace/base-ar/AGENTS.md)
- README: “It is not an electrical inspection or installation approval.” Setup: “Location is the phone’s property fix (latitude, longitude, time, and reported horizontal accuracy). It is not the battery position.” — [README.md](file:///Users/nikita/workspace/base-ar/README.md)
- `PropertyLocationProvider` file comment: “One-shot property fix. Callers must not treat this as the battery coordinate.” — [PropertyLocationProvider.swift](file:///Users/nikita/workspace/base-ar/BaseAR/Location/PropertyLocationProvider.swift)

### Inferences
- Disclaimer coverage is consistent: GPS ≠ battery pose; output ≠ approval. Those strings are also exported inside `survey.json`.

### Gaps
- No other legal/permitting copy (utility, HOA, AHJ) appears in Swift UI strings searched for this note.

---

## First-pass gap list (app vs project-intended Base guidance)

### Takeaway
Against AGENTS.md/README Austin guidance, the app **encodes all seven checks** but **cannot satisfy two of them at all** (footprint clearance, transfer-switch space) and **cannot fully decide** solar-or-two-batteries unless the breaker is already 200A or solar is yes. Several product fields the model already has are unasked.

### Cited Findings
- Stubbed, per README “What is stubbed”: OCR always nil; `plannedBatteryCount` not asked (below 200A the solar/two-battery check stays unknown until count exists; 200A satisfies it); `footprintIsClear` and `transferSwitchClearanceObserved` never set, so those required checks stay unknown and the preview does not turn green; no ERCOT, satellite, auto detection, Base backend, or permitting logic. — [README.md](file:///Users/nikita/workspace/base-ar/README.md)
- Intended but only partially collected vs AGENTS hub: Home address + GPS — implemented. Meter photo + number — implemented (number manual). Breaker photo + amps + solar — implemented. Placement size + pad + meter mark — implemented visually; wall/gas distances implemented when marks/planes exist; LiDAR mesh optional. Review images + breaker + solar + screenshot + missing + JSON share — implemented. Forced wizard “may come later.” — [AGENTS.md](file:///Users/nikita/workspace/base-ar/AGENTS.md); [README.md](file:///Users/nikita/workspace/base-ar/README.md)

### Inferences
First-pass gaps a report writer can treat as **app-side vs intended Base guidance** (not vs the live website form):

1. **Planned battery count** — required by the 200A-if-two-batteries rule and listed in `MissingInformation`, but no UI. Blocks a clean pass when solar is no and breaker is 150–199A.
2. **Footprint clearance** — guidance requires 3×3; app draws the pad but never sets `footprintIsClear`. Check stays unknown; green locked.
3. **Transfer-switch space beside the meter** — required check; never asked or measured. Stays unknown; green locked.
4. **Meter OCR** — intended (`MeterNumberRecognizing`); stub returns nil; user must type.
5. **Gas meter** — required 3 ft check, but marking is optional (“if you can see one”). Unmarked ⇒ unknown, not “N/A / pass.”
6. **Wall within 1 ft** — implemented only if ARKit reports a usable vertical plane; otherwise unknown (“No nearby wall plane”).
7. **GPS vs battery** — property fix only; no geo field for the placed Core (AR `PlacementAnchor` is local tracking space, not lat/long).
8. **Photos** — only meter, breaker, one AR screenshot. AGENTS says engineers may request more evidence; there is no extra-photo flow.
9. **Address** — one free-text `propertyIdentifier`, not structured street/city/zip or utility account fields.
10. **Out of scope by design** (do not treat as accidental omissions unless the website researcher finds the live form requires them): ERCOT, satellite, automatic equipment detection, accounts/backend, production permitting, step-locked wizard.

### Gaps
- Crosswalk to Base’s **live website form field names** is out of scope (assigned to the other researcher). Do not assume the seven Austin checks are the full Base intake form.
- No device run was performed for this inventory; “never set” is from source grep and README, not a live Instruments trace.
