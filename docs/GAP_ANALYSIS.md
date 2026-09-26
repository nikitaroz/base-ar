# Gap Analysis: Base Site Survey iOS App

**Repository**: Base Site Survey  
**Xcode Target**: BaseAR  
**Purpose**: Native iPhone app for preliminary home battery eligibility & placement survey  
**Analysis Date**: September 26, 2026  
**Collaborator**: logbx

---

## Executive Summary

**Base Site Survey** is a hackathon iOS prototype that captures property information, electrical photos, and AR battery placement to produce a local preliminary survey. The app is ~60% feature-complete for a shippable MVP focused on eligibility and placement. Core flows work (capture, AR placement, review, export), but critical gaps prevent the placement preview from turning green and the survey from matching Base Power's published 9-photo kit.

**Top 3 Blockers to MVP**:
1. **OCR stubbed** – Meter number recognition always returns nil; users must type manually
2. **Missing photo kit coverage** – 6 of 9 required Base photos missing (wide meter area shots)
3. **Unmeasured placement checks** – Footprint clearance, transfer-switch space, meter height, and panel working space not measured; preview cannot turn green

**Path to MVP**: Implement OCR (P0), measure AR clearances (P0), add home form fields (P0), then optionally expand photo capture (P1) if replacing engineer review is in scope.

---

## 1. What This Repo Is

### 1.1 Purpose
A native iPhone app that guides homeowners through a preliminary battery placement survey. Base Power engineers normally review a 9-photo kit after signup; this app produces a local stand-in with:
- Personal info & home electrical setup
- Meter and breaker photos (with typed numbers)
- AR placement preview with real-time distance measurements
- Pass/conflict/unknown eligibility checks (Austin rules)
- Local `survey.json` export (no backend submission)

**Critical constraint**: This is explicitly a *prototype*, not electrical approval or a code review.

### 1.2 Technology Stack
- **Language**: Swift (iOS 17+)
- **Frameworks**: SwiftUI, ARKit, RealityKit, Core Location, MapKit, Vision (stubbed)
- **Architecture**: Observable pattern (`@Observable`), protocol-driven boundaries
- **Target Device**: Physical iPhone (AR requires device; simulator walks forms only)
- **Dependencies**: Zero third-party; Apple frameworks only
- **Build System**: Xcode project, no CI/CD automation detected

### 1.3 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      BaseARApp (entry)                       │
│                      ContentView (root)                      │
└────────────────────────┬────────────────────────────────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
        Splash/Intro           SurveyHubView
              │                     │
              │         ┌───────────┼───────────┬──────────┐
              │         │           │           │          │
              └────► Home      Electrical    Placement  Review
                     Info       Capture      ARView     View
                       │           │            │          │
                       └───────────┴────────────┴──────────┘
                                   │
                            SurveyStore (composition root)
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
           MeterNumberRecognizing  │    SurveyEvaluating
                 (stubbed)         │    SurveyExporting
                                   │
                          PlacementMeasuring
                          (CorePlacementMeasurer)
