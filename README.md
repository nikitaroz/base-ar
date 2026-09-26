# Base Site Survey

A small iPhone app for a preliminary Base Power site survey. It collects meter and breaker photos, previews a Base Core in AR, and writes a local review. It is not an electrical inspection or installation approval.

The Xcode target is still `BaseAR`. The home-screen name is **Base Site Survey**.

## Guided survey branch

This branch implements a nine-step guided capture flow, wider context photos, explicit OCR/value confirmation, safe deferrals, local draft resume, and targeted review loops. See [the end-to-end workflow and Mermaid diagram](docs/guided-survey-workflow.md) and [validation / iPhone acceptance checklist](docs/guided-survey-validation.md).

The workflow document is the current behavior reference for this branch; the older feature notes below describe the original hub implementation. Native Xcode compilation and physical-device validation are still required.

## Xcode and device setup

Each teammate does this once. `git pull` won't disturb any of it — signing config lives in files git ignores.

1. **Sign in to Xcode with your Apple ID.**
   Xcode → Settings → Accounts → **+** → Apple ID. This downloads your Apple Development certificate to the keychain. Without this step Xcode has no way to sign the app, and every build will fail with *"No Account for Team … / No profiles for …"*.
2. **Generate your local signing config.**
   From the repo root:
   ```sh
   ./scripts/bootstrap-signing.sh
   ```
   The script reads the Team ID off the certificate you just installed, derives a bundle ID like `com.<your-username>.BaseAR`, and writes it to `Config/Local.xcconfig`. That file is gitignored, so it is per-machine and never shared. If you'd rather set it up by hand, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and fill in the two lines.
3. **Open the project and let Xcode fetch a provisioning profile.**
   Open `BaseAR.xcodeproj`. In *Signing & Capabilities* on the `BaseAR` target, confirm **Automatically manage signing** is checked. The first build (or Product → Clean Build Folder → Build) will pull down a profile for your bundle ID.
4. **On your iPhone, trust the developer profile.**
   First device install: Settings → General → VPN & Device Management → tap your developer profile → **Trust**.

That's the whole loop. From this point on, `git pull` just applies code — signing is untouched.

## Running the app

Select the `BaseAR` scheme and a physical iPhone running iOS 17 or later. Allow camera when a photo task starts, and allow While Using location when Site Measurements opens. Location is the phone's property fix (latitude, longitude, time, and reported horizontal accuracy) — it is not the battery position. Run outdoors, or somewhere the phone can see the ground and a wall.

AR placement needs a physical iPhone. The simulator can open the survey, take library photos, and reach review, but world tracking stays unavailable there.

For a signing-free simulator sanity build (useful in CI or a clean checkout):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project BaseAR.xcodeproj \
  -scheme BaseAR \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

For a device build from the command line (after step 1 above):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project BaseAR.xcodeproj \
  -scheme BaseAR \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  -allowProvisioningUpdates build
```

If `xcodebuild` reports it's using Command Line Tools instead of Xcode, either prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (as above) or run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` once.

## Project structure

- `BaseAR/Survey` — shared `SurveySession` and `SurveyStore`
- `BaseAR/Electrical` — meter and breaker capture, live scan, and photo OCR
- `BaseAR/Placement` — AR placement, battery size, measurements
- `BaseAR/Rules` — `EligibilityRule`, `BaseRuleSet`, pass / conflict / unknown
- `BaseAR/Review` — review screen and JSON export
- `BaseAR/Location` — one-shot property location

`SurveyStore` is the composition root. The three workstreams meet at `MeterNumberRecognizing`, `PlacementMeasuring`, and `SurveyEvaluating`.

## What works

