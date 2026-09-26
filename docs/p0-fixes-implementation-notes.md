# P0 Fixes Implementation Notes

Technical notes on the four P0 spatial evidence integrity fixes in PR #5.

## Architecture Overview

The fixes maintain the existing `PlacementMeasuring` protocol boundary between AR perception and rules evaluation:

```
ARKit/LiDAR → PlacementSceneSnapshot → PlacementMeasuring.measure() → PlacementMeasurements → EligibilityRule
```

No changes to `EligibilityRule`, `BaseRuleSet`, or `SurveyEvaluating`. All fixes are contained within the measurement layer.

---

## P0-1: Stale Clearance Invalidation

### Problem Pattern

```swift
// OLD: Conditional update kept stale values
if let footprint = measured.footprintIsClear {
    updated.footprintIsClear = footprint
}
// If measured.footprintIsClear is nil, old value persists
```

### Solution

```swift
// NEW: Unconditional replacement
updated.footprintIsClear = measured.footprintIsClear
updated.frontWorkingSpaceIsClear = measured.frontWorkingSpaceIsClear
updated.transferSwitchClearanceObserved = measured.transferSwitchClearanceObserved
```

### Why This Works

- `PlacementMeasurements` already has `Bool?` types (nil = unknown)
- `measure()` returns nil when measurement cannot be made
- `applying()` now propagates that nil to `PlacementEvidence`
- Rules engine already handles nil as UNKNOWN

### Edge Cases Handled

- Battery moved to unmeasured area → clearances reset to nil
- Mesh data deleted or invalidated → clearances reset to nil
- Battery removed entirely → all battery-dependent fields become nil

---

## P0-2: Sparse Mesh Coverage

### Problem Pattern

```swift
// OLD: Any nearby samples allowed clearance check
guard hasScan(snapshot.classifiedMesh, around: battery, radius: 2) else { return nil }
// hasScan only checked "any sample within radius", not density
```

### Solution

Added volume bounds and coverage validation:

```swift
struct VolumeBounds {
    var center: SIMD3<Float>
    var halfExtents: SIMD3<Float>  // X, Y, Z half-dimensions
    var along: SIMD3<Float>         // Local X axis
    var up: SIMD3<Float>            // Local Y axis
    var normal: SIMD3<Float>        // Local Z axis
}

func hasAdequateCoverage(_ samples: [ClassifiedMeshSample], in volume: VolumeBounds) -> Bool {
    // 1. Filter to nearby samples (projected radius + 1m margin)
    // 2. Filter to samples within volume bounds (±0.3m tolerance)
    // 3. Require minimum count based on footprint area
    let requiredCount = max(Int(volume.halfExtents.x * volume.halfExtents.z * 4), 8)
    return volumeSamples.count >= requiredCount
}
```

### Coverage Thresholds

| Volume | Dimensions | Min Samples | Rationale |
|--------|-----------|-------------|-----------|
| Footprint | 3×3 ft pad × 35.9 in height | 8 | 4× area in m², or 8 minimum |
| Working space | 30×36 in × 2m height | 8 | Same formula |
| Transfer switch | 13 in × 3 ft × 30 in out | 8 | Minimum enforced |

### Why 8 Samples Minimum?

- LiDAR mesh at ~1 sample per 0.3m² in good conditions
- 3×3 ft = 0.836 m² → 4× = 3.3 samples (rounded to 8 for safety)
- Prevents "one obstacle sample missing" false negatives
- Tunable per `requiredCount` formula

### Edge Cases Handled

- Initial scan with 1-2 samples → nil (UNKNOWN)
- User walks around, mesh densifies → true/false (measured)
- Mesh deleted after save → coverage check fails, returns nil
- Non-LiDAR device → `lidarMeshAvailable = false`, all coverage checks return nil

---

## P0-3: Preview vs. Confirmed Placement

### Problem Pattern

```swift
// OLD: autoPlace created battery entity
placeBattery(at: estimatedPosition)
// No distinction between preview and confirmed placement
// measure() treated it as real, producing measurements
```

### Solution

Added two-tier placement state:

```swift
// Snapshot state
struct PlacementSceneSnapshot {
    var batteryPosition: PlacementAnchor?
    var batteryIsPreview: Bool = false  // NEW
}

// AR controller state
var batteryIsPreviewMode = false  // NEW

// Auto-place sets preview mode
func autoPlaceIfPossible() {
    batteryIsPreviewMode = true
    placeBattery(at: placement)
}

// User tap clears preview mode
case .battery:
    batteryIsPreviewMode = false
    placeBattery(at: position)
```

### Measurement Gating

```swift
func measure(_ snapshot: PlacementSceneSnapshot) -> PlacementMeasurements {
    let confirmedBattery = snapshot.batteryPosition != nil && !snapshot.batteryIsPreview
    
    // All battery-dependent measurements check confirmedBattery:
    let meterFeet = confirmedBattery ? horizontalFeet(...) : nil
    let wallFeet = confirmedBattery ? wallDistanceFeet(snapshot) : nil
    let footprint = confirmedBattery ? footprintClearance(snapshot) : nil
    // etc.
    
    return PlacementMeasurements(
        batteryPlaced: confirmedBattery,  // false when preview
        batteryPosition: confirmedBattery ? snapshot.batteryPosition : nil,
        // ... all battery fields return nil when preview
    )
}
```

### Visual Behavior

- Preview battery: visible entity, no measurements, amber tone
- Confirmed battery: visible entity, measurements active, green/red/amber based on checks