```

**Key Design**:
- `SurveyStore` is the composition root holding one `SurveySession`
- Three protocol boundaries allow parallel work:
  - **Electrical/OCR**: `MeterNumberRecognizing`
  - **AR Placement**: `PlacementMeasuring`
  - **Rules/Export**: `SurveyEvaluating`, `SurveyExporting`
- Data model (`SurveySession`, `ElectricalEvidence`, `PlacementEvidence`) uses optionals so fields can stay unknown until captured
- `PlacementSceneController` owns AR session for survey lifetime (marks persist when navigating away)

---

## 2. What's Already Built

### 2.1 Screens & UI Flow ✅

| Screen | Status | Notes |
|--------|--------|-------|
| **Splash** | ✅ Complete | Branded start with "Base Site Survey" |
| **Intro** | ✅ Complete | Setup assistant ("Let's get your battery placement") |
| **Hub (4 tiles)** | ✅ Complete | Home info, Meter, Breaker, Placement – all unlocked simultaneously |
| **Home & Personal Info** | ✅ Complete | Name, email, phone, address (MapKit suggestions), location map with accuracy circle |
| **Electrical Meter** | ✅ Complete | Camera picker, meter photo, manual meter number field |
| **Breaker Box** | ✅ Complete | Camera picker, breaker photo, manual amperage field |
| **Battery Placement (AR)** | ✅ Complete | AR scene with ground/wall plane detection, tap to place, drag/rotate battery, meter/gas marker placement |
| **Review** | ✅ Complete | Shows all photos, typed values, rule results, missing info list, share sheet |

**UX Highlights**:
- Clean SwiftUI forms with progress indicators
- AR coaching overlay for plane detection
- Live distance readouts (meter, wall, gas) during placement
- Tone-based color coding (green/amber/red) for placement preview
- Disclaimer text on Intro, Hub, Placement, Review

### 2.2 Data Model ✅

```swift
SurveySession (Codable, Sendable)
├── Personal: contactName, email, phone, propertyIdentifier
├── Homeownership: own/rent (optional, unused in hub)
├── GeoFix: lat/long/timestamp/accuracy (phone property fix)
├── ElectricalEvidence
│   ├── Photos: meterPhotoFilename, breakerPhotoFilename
│   ├── Numbers: meterNumber, mainBreakerAmperage
│   └── Setup: hasSolar, generators, existingBattery, plannedBatteryCount
├── PlacementEvidence
│   ├── AR State: batteryPlaced, meterMarked, gasMeterMarked, lidarMeshAvailable
│   ├── Measurements: distanceToMeterFeet, distanceToWallFeet, distanceToGasMeterFeet
│   ├── Positions: batteryPosition, meterPosition, gasMeterPosition, batteryYawRadians
│   └── Stubbed: footprintIsClear, transferSwitchClearanceObserved
└── Assessment: ruleResults[], placementTone, missingInformation[]
```

**Design Strengths**:
- Protocol-driven boundaries (`PlacementMeasuring`, `SurveyEvaluating`, etc.)
- Optional fields model unknown state cleanly
- No premature coupling (AR doesn't depend on networking, rules don't depend on UI)

### 2.3 AR Placement ✅

**What Works**:
- Horizontal and vertical plane detection
- LiDAR mesh occlusion (when supported; graceful fallback to planes)
- Battery placeholder: 30.68"W × 35.9"H × 22"D with 3'×3' footprint pad
- Tap to place, drag to move, two-finger rotation
- Meter (blue box) and gas meter (purple sphere) markers
- Real-time distance measurements:
  - Battery ↔ Meter (horizontal XZ)
  - Battery ↔ Nearest vertical plane (wall clearance)
  - Battery ↔ Gas meter (when marked)
- AR session persists when navigating away (marks don't reset)
- Screenshot capture on "Save placement and review"

**Measurement Logic** (`CorePlacementMeasurer`):
- Wall clearance: finds closest vertical plane whose patch overlaps battery footprint horizontally, measures distance from nearest battery corner
- Gas/meter: straight-line horizontal distance (ignores Y)
- LiDAR mesh shown when available but not yet used for tighter wall measurements

### 2.4 Eligibility Rules ✅

7 rules from published Austin guidance, all returning **pass/conflict/unknown**:

| Rule | Evidence Required | Status |
|------|-------------------|--------|
| Austin main breaker (150-200A) | `mainBreakerAmperage` | ✅ Works |
| Solar or 2 batteries → 200A panel | `mainBreakerAmperage`, `hasSolar`, `plannedBatteryCount` | ⚠️ `plannedBatteryCount` not captured |
| 3'×3' footprint clear | `footprintIsClear` | ❌ Stubbed (never set) |
| Battery ≤20' from meter | `distanceToMeterFeet` | ✅ Works |
| Battery ≤1' from wall | `distanceToWallFeet` | ✅ Works (plane-based) |
| Battery ≥3' from gas meter | `distanceToGasMeterFeet` | ✅ Works (when marked) |
| Transfer switch space beside meter | `transferSwitchClearanceObserved` | ❌ Stubbed (never set) |

**Tone Logic** (green only if every required check has measured pass):
- ❌ **Cannot turn green in current build** (footprint + transfer-switch checks always unknown)
- ✅ Amber when unknown, red when conflict measured
- ✅ Correct: green reserved for full measured pass

### 2.5 Export & Sharing ✅

- `JSONSurveyExporter` writes pretty-printed `survey.json` with ISO8601 dates
- Saved to `Documents/Surveys/{UUID}/`
- Share sheet bundles: `survey.json`, `meter.jpg`, `breaker.jpg`, `placement.jpg`
- No backend, no authentication, no network calls

### 2.6 Location Services ✅

- One-shot property fix via `PropertyLocationProvider`
- Requests precise location, falls back to reduced accuracy
- Returns: latitude, longitude, timestamp, reported horizontal accuracy
- Shown on map with accuracy circle
- Disclaimers: "phone's property location, not the battery position" (repeated 4 times in UI/model)

### 2.7 Tests & CI ❌

**Tests**:
- ✅ One placeholder test (`BaseARTests.swift`): `testAppModuleLoads()` asserts true
- ❌ Zero functional tests (per project instructions: no tests for hackathon)

**CI/CD**:
- ❌ No `.github/workflows/`, `.gitlab-ci.yml`, or Xcode Cloud config detected
- ❌ No automated builds, linting, or device testing

---

## 3. Gaps vs Shippable MVP

### 3.1 Functional Gaps

#### **P0: Critical Blockers**

##### **OCR Stubbed** 🔴
- **File**: `BaseAR/Electrical/MeterNumberRecognizing.swift`
- **Issue**: `UnimplementedMeterNumberRecognizer` always returns `nil`
- **Impact**: Users must manually type meter number (UX friction, error-prone)
- **Evidence**: `recognizeMeterNumber(in:)` implementation is `{ nil }`
- **Work Required**:
  - Implement Vision text recognition on meter photo JPEG
  - Parse numeric meter ID patterns (typical formats: 8-12 digits, may have hyphens)
  - Pre-populate field, allow user override (per design: "typed number is confirmed value")
  - Handle OCR failures gracefully (log, don't block)
- **Estimate**: ~1 workstream (electrical capture owner)

##### **Home Form Fields Missing** 🔴
- **File**: `BaseAR/ContentView.swift` (HomeInformationView)
- **Gap**: No UI controls for:
  - Own/rent radio (model field exists but unused)
  - Portable generator (yes/no)
  - Whole-home standby generator (yes/no)
  - Existing whole-home battery (yes/no)
  - Planned battery count (1 or 2)
- **Impact**:
  - `plannedBatteryCount` missing → solar-or-two-batteries rule always unknown
  - Own/rent missing → can't show Base's "renters are waitlisted" filter
  - Generator/battery answers missing → incomplete product eligibility picture
- **Evidence**: `ElectricalEvidence` has these fields; UI shows only solar as radio
- **Work Required**:
  - Add 5 radio button groups to HomeInformationView
  - Wire to `SurveyStore` setters (already exist)
  - Update progress calculation in hub tile
- **Estimate**: ~2-3 hours UI work

##### **Placement Measurements Stubbed** 🔴
- **Files**: `PlacementEvidence.footprintIsClear`, `transferSwitchClearanceObserved`
- **Gap**: Two required checks never set:
  1. **Footprint clearance**: 3'×3' pad drawn but not measured for obstacles
  2. **Transfer switch space**: ~13" × 30" NEC clearance beside meter not measured
- **Impact**: **Placement preview can never turn green** (required checks always unknown)
- **Evidence**:
  - `BaseRuleSet.planningFootprint` returns unknown when `footprintIsClear == nil`
  - `BaseRuleSet.transferSwitchSpace` returns unknown when `transferSwitchClearanceObserved == nil`
  - No code in `CorePlacementMeasurer` or `PlacementSceneController` writes these fields
- **Work Required** (AR workstream):
  - **Footprint**: Check if LiDAR mesh / planes intersect the 3'×3' ground patch
  - **Transfer switch**: Virtual "space reserved" zone beside meter marker, check plane occlusions
  - May require UX for user confirmation ("Is this space clear?") if automated measurement unreliable
- **Estimate**: ~1 workstream (AR placement owner), 1-2 days

##### **Missing AR Measurements** 🟡
- **Files**: Published requirements not captured in `PlacementEvidence`
- **Gap**:
  - Meter height (Base limit: ≤6 ft from ground)
  - Working space in front of meter/panel (~30"×36" NEC clearance)
  - Whether meter and panel share a wall
- **Impact**: App can't flag violations of these Base requirements
- **Evidence**: Research notes say "AR owns height and spacing" but fields don't exist
- **Work Required** (AR workstream):
  - Meter height: Y-distance from meter marker to ground plane
  - Working space: Raycast forward from meter/panel positions, check for obstacles in 30×36 zone
  - Same wall: Compare meter marker plane vs detected wall planes (normal vector alignment)
- **Estimate**: ~1 day (extends PlacementEvidence, adds rules)

#### **P1: Important for Complete MVP**

##### **Photo Kit Coverage** 🟡
- **Current**: 2 photos (meter close-up, breaker close-up) + AR screenshot
- **Base's Kit**: 9 compositions:
  1. ✅ Electric meter (number legible)
  2. ❌ Surrounding meter area (≥10 steps back)
  3. ❌ Area to the right of meter
  4. ❌ Area to the left of meter
  5. ❌ Adjacent wall (corner to corner)
  6. ❌ Behind the fence (if applicable)
  7. ✅ Main breaker box
  8. ✅ Main disconnect (amperage visible) – same as #7
  9. ❌ Area surrounding breaker box
- **Impact**: Engineers can't judge site from 2 close-ups; wide context missing
- **Assumption**: If app replaces Base's photo review, needs 6+ additional captures
- **Work Required**:
  - Add multi-shot capture flow (or replace single photo with camera session)
  - Label shots ("10 steps back", "left", "right", etc.)
  - Store as `meter_surrounding.jpg`, `meter_left.jpg`, etc.
  - Update export to bundle all shots
- **Alternative**: Treat app as "AR placement tool only"; engineers still request separate photo kit
- **Estimate**: ~2-3 days if required (defer until product decision)

##### **Gas Meter Marker UX** 🟡
- **Current**: Optional purple sphere, no photo
- **Gap**: Base's 3' rule requires gas meter presence, but:
  - Unmarked → rule stays unknown (correct)
  - Marked → distance measured but no photo proof
  - No "I don't have a gas meter" / "not visible" option
- **Impact**: Ambiguity whether user skipped or gas meter doesn't exist
- **Work Required**:
  - Add "No gas meter" checkbox in placement or home form
  - OR: Capture gas meter photo when marked
  - Update rule explanation text

##### **Address Validation** 🟡
- **Current**: Free-text `propertyIdentifier` with MapKit suggestions
- **Gap**: No structured address (street/city/state/ZIP), no validation
- **Impact**: Could accept "my house" or incomplete addresses
- **Work Required**:
  - Parse MapKit result into structured fields
  - Validate before allowing review
  - OR: Keep free-text but add validation hint ("enter full address")

##### **Solar/Generator Product Filters** 🟡
- **Current**: Data captured but no in-app messaging
- **Gap**: Base waitlists renters, considers standby generators/existing batteries "incompatible"
- **Impact**: User completes survey unaware of eligibility
- **Work Required**:
  - Show warning on review if `homeownership == .rent`
  - Show warning if `hasStandbyGenerator == true` or `hasExistingWholeHomeBattery == true`
  - Disclaimer: "Base may waitlist or decline based on these answers"

#### **P2: Nice-to-Have / Post-MVP**

##### **LiDAR Mesh in Wall Measurements** 🟢
- **Current**: Wall clearance uses vertical plane patches only
- **Gap**: LiDAR mesh shown for occlusion but not queried for tighter wall distance
- **Impact**: Plane detection may miss curved walls, tight corners
- **Work Required**: Query `ARMeshAnchor` vertices, find nearest surface point to battery
- **Estimate**: ~1 day (nice optimization, not blocker)

##### **Amperage OCR** 🟢
- **Current**: User types breaker amperage manually
- **Gap**: Photo should be sufficient (Base's kit doesn't require typed field)
- **Work Required**: Same Vision approach as meter OCR, parse "125A", "150A", "200A" from breaker label
- **Estimate**: ~0.5 day (low priority if meter OCR works)

##### **Survey History / Multi-Survey** 🟢
- **Current**: One survey per launch, "Start Over" discards
- **Gap**: Can't compare multiple placements, no history
- **Work Required**: List view of saved surveys, UUID-based directory
- **Estimate**: ~1 day (defer until backend exists)

##### **Offline Resilience** 🟢
- **Current**: No network = already works (local-only)
- **Gap**: Location denial or GPS unavailable → form still usable but fix missing
- **Work Required**: Graceful degradation complete; could add manual lat/long entry
- **Estimate**: Low priority

---

### 3.2 UX Gaps

#### **Placement Green Preview Impossible** 🔴
- **Issue**: Tone stays amber even when no conflicts measured
- **Root Cause**: `footprintIsClear` and `transferSwitchClearanceObserved` always nil
- **User Impact**: No positive feedback for valid placement
- **Fix**: Implement P0 AR measurements above

#### **No Wizard/Step Lock** 🟡
- **Current**: All 4 hub tiles unlocked from start
- **Design Note**: README says "debug layout; forced wizard may come later"
- **Impact**: Users can skip to review with no data
- **Work Required**: Add completion gates (disable Review until required fields filled)
- **Estimate**: ~0.5 day

#### **Camera Permission Handling** 🟡
- **Current**: `CameraImagePicker` presents picker; iOS handles denial
- **Gap**: No pre-explanation for why camera needed, no Settings deeplink on denial
- **Work Required**: Add alert before first camera use, link to Settings if denied

#### **AR Error Messaging** 🟡
- **Current**: `onFailure` closure shows error but no recovery guidance
- **Gap**: "Session failed" isn't actionable
- **Work Required**: Add tips ("Move to better-lit area", "Point at ground", etc.)

#### **Rotation Gesture Discoverability** 🟡
- **Current**: Two-finger twist works but no hint
- **Gap**: Users may not find rotation
- **Work Required**: Animate hint or add "Rotate left/right" buttons (buttons already exist)

---

### 3.3 Data & Accuracy Gaps

#### **GPS Not Battery Position** ✅ (Already Handled)
- **Current**: 4+ disclaimers clarify property fix ≠ battery coordinates
- **Status**: Correct; no gap

#### **AR World Coordinates Not Persistent** ✅ (By Design)
- **Current**: `PlacementAnchor` is local session coordinates, not lat/long
- **Gap**: Can't reconstruct AR scene from JSON alone
- **Assumption**: Engineers don't need AR replay; distances + screenshot sufficient
- **Status**: Acceptable for prototype

#### **Wall Clearance Accuracy** 🟡
- **Current**: Measures from nearest detected vertical plane patch
- **Gap**:
  - Plane may be incomplete if user doesn't scan full wall
  - Curved walls, recesses not captured
  - No validation that plane is actual building wall (could be fence)
- **Impact**: 1' rule may false-positive or false-negative
- **Mitigation**: Already uses 0.5m patch margin; could add LiDAR mesh query (P2)

#### **Meter Number Format** 🟡
- **Current**: Free-text field, no validation
- **Gap**: Could accept "ABC123" or truncated numbers
- **Work Required**: Regex validation for utility meter patterns (typically 8-12 digits)

---

### 3.4 Backend / Integration Gaps

#### **No Backend** ✅ (By Design)
- **Current**: Local JSON export only
- **Constraint**: Project brief says "No backend, accounts, external datasets"
- **Status**: Correct for hackathon scope

#### **No Base API Submission** ✅ (Documented)
- **Current**: Share sheet for `survey.json` + photos
- **Gap**: Engineers must manually upload
- **Assumption**: Out of scope (prototype)

#### **No ERCOT / Satellite / Equipment Detection** ✅ (Explicitly Excluded)
- **Constraint**: Project brief says "Do not add ERCOT data, satellite imagery, automatic equipment detection... unless explicitly asked"
- **Status**: Correct

---

### 3.5 Compliance & Safety Gaps

#### **Disclaimer Placement** ✅ (Strong)
- **Current**: Prototype disclaimer on Intro, Hub, Placement, Review
- **Text**: "Preliminary survey only. This is not an electrical inspection, a code review, or installation approval."
- **Status**: Adequate

#### **Electrical Data Liability** 🟡
- **Gap**: App stores unvalidated amperage/meter numbers
- **Risk**: User typos could lead to unsafe install decisions
- **Mitigation**: Already requires manual confirmation; engineers review

#### **NEC Compliance** 🟡
- **Current**: Rules reference "30×36 working space" but don't measure
- **Gap**: App doesn't check all NEC 110.26 requirements:
  - Clear space depth (36")
  - Height clearance (6.5' headroom)
  - No panel in closet
  - Equipment access
- **Assumption**: Engineers handle full NEC review; app provides preliminary screen
- **Status**: Acceptable for prototype if disclaimer clear

#### **AHJ Variability** 🟡
- **Current**: Hard-coded "Austin" rules (150-200A)
- **Gap**: National guidance is 100-200A; Dallas, Houston may differ
- **Work Required**: Make `BaseRuleSet` locale-configurable, or rename to `AustinRuleSet`
- **Estimate**: ~0.5 day (just config)

---

### 3.6 Testing Gaps

#### **No Unit Tests** ✅ (By Design)
- **Current**: One placeholder test (`testAppModuleLoads`)
- **Constraint**: Project brief: "Do not write, add, or generate unit tests"
- **Status**: Correct

#### **No Manual Test Plan** 🟡
- **Gap**: No documented test scenarios for:
  - OCR edge cases
  - AR plane detection failures
  - Location denial flow
  - Rotation gesture
- **Work Required**: Write test checklist for QA pass

#### **Simulator Limitations** ✅ (Documented)
- **Current**: README says "simulator can walk survey but world tracking unavailable"
- **Status**: Expected; AR requires device

---

### 3.7 DevOps Gaps

#### **No CI/CD** 🟡
- **Gap**: No automated builds, tests, or device deployments
- **Impact**: Manual Xcode builds only, no PR checks
- **Work Required**:
  - Add Xcode Cloud workflow OR GitHub Actions
  - Build scheme validation
  - Optional: TestFlight distribution
- **Estimate**: ~1 day setup

#### **No Code Signing Docs** 🟡
- **Gap**: README doesn't cover provisioning profiles, team ID
- **Impact**: Collaborator may hit signing errors
- **Work Required**: Add Xcode signing instructions to README

#### **No Dependency Lock** ✅ (N/A)
- **Current**: No third-party deps → no lockfile needed
- **Status**: Correct

---

## 4. Prioritized Work Backlog

### P0: Blockers to Green Placement (MVP Core)

1. **Implement Meter OCR** – `MeterNumberRecognizing` 
   - Owner: Electrical capture workstream
   - Effort: ~4-6 hours
   - Deliverable: Vision text recognition, pre-populate field

2. **Add Home Form Fields** – Own/rent, generators, battery count
   - Owner: UI/survey workstream
   - Effort: ~2-3 hours
   - Deliverable: 5 radio groups wired to store

3. **Measure Footprint Clearance** – `footprintIsClear`
   - Owner: AR placement workstream
   - Effort: ~1 day
   - Deliverable: LiDAR/plane intersection check for 3×3 pad

4. **Measure Transfer Switch Space** – `transferSwitchClearanceObserved`
   - Owner: AR placement workstream
   - Effort: ~1 day
   - Deliverable: Virtual clearance zone beside meter marker

5. **Add Missing AR Measurements** – Meter height, working space, same-wall check
   - Owner: AR placement workstream
   - Effort: ~1 day
   - Deliverable: New `PlacementEvidence` fields + rules

### P1: Important for Complete MVP

6. **Decide Photo Kit Scope** – Product decision
   - Question: Replace Base's 9-photo kit or stay AR-focused?
   - If yes: Add 6 wide-angle captures (~2-3 days)
   - If no: Document scope boundary in README

7. **Gas Meter UX** – "No gas meter" option or photo
   - Owner: UI or AR workstream
   - Effort: ~0.5 day

8. **Address Validation** – Structured address or validation
   - Owner: UI/location workstream
   - Effort: ~0.5 day

9. **Product Filter Warnings** – Renter/generator disclaimers on review
   - Owner: Rules/review workstream
   - Effort: ~2 hours

10. **Wizard/Step Gates** – Lock Review until required fields complete
    - Owner: UI workstream
    - Effort: ~0.5 day

11. **Camera Permission Pre-Explanation** – Alert before first use
    - Owner: Electrical capture workstream
    - Effort: ~1 hour

### P2: Polish / Post-MVP

12. **LiDAR Mesh in Wall Measurements** – Query `ARMeshAnchor`
    - Owner: AR placement workstream
    - Effort: ~1 day

13. **Amperage OCR** – Parse breaker label
    - Owner: Electrical capture workstream
    - Effort: ~0.5 day

14. **Survey History** – List/compare multiple surveys
    - Owner: Review/export workstream
    - Effort: ~1 day

15. **CI/CD Setup** – Xcode Cloud or GitHub Actions
    - Owner: DevOps / any collaborator
    - Effort: ~1 day

16. **AR Error Guidance** – Actionable tips on failures
    - Owner: AR placement workstream
    - Effort: ~0.5 day

17. **Manual Test Plan** – QA checklist
    - Owner: Any collaborator
    - Effort: ~0.5 day

---

## 5. Suggested Engineering Plan for logbx

### **Assumptions**
- logbx is unfamiliar with this codebase
- Write access, can push branches and open PRs
- Has Xcode + physical iPhone for AR testing
- Working independently (no pairing)

### **Workstream Recommendations**

**If logbx owns Electrical Capture (OCR + photos)**:
1. **Week 1**: Implement meter OCR (P0 #1), add home form fields (P0 #2), camera permissions (P1 #11)
2. **Week 2**: Add photo kit captures (P1 #6, if decided in scope), amperage OCR (P2 #13)
3. **Week 3**: Polish + testing

**If logbx owns AR Placement (measurements)**:
1. **Week 1**: Footprint clearance (P0 #3), transfer-switch space (P0 #4)
2. **Week 2**: Missing AR measurements (P0 #5) – meter height, working space, same-wall
3. **Week 3**: LiDAR mesh optimization (P2 #12), gas meter UX (P1 #7), testing

**If logbx owns Rules/Review (export + UX)**:
1. **Week 1**: Add home form fields (P0 #2), product filter warnings (P1 #9)
2. **Week 2**: Wizard/step gates (P1 #10), address validation (P1 #8)
3. **Week 3**: CI/CD setup (P2 #15), manual test plan (P2 #17)

### **Recommended First Task (Any Workstream)**
**Start with P0 #2 (Add Home Form Fields)** – Low risk, high clarity:
- File: `BaseAR/ContentView.swift`, lines 440-642 (HomeInformationView)
- Add 5 radio groups (same pattern as existing `RadioChoice` for solar)
- Bindings already exist in `SurveyStore`
- Testable immediately (no AR device needed)
- Unblocks solar-or-two-batteries rule

### **First Week Goals**
1. Build & run app on device (verify AR works)
2. Complete P0 #2 (home fields) – get PR merged
3. Pick one P0 from your workstream (OCR / footprint / transfer-switch)
4. Open 2nd PR by end of week

### **Collaboration Touch Points**
- **Data model changes** (PlacementEvidence, ElectricalEvidence): Coordinate with other workstreams
- **Rule additions** (BaseRuleSet): Tag rules/review owner
- **AR session lifecycle**: Don't break PlacementSceneController pause/resume

### **Key Files to Understand First**
1. `SurveySession.swift` – Data model
2. `SurveyStore.swift` – Composition root
3. `BaseRuleSet.swift` – Rule definitions
4. `ContentView.swift` – Navigation & hub
5. Your workstream boundary:
   - Electrical: `MeterNumberRecognizing.swift`, `ElectricalCaptureView.swift`
   - AR: `PlacementMeasuring.swift`, `PlacementARView.swift`
   - Rules: `SurveyEvaluating.swift`, `ReviewView.swift`

---

## 6. Open Questions / Assumptions

1. **Photo Kit Scope**: Is replacing Base's 9-photo engineer review in scope, or is this app AR-focused only?
   - If yes → P1 #6 becomes P0
   - If no → Document boundary

2. **Green Preview Requirement**: Must placement turn green for MVP, or is amber acceptable?
   - Current: Cannot turn green (footprint/transfer-switch unmeasured)
   - If blocker → P0 #3, #4 critical

3. **Backend Timeline**: When will Base API exist for submission?
   - Current: Local export only
   - If soon → Add networking layer to backlog

4. **AHJ Expansion**: Support cities beyond Austin?
   - Current: Hard-coded Austin rules
   - If yes → Make `BaseRuleSet` configurable

5. **Survey Persistence**: Should surveys survive app restart, or is single-session OK?
   - Current: One survey per launch, discarded on "Start Over"
   - If multi-survey → P2 #14 becomes P1

6. **OCR Accuracy Target**: What % meter number accuracy required?
   - Suggestion: 80%+ pre-populate, always allow manual override

7. **Transfer Switch Measurement**: Automated or user confirmation?
   - Automated measurement may be unreliable (cluttered walls)
   - Consider "Is this space clear?" prompt after AR measures

---

## 7. Repo Health Notes

### **Strengths** ✅
- Clean architecture with protocol boundaries
- Comprehensive data model (optionals for unknown state)
- Zero third-party deps → no supply chain risk
- Strong disclaimers (prototype, not approval)
- Good separation of concerns (AR doesn't leak into rules)

### **Weaknesses** ⚠️
- No tests (by design, but risky for production)
- No CI/CD (manual builds only)
- Hard-coded Austin rules (not configurable)
- Stubbed critical paths (OCR, footprint, transfer-switch)
- Single commit history (hard to trace decisions)

### **Technical Debt**
- `UnimplementedMeterNumberRecognizer` is a TODO factory
- `footprintIsClear` and `transferSwitchClearanceObserved` naming implies implementation exists (it doesn't)
- `PlacementSceneController` is 690 lines (consider extracting gesture handlers, measurement logic)
- No logging or analytics (can't debug user issues)

---

## 8. Conclusion

**Base Site Survey** is a well-architected hackathon prototype with working flows for capture, AR placement, and review. The core vision—guided homeowner survey with real-time eligibility checks—is 60% realized. To reach shippable MVP:

1. **Unblock green placement** (P0 #3, #4, #5): Measure footprint, transfer-switch space, meter height
2. **Complete OCR** (P0 #1): Remove manual meter typing friction
3. **Finish home form** (P0 #2): Capture all Base eligibility questions
4. **Decide photo kit scope** (P1 #6): AR-only or replace engineer review?

The codebase is collaborator-friendly: protocol boundaries allow parallel work, data model is clear, and no surprises in dependencies. **logbx can start immediately with P0 #2 (home form fields)** to get familiar, then pick a core workstream (OCR, AR measurements, or rules/UX).

**Estimated effort to MVP**: 2-3 weeks for one person focusing on P0 items, assuming AR workstream (P0 #3-5 are the heaviest lift). With three collaborators (one per workstream), MVP achievable in 1-2 weeks.

---

**Next Steps for logbx**:
1. Clone repo, build on device, walk full survey flow
2. Read `SurveySession.swift`, `SurveyStore.swift`, `BaseRuleSet.swift`
3. Pick P0 #2 (home form) as first task → PR within 2 days
4. Choose workstream (OCR / AR / Rules) → tackle one P0 item per week
5. Open questions above → sync with team for product decisions