- Welcome → nine-step guide: safety, home, utility, meter, meter context, main disconnect, panel context, AR placement, and review. Step navigation, explicit deferrals and local draft resume are available.
- Home and personal info stores a name, email, phone, property address or identifier, own or rent, solar, portable generator, whole-home standby generator, existing whole-home battery, planned battery count (1 or 2), and the phone’s property location fix when allowed. Those choices are radio buttons. The fix requests precise location and is shown on a map. Address suggestions come from MapKit as you type.
- Photograph the round meter and the main disconnect from separate hub tiles. The meter number and breaker amperage are different fields. On an iPhone, Scan highlights the number in a card-style frame and saves that photo. A normal photo can also fill an empty field. The typed value is the one that is kept.
- Outdoor `ARView` with horizontal and vertical plane detection. One scan: point at the electric meter, step back about 10 steps, and look left, right, and along the wall. Then point at the breaker panel and do the same around that box. Done stays off until both looks finish. Clear meter or Clear panel undoes a bad lock. Live detection boxes stay on the camera. The scan hides any battery or equipment cubes already in the scene and does not drop new ones. Meter height and whether the meter and panel share a wall still come from the locks.
- LiDAR occlusion when the phone supports it. Placement still uses plane raycasts without LiDAR. The mesh is not drawn on screen.
- Meter height is the vertical rise from the ground under the meter to the meter face. Whether the meter and panel share a wall comes from the two wall locks. The step-back counts distance and a pan left, right, and along the wall, so the mesh can cover the area around each lock. Opening the scan does not erase a battery, gas, or working-space position already saved on the scene.
- Battery-to-meter, wall, and gas distances, plus the 3 ft pad, working space, and transfer-switch box, still exist in the measurer. This scan does not place those boxes, so those checks stay unmeasured.
- Review is reachable from the hub (and after placement). It leads with grouped next actions, then provides collapsible property, electrical, placement, and rule details with edit links.
- A local `survey.json` is saved next to the photos and can be shared from the review screen. When the phone reconstructed a LiDAR mesh, that share also includes `scene.ply` (meters, AR world, camera colors, plus the battery, footprint, equipment marks, and distance bars colored pass/conflict/unknown; the distances are listed in the header comments). Open it in MeshLab, CloudCompare, or Blender.
- The battery preview is green only when every required check passed on measured evidence. Unknown stays amber. A measured conflict turns it red.

Siting numbers follow Base’s published guidance: Austin main breakers 150–200A, 200A when the home has solar or two batteries, a 3 ft × 3 ft footprint, within 20 ft of the meter, within 1 ft of the wall, at least 3 ft from a gas meter, and space for a transfer switch beside the meter.

- https://www.basepowercompany.com/specs/core
- https://help.basepowercompany.com/en/articles/10280705
- https://help.basepowercompany.com/en/articles/10280641

## Equipment detector

`BaseAR/Placement/EquipmentScan.mlpackage` is YOLO26n fine-tuned at 640 px to find the electric meter (class 0) and breaker panel (class 1). Training data lives in `training/`, which is gitignored, so each machine rebuilds it:

1. `uv venv --python 3.12 training/.venv && uv pip install --python training/.venv/bin/python ultralytics coremltools "git+https://github.com/ultralytics/CLIP.git"`
2. `python3 scripts/fetch_commons.py`: about 400 CC-licensed Wikimedia Commons photos, with credits in `training/raw/sources.csv`.
3. Put hand-labeled site photos in `training/site/`, each with a YOLO `.txt` label beside it. They are repeated three times in training, and four are held out for validation (`VAL_STEMS` in `autolabel.py`).
4. `training/.venv/bin/python scripts/autolabel.py`: YOLOE-26l drafts meter boxes for the Commons photos. Check `training/review/` and list bad images in `training/exclude.txt`. Commons panels are skipped because they are European switchboards.
5. `training/.venv/bin/python scripts/train_equipment.py`: trains on the Apple GPU and writes the Core ML package into the app.

Every panel example so far comes from one demo wall. Expect weaker panel detection at other houses until more site photos are added.

## How this maps to Base

Base’s public request is two steps, researched 26 September 2026. [Get Started](https://www.basepowercompany.com/get-started) collects ownership, energy setup, address, and contact. Engineers later judge the site from a [photo kit](https://help.basepowercompany.com/en/articles/10280641): meter with a legible number, wide shots around the meter (surrounding, left, right, adjacent wall, behind the fence), breaker box, disconnect amperage, and breaker-area context. The longer comparison is in `reports/Base battery form vs app.md`.

This app already asks the typed home-form questions and stores one meter photo, one breaker photo, typed meter number and amperage, and an AR screenshot. It does not yet capture Base’s wide meter-yard photos. Meter height (6 ft), working space in front of the meter and panel (about 30 × 36 in), and whether the meter and panel share a wall belong to AR placement, not the home form. The survey stays on the phone.

## What is stubbed

- AR measurements are preliminary raycast estimates and still need physical-device field verification; they do not replace an installer measurement.
- The wide photo kit (left, right, surrounding, adjacent wall, behind the fence, breaker-area context) is not captured.
- No ERCOT data, satellite imagery, Base backend, or permitting logic. Meter and panel boxes come from an on-device model; they are not an electrical inspection.

## Next three tasks

1. **Electrical capture / OCR.** Done. Vision reads a meter number and main-breaker amperage from a photo, and a live card-style scan can fill either field. The typed value is still the one the user accepts.
2. **AR placement and measurements.** Measure pad clearance into `footprintIsClear`, and transfer-switch space beside the meter into `transferSwitchClearanceObserved`. Add meter height, front working space, and whether the meter and panel share a wall. Tighten wall distance against the LiDAR mesh when it exists.
3. **Rules and review export.** Extend `BaseRuleSet` only when those measurements exist. Keep each check at pass, conflict, or unknown, and keep green reserved for a full set of measured passes.
