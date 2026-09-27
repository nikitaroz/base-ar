# Base Site Survey

An iPhone prototype for a preliminary Base Power site survey. It asks the home questions, scans the electric meter and breaker panel with the camera, previews a Base Core beside the meter in AR, and writes a local review you can share. It is not an electrical inspection, a code review, or installation approval.

The Xcode target is `BaseAR`. The home-screen name is **Base Site Survey**. Agent and team rules are in `AGENTS.md`.

## First-time setup (once per Mac)

Signing lives in files git ignores, so `git pull` never disturbs it.

1. **Sign in to Xcode with your Apple ID.** Xcode → Settings → Accounts → **+** → Apple ID. Without it every device build fails with *"No Account for Team … / No profiles for …"*.
2. **Generate your local signing config.** From the repo root run `./scripts/bootstrap-signing.sh`. It reads your Team ID from the installed certificate, derives a bundle ID like `com.<your-username>.BaseAR`, and writes the gitignored `Config/Local.xcconfig`. It never overwrites an existing file. To do it by hand, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and fill in the two lines. Never put a team ID in `project.pbxproj`.
3. **Open `BaseAR.xcodeproj`**, keep *Automatically manage signing* on, and build once so Xcode fetches a profile.
4. **On the iPhone, trust the developer profile** on first install: Settings → General → VPN & Device Management → your profile → **Trust**.

## Building and running

Use a physical iPhone on iOS 17 or later, outdoors or anywhere the phone can see the ground and a wall. Allow camera, and While Using location on Home Info. The location is the phone's property fix, not the battery position. The simulator can walk Home Info and Review, but has no world tracking.

Signing-free build check (paste its `BUILD SUCCEEDED` in every PR):

```sh
xcodebuild -project BaseAR.xcodeproj -scheme BaseAR \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build \
  2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```

Device build from the command line (after setup):

```sh
xcodebuild -project BaseAR.xcodeproj -scheme BaseAR \
  -destination 'generic/platform=iOS' -configuration Debug \
  -allowProvisioningUpdates build
```

If `xcodebuild` picks Command Line Tools, prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` or run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` once.

Install only from a commit, never from uncommitted patches. A black camera is not a mirroring or Device Hub problem: the back lens is covered or sees nothing, and the bottom line says so.

## The three steps

Splash → Welcome → **Home Info** → **Live Survey** → **Review & Export**.

1. **Home Info.** First launch opens a short onboarding wizard, then the full form: name, email, phone, address with MapKit suggestions, own or rent, solar, portable generator, standby generator, existing whole-home battery, planned batteries (1 or 2), the panel bus rating when solar or two batteries apply, and "Gas meter outside: Yes / No / Not sure". The property location fix shows on a map with its accuracy circle.
2. **Live Survey.** The camera with no top bar and exactly two lines of text:
   - the **top** line is the current job, and it changes as each job completes;
   - the **bottom** line is live feedback with a small animated graphic ("Point at the meter", "Get closer", "Hold still", "Found the meter", …).

   There is nothing to tap. The app captures by itself when it recognizes the target reliably and the image is good. The order is the meter and its number, the panel (and the main breaker size when its label reads), the gas meter (only when Home Info said Yes or Not sure), a step back to look around, then the battery. The app suggests a spot beside the meter wall, accepts it, and tints it with the live tone. Then the scan saves itself and opens Review. Distances never appear on the camera. To leave early, swipe right from the left edge; the scan so far is kept.
3. **Review & Export.** "What's missing" rows take you to the fix (Home Info, the Live Survey, or the Electrical screen to retake a photo or type a number). Numbers read by scan are marked "read by scan" until you confirm them here. Then property, electrical, site-measurement, and eligibility details, a `survey.json` preview, and Share, which sends `survey.json`, the photos, and `scene.ply` when the phone built a LiDAR mesh. Start over deletes the survey.

## Checks and colors

