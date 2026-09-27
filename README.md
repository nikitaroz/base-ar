<div align="center">

<img src="docs/media/app-icon-256.png" alt="Base Site Survey app icon" width="128" height="128" />

# Base Site Survey

A native iPhone app that turns a homeowner's phone into a preliminary Base Power site survey — collecting electrical evidence, capturing a LiDAR scan of the meter and breaker panel, previewing a Base Core battery in AR against Base's published clearances, and exporting a portable review packet.

Not an electrical inspection, code review, or installation approval.

</div>

## Demo

https://github.com/nikitaroz/base-ar/raw/main/docs/media/demo.mp4

> If your Markdown viewer does not render the video inline, open [`docs/media/demo.mp4`](docs/media/demo.mp4) directly.

## Contents

- [What it does](#what-it-does)
- [Feature tour](#feature-tour)
- [Architecture](#architecture)
- [Getting started](#getting-started)
- [Running the app](#running-the-app)
- [Export packet](#export-packet)
- [Rules engine](#rules-engine)
- [On-device equipment detector](#on-device-equipment-detector)
- [Site Scan Viewer (browser tool)](#site-scan-viewer-browser-tool)
- [How this maps to Base's intake](#how-this-maps-to-bases-intake)
- [What's stubbed](#whats-stubbed)
- [References](#references)

## What it does

Base Power asks homeowners for a home-form of typed answers and a photo kit of the meter yard and breaker panel; engineers then judge the site. This app is a guided phone-side stand-in for that flow. It:

1. Walks the homeowner through the same typed answers Base asks (with a MapKit-completed address, an optional GPS fix, and a battery-count decision helper backed by ERCOT price samples).
2. Captures the electric meter photo, reads the meter number and main-breaker amperage with Vision OCR, and lets the user hand-correct either.
3. Runs an outdoor AR scan that locks the meter and breaker panel using an on-device YOLO detector, reconstructs a LiDAR mesh, and records posed keyframes with depth.
4. Previews a to-scale Base Core cabinet in AR, tinted **green / amber / red** against Base's Austin siting rules using only measured evidence.
5. Writes `survey.json` and a `BaseSiteSurvey-<date>.zip` you can share; a companion browser viewer maps every square-foot of the scan for candidate battery placements.

## Feature tour

### Home & personal info
- Name, email, phone, and address (with MapKit typeahead suggestions).
- Own / rent, existing solar, portable generator, whole-home standby generator, existing whole-home battery — all radio-buttoned to match Base's Get Started form.
- Planned battery count (1 or 2) with an inline **battery-count decision card**: capacity, backup hours at ~3 kW load, and annualized wholesale-arbitrage $/day derived from an embedded ERCOT price sample keyed to the property's load zone.
- One-shot property GPS fix (lat, lon, timestamp, reported horizontal accuracy) shown on a map with an accuracy ring. Precise-location is requested; if the user only grants approximate, that's what is recorded.

### Electrical capture
- Round-meter photo capture through a native camera picker; the JPEG is baked upright (no EXIF-only rotation).
- **Live label scanner** overlays the camera preview with a card-style highlight around the meter nameplate, aggregating Vision text observations across frames until the meter number stabilizes.
- Photo-fallback OCR: attaching an existing library photo also runs Vision recognition on the still.
- Typed main-breaker amperage is the value of record — OCR is a suggestion, not an override.

### AR placement and site scan
- Outdoor `ARView` with horizontal and vertical plane detection, LiDAR mesh occlusion on supported devices, and plane-raycast placement on devices without LiDAR.
- **One guided scan** covers both the meter and the breaker panel: point at the meter, step back ~10 steps, pan left / right / along the wall; then repeat around the panel. A live progress readout gates the Done button until both looks complete.
- **On-device YOLO detector** (`EquipmentScan.mlpackage`, YOLO26n fine-tuned at 640 px) draws candidate meter / panel boxes on the camera at ≥0.30 confidence and auto-locks at ≥0.45. Users can also lock by holding the center reticle steady, or tap to mark manually. Every lock records its source (detector / hold / tap).
- **Battery preview**: a to-scale Base Core cabinet (30.68 in W × 35.9 in H × 22 in D) is placed on the ground; a separate 3 ft × 3 ft planning footprint and a transfer-switch working space beside the meter are drawn as overlays.
- Live tint: the cabinet is **green** only when every required rule passes on measured evidence, **amber** if anything is unknown, **red** on an observed conflict.
- **Keyframe recorder** captures posed camera photos + depth + intrinsics during the scan: an anchor frame at every meter / panel lock, then a new frame after ~0.4 m of movement or a ~20° turn, only while the phone is steady. Up to 120 frames per scan, all rotated upright to match how the phone was held.

### Review and export
- Reachable from the hub or automatically after placement.
- Grouped next actions at the top; collapsible cards for property, electrical, placement, and every rule result, each with a direct edit link back to its section.
- `Share` writes one zip — `BaseSiteSurvey-<yyyy-MM-dd-HHmm>.zip` — unpacking to a single folder with the survey, photos, LiDAR mesh, and the full keyframe stream. See [Export packet](#export-packet).

## Architecture

```
BaseAR/
├─ Survey/        SurveySession · SurveyStore (composition root) · ToneStyle
├─ Onboarding/    Splash + 5-page onboarding
├─ Location/      PropertyLocationProvider · MapKit AddressCompleter · map view
├─ Electrical/    Camera picker · LiveLabelScanner · Vision OCR (meter number
│                 + breaker amperage) · MeterNumberRecognizing protocol
├─ Placement/     PlacementARView · PlacementMeasuring · KeyframeRecorder
│                 EquipmentDetecting (Core ML) · BatteryCatalog / Geometry
│                 EquipmentScan.mlpackage (YOLO26n)
├─ Grid/          ERCOTLoadZone · LoadZoneLookup · ERCOTPriceSample
│                 GridService · BatteryCountDecision + card
├─ Rules/         EligibilityRule · BaseRuleSet · SurveyEvaluating
└─ Review/        ReviewView · SurveyExporting (zip + PLY writer)
```

`SurveyStore` is the composition root. The three parallel workstreams meet at three protocols so they can be developed independently and mocked in isolation:

| Workstream | Owns | Protocol |
|---|---|---|
| Electrical capture / OCR | Meter photo, meter number, breaker amperage | `MeterNumberRecognizing` |
| AR placement & measurements | Battery position, meter / panel / gas anchors, distances, LiDAR mesh, keyframes | `PlacementMeasuring` |
| Rules & review export | Rule outcomes, tone, zip / PLY export | `SurveyEvaluating` |

Every capability is Apple-frameworks only: SwiftUI, ARKit, RealityKit, Vision / VisionKit, Core ML, Core Location, MapKit. No backend, no accounts, no third-party dependencies.

## Getting started

Each teammate does this once per Mac. `git pull` never disturbs signing — those files are gitignored.

1. **Sign in to Xcode with your Apple ID.** Xcode → Settings → Accounts → **+** → Apple ID. Without this Xcode has no cert to sign with and every device build fails with *"No Account for Team … / No profiles for …"*.
2. **Generate your local signing config.**
   ```sh
   ./scripts/bootstrap-signing.sh
   ```
   Reads the Team ID off the certificate you just installed, derives a bundle ID like `com.<your-username>.BaseAR`, and writes it to `Config/Local.xcconfig` (gitignored). To do it by hand: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and fill in the two lines.
3. **Open `BaseAR.xcodeproj`** and confirm *Automatically manage signing* is checked on the `BaseAR` target. The first build pulls down a provisioning profile.
4. **On device, trust the developer profile** the first time: Settings → General → VPN & Device Management → tap your profile → **Trust**.

## Running the app

Select the `BaseAR` scheme and a physical iPhone running **iOS 17+**. Grant camera when a photo task starts, and *While Using* location when Site Measurements opens.

AR placement requires a device — the simulator can walk the survey and reach review, but world tracking stays unavailable there.

**Signing-free simulator build** (useful in CI or a clean checkout):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project BaseAR.xcodeproj \
  -scheme BaseAR \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

**Device build from the command line** (after step 1 above):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project BaseAR.xcodeproj \
  -scheme BaseAR \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  -allowProvisioningUpdates build
```

If `xcodebuild` says it is using Command Line Tools instead of Xcode, either prefix as above or run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` once.

## Export packet

Sharing from the review screen writes a single zip that unzips to one folder:

```
BaseSiteSurvey-2026-09-26-2041/
├─ survey.json          Full SurveySession (personal, electrical, placement,
│                       rule results, tone, ERCOT grid context, device provenance)
├─ meter.jpg            The captured meter photo (upright JPEG)
├─ placement.jpg        AR screenshot at the time of Save
├─ scene.ply            ASCII LiDAR mesh — per-vertex RGB from camera,
│                       per-face ARKit label (wall / floor / window / door /
│                       ceiling / …), and header `mark` lines for the meter,
│                       panel, gas meter, battery, footprint, and distance bars,
│                       coloured pass / conflict / unknown
└─ capture/
   ├─ frames.json       Per-frame index, timestamp, intrinsics, camera→world
   │                    pose, exposure, orientation — in the same AR world as
   │                    scene.ply
   ├─ frames/NNNNNN.jpg Upright rotated JPEGs (no EXIF)
   ├─ NNNNNN.depth.bin  Raw Float32 little-endian depth in meters
   └─ NNNNNN.conf.bin   UInt8 depth confidence (0 low · 1 medium · 2 high)
```

`scene.ply` opens directly in MeshLab, CloudCompare, or Blender. The keyframe stream is enough to re-photogrammetry the yard or run a downstream 3D pipeline.

## Rules engine

Every eligibility check returns `pass`, `conflict`, or `unknown`, and records whether it used **measured** or **attested** evidence. The battery preview turns green only when every required check passes on measured evidence.

| # | Check | Threshold |
|---|---|---|
| 1 | Austin main breaker | 150–200 A |
| 2 | Solar or two batteries | 200 A panel |
| 3 | Battery footprint | 3 ft × 3 ft clear |
| 4 | Distance to meter | ≤ 20 ft |
| 5 | Distance to wall | ≤ 1 ft |
| 6 | Not in front of a window | Wall clear where cabinet backs onto |
| 7 | Equipment working space | 30 in × 36 in clear |
| 8 | Distance to gas meter | ≥ 3 ft |
| 9 | Meter height | 3–6 ft |
| 10 | Meter & panel share a wall | Two wall locks aligned |
| 11 | Transfer-switch space beside meter | ≈ 13 in × 3 ft × 30 in |
| 12 | Front working space clear | 30 in × 36 in ahead of cabinet |

Austin thresholds live in `BaseAR/Rules/BaseRuleSet.swift` and follow Base's public guidance (linked below).

## On-device equipment detector

`BaseAR/Placement/EquipmentScan.mlpackage` is a YOLO26n model fine-tuned at 640 px to find the electric meter (class 0) and breaker panel (class 1). It runs live on the AR camera stream; boxes are drawn at ≥ 0.30 confidence and auto-lock at ≥ 0.45.

Training assets live in `training/` (gitignored) so each machine rebuilds:

1. `uv venv --python 3.12 training/.venv && uv pip install --python training/.venv/bin/python ultralytics coremltools "git+https://github.com/ultralytics/CLIP.git"`
2. `python3 scripts/fetch_commons.py` — ~400 CC-licensed Wikimedia Commons photos, credits in `training/raw/sources.csv`.
3. Drop hand-labeled site photos into `training/site/` with a YOLO `.txt` label beside each. They're triplicated in training; four are held out for validation (`VAL_STEMS` in `autolabel.py`).
4. `training/.venv/bin/python scripts/autolabel.py` — YOLOE-26l drafts meter boxes for the Commons photos. Review `training/review/` and list bad images in `training/exclude.txt`. Commons panels are skipped (European switchboards).
5. `training/.venv/bin/python scripts/train_equipment.py` — trains on the Apple GPU and writes the Core ML package into the app.

Every panel example so far comes from one demo wall — expect weaker panel detection at other houses until more site photos are added.

## Site Scan Viewer (browser tool)

`tools/viewer/` is a React + Vite + Tailwind + three.js viewer that opens an exported survey zip (or loose `scene.ply` + `survey.json`) and answers one question: **where on this scan can a Base Core actually stand?**

- Small coloured squares cover scanned ground within 20 ft of the meter — green (candidate), red (conflict, hover for which check), amber (needs more scan), gray (why not), pale amber (surface scanned too low to confirm as a house wall).
- Select any square to see the full 3 ft × 3 ft footprint plus both side-clearance regions with every rule result for that spot.
- View toggles: camera-colour vs ARKit labels, 3D vs top-down, grid, floor layer, cutaway above 2.2 m, ceiling.
- Runs entirely in the browser — nothing uploads. `npm run build` inlines everything into one ~1 MB `dist/index.html` you can email to a reviewer.

See [`tools/viewer/README.md`](tools/viewer/README.md) for details.

## How this maps to Base's intake

Base's public request is two steps (researched 2026-09-26). [Get Started](https://www.basepowercompany.com/get-started) collects ownership, energy setup, address, and contact. Engineers later judge the site from a separate [photo kit](https://help.basepowercompany.com/en/articles/10280641): meter with a legible number, wide shots around the meter (surrounding, left, right, adjacent wall, behind the fence), breaker box, disconnect amperage, and breaker-area context. Full comparison: [`reports/Base battery form vs app.md`](reports/Base%20battery%20form%20vs%20app.md).

This app already asks Base's typed home-form questions and stores one meter photo, a typed meter number, a typed breaker amperage, an AR screenshot, and a full LiDAR + keyframe capture. It does **not** yet capture Base's wide meter-yard compositions. Meter height, front working space, and shared-wall status are AR measurements, not home-form answers. Everything stays on the phone.

## What's stubbed

- **AR measurements** are preliminary raycast + LiDAR estimates and still need physical-device field verification; they do not replace an installer measurement.
- **Wide photo kit** (left, right, surrounding, adjacent wall, behind the fence, breaker-area context) is not yet captured — the keyframe recorder captures posed frames but not the specific compositions Base asks for.
- **No Base backend, no ERCOT live feed, no permitting logic.** ERCOT prices are an embedded sample keyed to load zone; the meter and panel boxes come from an on-device model and are not an electrical inspection.

## References

- Base Core specs: <https://www.basepowercompany.com/specs/core>
- Base site requirements: <https://help.basepowercompany.com/en/articles/10280705>
- Base photo kit: <https://help.basepowercompany.com/en/articles/10280641>
- Detailed home-form vs app comparison: [`reports/Base battery form vs app.md`](reports/Base%20battery%20form%20vs%20app.md)
- Agent / build conventions: [`AGENTS.md`](AGENTS.md)
