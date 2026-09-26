# Spatial Evidence Integrity Verification

Test plan for PR #5 P0 fixes on physical iPhone with LiDAR.

## Prerequisites

- Physical iPhone 12 Pro or later (LiDAR required)
- iOS 17+
- Outdoor or large indoor space with meter/panel/gas meter (or mock equipment)
- Build from `cursor/fix-spatial-evidence-validity-1810` branch

## Test Cases

### P0-1: Stale Clearance Invalidation

**Objective**: Verify that when measurements return nil, old clearance booleans are replaced instead of retained.

**Steps**:

1. Place battery with good LiDAR mesh coverage around 3×3 ft footprint
2. Observe `footprintIsClear` in review (should be true if clear, false if blocked)
3. Move battery to area with no mesh coverage or very sparse scan
4. Check review again

**Expected**:
- Step 2: `footprintIsClear` = true/false (measured result)
- Step 4: `footprintIsClear` = nil (UNKNOWN), not the old value from step 2

**Verification in code**:
```swift
// BaseAR/Placement/PlacementMeasuring.swift, applying()
updated.footprintIsClear = measured.footprintIsClear  // Always replaced, even nil
```

**Pass criteria**: Moving battery to unmeasured area resets clearance to nil, not stale boolean.

---

### P0-2: Sparse Mesh Coverage Rejection

**Objective**: Verify that unobserved volume returns UNKNOWN instead of clear.

**Steps**:

1. Place battery in partially scanned area with < 8 mesh samples in footprint
2. Observe `footprintIsClear` in review
3. Scan the footprint thoroughly (walk around, look at ground/walls)
4. Wait for mesh to densify (> 8 samples covering footprint)
5. Check review again

**Expected**:
- Step 2: `footprintIsClear` = nil (insufficient coverage)
- Step 5: `footprintIsClear` = true/false (adequate coverage, measured result)

**Verification in code**:
```swift
// BaseAR/Placement/PlacementMeasuring.swift
func footprintClearance(_ snapshot: PlacementSceneSnapshot) -> Bool? {
    let footprintVolume = volumeBounds(...)
    guard hasAdequateCoverage(snapshot.classifiedMesh, in: footprintVolume) else { return nil }
    // ... occupancy check only if coverage is adequate
}
```

**Pass criteria**: Sparse mesh returns nil. Dense mesh returns pass/fail.

**Additional checks**:
- `frontWorkingSpaceIsClear` requires coverage of 30×36 in slab
- `transferSwitchClearanceObserved` requires coverage of 13 in × 3 ft reservation

---

### P0-3: Preview vs. Confirmed Placement

**Objective**: Verify that auto-placed or camera-relative preview cannot become measurement evidence.

**Steps**:

1. Start AR placement (app may auto-place battery on launch if plane detected)
2. If auto-placed, check battery color/state and review measurements
3. Tap ground deliberately to place battery
4. Check measurements again

**Expected**:
- Step 2 (auto-place): 
  - `batteryIsPreview` = true
  - No `distanceToMeterFeet`, `distanceToWallFeet`, `footprintIsClear`, etc.
  - Preview visible but not confirmed
- Step 4 (user tap):
  - `batteryIsPreview` = false
  - Measurements active (distances, clearances)

**Verification in code**:
```swift
// BaseAR/Placement/PlacementARView.swift
func autoPlaceIfPossible() {
    batteryIsPreviewMode = true  // Preview mode
    placeBattery(at: placement)
}

// User tap:
case .battery:
    batteryIsPreviewMode = false  // Confirmed placement
    placeBattery(at: position)

// BaseAR/Placement/PlacementMeasuring.swift
func measure(_ snapshot: PlacementSceneSnapshot) -> PlacementMeasurements {
    let confirmedBattery = snapshot.batteryPosition != nil && !snapshot.batteryIsPreview
    let wallFeet = confirmedBattery ? wallDistanceFeet(snapshot) : nil
    // ... all battery measurements return nil when preview
}
```

**Pass criteria**: Preview battery visible but produces no measurements. Tap placement enables measurements.

---

### P0-4: Evidence Revision Versioning

**Objective**: Verify that screenshot and measurements are bound with same revision ID.