`BaseRuleSet` has 12 required checks, each pass, conflict, or unknown: Austin main breaker 150–200 A; a 200 A panel for solar or two batteries (from the panel's bus rating, never the main breaker); a clear 3 ft × 3 ft pad; within 20 ft of the meter; within 1 ft of the wall; not in front of a window; out of the meter's and panel's working space; at least 3 ft from a gas meter; transfer-switch space beside the meter; meter height 3–6 ft; about 30 × 36 in of front working space; meter and panel on the same wall.

- **Green**: every check passed on measured evidence.
- **Teal**: every check passed, but some passes are your statements (for example the typed panel bus rating or "No gas meter").
- **Amber**: something is still unknown.
- **Red**: a measured conflict.

The battery tint on the camera uses the same assessment as Review. Pad and transfer-switch clearance come from the LiDAR mesh once enough of the area was seen. Without LiDAR those checks stay unknown, so the preview stays amber.

## Optional TypeSafe Jev advisory

Review can show a collapsed "Jev advisory" card that asks TypeSafe Jev how ready the survey looks. It is advisory only and never changes a check, the tone, or `survey.json`. It appears only when a key is set; with no key there is no card and no network call. To try it, add one line to your gitignored `Config/Local.xcconfig`:

```
TYPESAFE_API_KEY = your_key_here
```

The committed `Config/BaseAR.xcconfig` keeps it empty. You can also set `TYPESAFE_API_KEY` as an environment variable in the Xcode scheme. Never commit a key. The request sends check results and home answers, never name, contact details, address, location, meter number, or photos. Errors and timeouts show "Advisory unavailable".

## Project structure

- `BaseAR/Survey`: `SurveySession`, `SurveyStore` (the composition root), `ToneStyle`
- `BaseAR/Onboarding`: first-launch Home Info wizard
- `BaseAR/Electrical`: meter-number scan, photo OCR, typed numbers
- `BaseAR/Placement`: Live Survey view, scene controller, detector, battery geometry, measurements
- `BaseAR/Rules`: `EligibilityRule`, `BaseRuleSet`, `SurveyEvaluating`
- `BaseAR/Review`: Review, JSON and PLY export, Jev advisory
- `BaseAR/Location`: property location and address suggestions

`scene.ply` holds the LiDAR mesh in meters in the AR world frame, with camera colors, plus the battery, pad, equipment marks, and distance bars colored pass / conflict / unknown. The header comments list the measurements. Open it in MeshLab, CloudCompare, or Blender.

## Equipment detector

`BaseAR/Placement/EquipmentScan.mlpackage` is YOLO26n fine-tuned at 640 px to find the electric meter (class 0) and breaker panel (class 1). It only proposes: a lock also needs the box to land on a real wall or depth patch, agree over several frames, and pass the separation and height guards. The panel class rarely fires away from the one demo wall it was trained on, and AC units can score as meters. Retrain on phone frames from at least 3 houses. Training data lives in the gitignored `training/`:

1. `uv venv --python 3.12 training/.venv && uv pip install --python training/.venv/bin/python ultralytics coremltools "git+https://github.com/ultralytics/CLIP.git"`
2. `python3 scripts/fetch_commons.py`: about 400 CC-licensed Wikimedia Commons photos, credited in `training/raw/sources.csv`.
3. Put hand-labeled site photos in `training/site/`, each with a YOLO `.txt` label beside it. They are repeated three times, and four are held out (`VAL_STEMS` in `autolabel.py`).
4. `training/.venv/bin/python scripts/autolabel.py`: YOLOE-26l drafts meter boxes. Check `training/review/` and list bad images in `training/exclude.txt`.
5. `training/.venv/bin/python scripts/train_equipment.py`: trains on the Apple GPU and writes the Core ML package into the app.

## How this maps to Base

Base's public request has two steps (researched 26 September 2026). [Get Started](https://www.basepowercompany.com/get-started) collects ownership, energy setup, address, and contact. Engineers later judge the site from a nine-shot [photo kit](https://help.basepowercompany.com/en/articles/10280641). This app asks the home questions, captures the meter and panel photos during the Live Survey, reads the meter number (and the main breaker size when legible), measures what AR can, and keeps everything on the phone. Siting numbers follow Base's [equipment requirements](https://help.basepowercompany.com/en/articles/10280705) and [Core specs](https://www.basepowercompany.com/specs/core). The longer comparison is in `reports/Base battery form vs app.md`, which is partly out of date.

## Still stubbed or next

- **Next: the photo kit's wide shots** (surrounding area from at least 10 steps back, left, right, adjacent wall, behind the fence, area around the breaker box). The look-around step walks those views but does not save them yet.
- AR distances are preliminary estimates and need field checks against a tape. They do not replace an installer's measurement.
- The detector needs retraining on real phone frames.
- Open team calls, listed in `docs/context/README.md`: the 3 ft meter-height minimum, meter and panel on opposite sides of one wall, and the working-space shape.
- No ERCOT data, satellite imagery, Base backend, or permitting logic.

## Research and proposed expansion

The [context pack](docs/context/README.md) holds the 26 September electrical guide, the scan-coverage design, and the verified repo status. The [site-survey research index](docs/site-survey-research/README.md) preserves the 26 September research, source links, product decisions, and a proposed end-to-end expansion: utility and program routing, public electrical and property data, placement constraints, a 30-rule research catalog, source coverage, and an implementation handoff.

These documents are research context, not implemented functionality or installation approval. Their code snapshots are older; recheck code-specific findings against current `main`, and do not promote unresolved or model-specific guidance into universal rules.
