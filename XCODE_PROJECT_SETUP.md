# Xcode Project Setup Required

## New Files Added (Need Manual Project Integration)

Two new Swift files were created but need to be added to the Xcode project:

1. `BaseAR/Survey/RealtimeSurveyView.swift` — Single unified realtime feedback screen
2. `BaseAR/Survey/SimplifiedSurveyFlow.swift` — Two-step survey flow wrapper

## Steps to Add Files in Xcode

1. Open `BaseAR.xcodeproj` in Xcode
2. Right-click the "Survey" group in the Project Navigator
3. Select "Add Files to 'BaseAR'..."
4. Navigate to `BaseAR/Survey/`
5. Select both:
   - `RealtimeSurveyView.swift`
   - `SimplifiedSurveyFlow.swift`
6. Ensure:
   - ✅ "Copy items if needed" is UNCHECKED (files already in place)
   - ✅ "Create groups" is selected
   - ✅ "Add to targets: BaseAR" is checked
7. Click "Add"

## Verify Build

After adding files:
1. Product → Clean Build Folder (⇧⌘K)
2. Product → Build (⌘B)
3. Should compile successfully

## What Changed

### Flow Simplification

**Before**: 9-step verbose guided checklist with ~20 photos
- safety → home → program → meter → meterContext → breaker → panelContext → placement → review

**After**: 2-step + realtime feedback
- Step 1: Home Information (name, address, ownership, energy setup)
- Live Survey: Single AR screen with:
  - Live equipment detection + scanning
  - Real-time AR placement preview
  - Status chips (location, electrical, placement)
  - TypeSafe Jev coaching overlay (throttled, advisory only)
  - Review/export always available

### Key Changes

1. **ContentView.swift**: Replaced `GuidedSurveyView` with `SimplifiedSurveyFlow`
2. **SimplifiedSurveyFlow.swift**: Two-step launcher (home info → realtime screen)
3. **RealtimeSurveyView.swift**: Unified AR + scanning + rules + Jev coaching

### Product Intent (Logan)

"user completes survey step 1 (fill it out once), then goes to a single screen with realtime feedback — live AR + rules chips + TypeSafe Jev advisory coaching"

**NOT** "~20 photos to take with a lot of words" multi-capture / verbose guided checklist.

## Hard Constraints Maintained

- ✅ TypeSafe Jev advisory only (never overrides measured green/amber/red or EligibilityRule)
- ✅ Deterministic BaseRuleSet authority preserved
- ✅ Austin-first utility reporting
- ✅ Photo capture available but not primary blocking path

## After Xcode Setup

Run on physical iPhone to test:
1. Complete Step 1 (home information)
2. Tap "Open Live Survey"
3. Point camera at meter → live scanning
4. Point camera at panel → live scanning
5. AR placement preview with live rule status chips
6. TypeSafe Jev coaching chip (when API key configured)
7. Save and review

The old verbose guided flow (`GuidedSurveyView`) remains in codebase but is not used in the primary path.