**Steps**:

1. Complete placement (meter, panel, gas, battery)
2. Tap "Save" to capture placement
3. Export and open `survey.json`
4. Check `placement.evidenceRevisionId` and `placement.snapshotTimestamp`
5. Move battery to new position
6. Save again
7. Export and check `survey.json` again

**Expected**:
- Step 4: `evidenceRevisionId` is a valid UUID, `snapshotTimestamp` present
- Step 7: `evidenceRevisionId` is a *different* UUID, `snapshotTimestamp` updated

**Verification in code**:
```swift
// BaseAR/Placement/PlacementARView.swift, savePlacement()
let revisionId = UUID()
store.commitPlacement(committed, revisionId: revisionId)
// ... screenshot captures with same revisionId context

// BaseAR/Survey/SurveyStore.swift
func commitPlacement(_ snapshot: PlacementSceneSnapshot, revisionId: UUID) {
    session.placement.evidenceRevisionId = revisionId
    session.placement.snapshotTimestamp = Date()
}
```

**Pass criteria**: Each save generates a new `evidenceRevisionId`. Screenshots and measurements share the same revision.

**Future validation**: Review system can reject evidence where `evidenceRevisionId` doesn't match screenshot metadata.

---

## Additional Observations

### Tone/Color Validation

After P0 fixes, placement preview should correctly reflect:

- **Green**: All required checks passed with measured evidence
- **Amber**: Unknown (insufficient mesh, no measurement, preview mode)
- **Red**: Measured conflict

**Test**: Place battery in preview mode → should be amber (no measurements). Confirm placement with good coverage → green or red based on actual clearances.

### Export Consistency

After P0-4, every `survey.json` should have:

```json
{
  "placement": {
    "snapshotTimestamp": "2026-09-26T...",
    "evidenceRevisionId": "F7A8B3C2-...",
    "batteryPlaced": true,
    "footprintIsClear": true,
    // ... other measurements
  }
}
```

**Test**: Export multiple times during a session. Each save should advance both timestamp and revisionId together.

---

## Known Limitations (Not Fixed in This PR)

These remain as documented issues, not addressed by P0 scope:

- Wide photo kit (left, right, surrounding, adjacent wall) not captured
- Automatic equipment detection still preliminary
- No ERCOT data, satellite imagery, or Base backend integration
- AR measurements are raycast estimates, not installer-grade precision

---

## Failure Modes to Check

1. **No LiDAR device**: Coverage checks should gracefully return nil (UNKNOWN), not crash
2. **Lost tracking**: Measurements should halt, not produce stale/invalid results
3. **Rapid battery movement**: Preview flag should stay consistent, not flicker
4. **Screenshot timeout**: Revision ID should still be recorded even if screenshot fails

---

## Documentation References

- [P0 issue definitions](https://github.com/nikitaroz/base-ar/blob/feat/guided-site-survey/docs/realtime-guidance-assessment.pplx.md#highest-priority-engineering-findings)
- [Guided survey workflow](https://github.com/nikitaroz/base-ar/blob/feat/guided-site-survey/docs/guided-survey-workflow.md)
- [PR #5](https://github.com/nikitaroz/base-ar/pull/5)

---

## Reporting Results

After on-device validation, update the PR with:

1. Device model and iOS version
2. LiDAR availability
3. Pass/fail for each test case
4. Screenshots or video of key scenarios
5. Any unexpected behavior or regressions

Example:

```markdown
## Verification Results

**Device**: iPhone 13 Pro, iOS 17.5
**Branch**: cursor/fix-spatial-evidence-validity-1810
**Commit**: 3d11a49

| Test Case | Status | Notes |
|-----------|--------|-------|
| P0-1: Stale clearance | ✅ Pass | Clearances reset to nil when battery moved |
| P0-2: Sparse mesh | ✅ Pass | < 8 samples returns nil, dense mesh returns bool |
| P0-3: Preview blocking | ✅ Pass | Auto-place produces no measurements until tap |
| P0-4: Revision versioning | ✅ Pass | New UUID on each save, timestamps advance |

**Regressions**: None observed
**Unexpected behavior**: None
```