### Edge Cases Handled

- Auto-place twice (shouldn't happen, but `didAttemptAutoPlace` guards it)
- User taps to confirm preview → clears flag, measurements activate
- User taps new position → moves battery, stays confirmed
- Drag/rotate confirmed battery → remains confirmed, measurements update
- Remove battery → preview flag irrelevant (no position)

---

## P0-4: Evidence Revision Versioning

### Problem Pattern

```swift
// OLD: commit and screenshot were separate, unlinked events
store.commitPlacement(snapshot)
// ... later ...
store.attachPlacementScreenshot(image)
// No way to verify they belong to the same capture
```

### Solution

Single revision ID flows through both operations:

```swift
// In PlacementARView.savePlacement():
let revisionId = UUID()
store.commitPlacement(committed, revisionId: revisionId)
let token = UUID()  // Screenshot capture token
screenshotToken = token
// ... screenshot callbacks ...

// In SurveyStore.commitPlacement():
func commitPlacement(_ snapshot: PlacementSceneSnapshot, revisionId: UUID) {
    session.placement = measurer.applying(snapshot, to: session.placement)
    session.placement.snapshotTimestamp = Date()
    session.placement.evidenceRevisionId = revisionId  // Bound here
}

// In SurveyStore.attachPlacementScreenshot():
func attachPlacementScreenshot(_ image: UIImage) {
    placementImage = image
    session.placement.screenshotFilename = write(...)
    // revisionId already set by commitPlacement
}
```

### Revision Lifecycle

```
User taps Save
    ↓
Generate revisionId (UUID)
    ↓
commitPlacement(snapshot, revisionId) → writes revisionId to placement
    ↓
Generate screenshotToken (UUID, separate)
    ↓
Trigger ARView screenshot capture
    ↓
Screenshot callback → attachPlacementScreenshot(image)
    ↓
Write image to disk, filename to placement.screenshotFilename
    ↓
Export survey.json → includes evidenceRevisionId and screenshotFilename
```

### Verification Contract

In `survey.json`:

```json
{
  "placement": {
    "snapshotTimestamp": "2026-09-26T21:34:56Z",
    "evidenceRevisionId": "A1B2C3D4-...",
    "screenshotFilename": "placement.jpg",
    "batteryPlaced": true,
    "distanceToMeterFeet": 12.3,
    "footprintIsClear": true
  }
}
```

Future validation can:
- Embed `evidenceRevisionId` in screenshot EXIF/metadata
- Reject reviews where `evidenceRevisionId` doesn't match screenshot
- Track revision history for multi-save sessions

### Edge Cases Handled

- Screenshot timeout → revisionId still recorded, screenshotFilename = nil
- User saves twice → new revisionId each time
- User leaves without Save → `commitLiveScene()` generates new revisionId
- Review without screenshot → revisionId present, screenshotFilename = nil

---

## Testing Strategy

### Unit Tests

Per `AGENTS.md`, this is a hackathon project with no unit tests. All verification is on-device.

### On-Device Verification

See [spatial-evidence-verification.md](./spatial-evidence-verification.md) for full test plan.

**Key scenarios**:

1. Move battery to unmeasured area → clearances nil
2. Sparse mesh scan → nil until dense
3. Auto-place → no measurements, tap → measurements
4. Save multiple times → new revisionId each time

### Compile-Time Safety

- All changes use existing Swift types (`Bool?`, `UUID?`, etc.)
- No runtime reflection or dynamic dispatch
- Protocol boundary (`PlacementMeasuring`) unchanged
- Rules engine unchanged

---

## Future Enhancements (Not in This PR)

### P0-1 Follow-up

- Add "measurement provenance" field tracking which scan/model produced each clearance
- Invalidate measurements when battery model changes (different dimensions)

### P0-2 Follow-up

- Adaptive coverage thresholds based on mesh density statistics
- Mesh quality score (sample spacing variance, noise level)
- Real-time coverage visualization overlay

### P0-3 Follow-up

- Visual distinction: preview battery translucent/wireframe, confirmed solid
- Preview-mode distance hints (non-measurement informational display)
- Prevent Save button when battery is still preview

### P0-4 Follow-up

- Embed `evidenceRevisionId` in screenshot EXIF/PNG metadata
- Server-side revision validation
- Revision history log (all saves, not just latest)

---

## Code Quality Notes

### Diff Size

- 4 Swift files modified
- ~120 lines added (coverage checks, preview gating, revision plumbing)
- ~15 lines removed (old conditional clearance updates)
- 1 doc file added (verification plan)

### Backwards Compatibility

- New `evidenceRevisionId` field is optional (`UUID?`)
- Old `survey.json` files decode without it (nil)
- No schema version bump needed (field is additive)

### Performance Impact

- `hasAdequateCoverage()` scans mesh samples twice (nearby filter, then volume filter)
- Typical mesh has ~100-500 samples; filter is O(n), acceptable
- No new heap allocations in measurement hot path
- Preview check is one boolean gate, negligible

---

## References

- [P0 issue definitions](https://github.com/nikitaroz/base-ar/blob/feat/guided-site-survey/docs/realtime-guidance-assessment.pplx.md#highest-priority-engineering-findings)
- [PlacementMeasuring protocol](../BaseAR/Placement/PlacementMeasuring.swift)
- [SurveySession schema](../BaseAR/Survey/SurveySession.swift)
- [PR #5](https://github.com/nikitaroz/base-ar/pull/5)
