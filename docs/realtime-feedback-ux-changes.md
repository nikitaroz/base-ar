# Realtime Feedback UX Changes (logan/test)

## Product Intent (Logan)
"smooth flow no photo taking just real time feedback"

## Current State (Post-Merge)
- Nine-step guided flow with explicit photo capture steps
- Meter/breaker require: Take photo → Review → Confirm → Continue
- Context photos are separate capture steps
- AR placement is step 8 of 9
- TypeSafe Jev appears only at Review (step 9)

## Target State (Realtime Feedback)

### Philosophy
- **Observation > Capture**: Live scanning and AR are primary; photos are optional evidence export
- **Continuous feedback**: Status chips, clearance indicators, and Jev coaching update as you move
- **Flow when ready**: Auto-advance when sufficient evidence collected, no explicit "confirm" gate
- **AR-first**: Equipment detection, placement preview, and rule checks happen together in AR

### Concrete Changes

#### 1. Meter/Panel Steps → Live Observation Mode
**Before**: Tap "Take photo" → Capture → Type number → Toggle "confirm" → Continue
**After**: Open live scanner → Point at equipment → See number + status chip → Auto-save when stable → Continue

Implementation:
- `ElectricalCaptureView` opens `LiveLabelScanner` immediately (not as a secondary option)
- When scan succeeds and stabilizes (3 consecutive matching reads), auto-save snapshot + extracted value
- Remove explicit "confirm" toggle; success = scan stabilized
- "Take photo instead" becomes fallback option for when live scan fails

Files:
- `BaseAR/Electrical/ElectricalCaptureView.swift` - make scan primary, photo secondary
- `BaseAR/Electrical/LiveLabelScanner.swift` - add auto-save on stable read

#### 2. Context Photos → Optional Evidence Layer
**Before**: meterContext and panelContext are separate steps requiring 3-4 photos each
**After**: Context photos available as "Capture evidence" option from AR placement step, not blocking main flow

Implementation:
- Remove `meterContext` and `panelContext` as separate steps from `SurveyStep`
- Add "Capture context photos" disclosure in AR placement view
- Context photos don't block Continue; they're for export/review evidence
- Update `SurveyWorkflow.issues()` to not require context photos for step completion

Files:
- `BaseAR/Survey/SurveyWorkflow.swift` - remove context steps from blocking path
- `BaseAR/Placement/PlacementARView.swift` - add context photo capture UI

#### 3. AR Placement → Integrated Observation + Coaching
**Before**: Scan equipment → Mark gas → Place battery → Save → Review → See Jev
**After**: Continuous AR session with live status chips, clearance indicators, and throttled Jev coaching

Implementation:
- Equipment boxes stay visible with status chips (detected/locked/measuring)
- Placement preview shows live rule results (green/amber/red) as you move battery
- TypeSafe Jev coaching panel available in AR (throttled, not every frame)
- "Save" captures current state + screenshot but doesn't exit AR
- Can iterate placement → see feedback → adjust → save again

Files:
- `BaseAR/Placement/PlacementARView.swift` - add live rule status overlay
- `BaseAR/Review/TypeSafeJevAdvisoryView.swift` - make embeddable in AR view (not just Review)

#### 4. Guided Flow Simplification
**Before**: 9 steps (safety, home, program, meter, meterContext, breaker, panelContext, placement, review)
**After**: 6 steps (safety, home, program, observation, placement, review)

New "observation" step combines meter + breaker live scanning.

Implementation:
- Merge meter + breaker into one "Scan electrical equipment" step
- Both scans open in sequence (meter first, then panel when meter succeeds)
- Context photos and placement come next
- Review remains final step

Files:
- `BaseAR/Survey/SurveyWorkflow.swift` - consolidate steps
- `BaseAR/Survey/GuidedSurveyView.swift` - update step routing

#### 5. TypeSafe Jev as Continuous Coach
**Before**: Only at Review step, manual "Fetch advisory"
**After**: Available throughout AR placement, throttled updates (max 1/10s), shows "what to check next"

Implementation:
- Add lightweight Jev query mode: "next_action_only" (skips full policy evaluation)
- Display coaching chip in AR: "Check gas meter clearance" / "Move battery closer to wall"
- Full advisory remains available at Review for final export

Files:
- `BaseAR/Review/TypeSafeJevClient.swift` - add `fetchNextAction()` lightweight mode
- `BaseAR/Placement/PlacementARView.swift` - integrate coaching chip

### Hard Constraints (Maintained)

✅ **TypeSafe Jev stays advisory** — Never overrides green/amber/red or rule pass/conflict/unknown
✅ **Deterministic rules authority** — BaseRuleSet + ARKit/LiDAR measurements remain source of truth
✅ **Austin-first** — Utility self-report; no GPS-inferred regulated vs unregulated
✅ **P0 integrity** — Stale clearances → unknown; sparse mesh ≠ clear; versioned evidence preserved

### Migration Path

1. **Phase 1** (this commit): Merge main → logan/test ✅
2. **Phase 2** (next commits):
   - Make LiveLabelScanner primary in ElectricalCaptureView
   - Add auto-save on stable read
   - Remove explicit "confirm" toggle
3. **Phase 3**:
   - Consolidate meter + breaker into "observation" step
   - Move context photos to optional AR layer
4. **Phase 4**:
   - Add live rule status overlay in AR
   - Integrate throttled Jev coaching in AR
5. **Phase 5**:
   - Update guided flow to 6 steps
   - Test end-to-end on device

### What Stays

- Deferral mechanism for unsafe/blocked equipment
- Local draft resume
- All measurements and evidence versioning
- JSON + PLY export at Review
- TypeSafe Jev full advisory at Review

### What Changes

- Default interaction model: live observation → realtime feedback → continue when ready
- Photo capture: optional evidence layer, not primary blocker
- Confirmation: implicit (stable scan) not explicit (toggle)
- Coaching: available during capture, not just at end

## Next Actions

1. ✅ Merge origin/main into logan/test
2. Update ElectricalCaptureView to prefer live scanning
3. Add auto-save on stable read to LiveLabelScanner  
4. Remove confirmation toggle requirement
5. Test on physical iPhone
6. Consolidate steps in SurveyWorkflow
7. Add AR coaching overlay
8. Update PR description and push

## Build Status

Post-merge: logan/test builds pending device validation (Xcode not available in cloud env).
Expected: Swift compiler success; AR/Vision features require physical iPhone for full validation.
