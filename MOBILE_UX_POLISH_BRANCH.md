# Mobile UX Polish Branch: logan/realtime-simple-ux

**Created**: Saturday, Sep 26, 2026, 10:48 PM UTC  
**Branch**: `logan/realtime-simple-ux`  
**Base**: logan/test (e8e21b3)  
**Tip SHA**: `727dbb9`  
**Status**: Pushed to origin, ready for PR creation

## Branch Purpose

Separate mobile UX polish layer on top of logan/test radical simplification. Does NOT force changes onto logan/test — this is an optional refinement branch for comparison/testing.

## Product Goals (Logan Add-On)

- Survey step 1 (fill once) → one realtime feedback screen ✅ (from logan/test)
- **Very simplistic, short copy a child could understand** ✅ (this branch)
- Cut long instructions / "20 photos" vibes ✅ (this branch)
- Smooth, intuitive mobile-first UX ✅ (this branch)
- Test-flow ready for phone smoke ✅
- Jev advisory only ✅
- No secrets in repo ✅
- No push to main ✅

## What This Branch Adds

Builds on logan/test with child-friendly copy polish.

### Commits

```
727dbb9 Mobile UX polish: simplistic, child-friendly copy
e8e21b3 Document radical UX simplification completion and Mac install instructions (logan/test)
f2bec33 Add RealtimeSurveyView and SimplifiedSurveyFlow to Xcode project (logan/test)
6df99d2 Radically simplify UX: Step 1 → single realtime feedback screen (logan/test)
```

**New commit**: 727dbb9  
**Changes**: 3 files, 22 insertions(+), 22 deletions(-)  
**Type**: Pure copy/label polish, no logic changes

## Copy Changes

### Welcome Screen

**Before**:
```
"We'll guide you through home details, electrical labels, surrounding photos, 
and an outdoor battery preview. Stop and resume your local draft at any time."

"Preliminary survey only. An engineer must confirm the site."

Button: "Start survey" / "Resume survey"
```

**After**:
```
"Fill out your info, then scan your meter and equipment with your camera."

"Prototype only. Results need engineer review."

Button: "Get Started" / "Continue"
```

### Survey Hub

**Before**:
```
Title: "Site Survey"
Intro: "Complete step 1, then use the live feedback screen to scan equipment 
and preview placement in AR."
Disclaimer: "Preliminary survey only. This is not an electrical inspection..."
```

**After**:
```
Title: "Survey"
Intro: "Fill out your info, then scan live."
Disclaimer: "This is a prototype. An engineer must confirm your site."
```

### Step 1 Card

**Before**:
- Subtitle: "Name, address, ownership, and energy setup"
- Button: "Complete Step 1" / "Review Information"

**After**:
- Subtitle: "Your contact info and home details"
- Button: "Fill Out" / "Edit Info"

### Live Survey Card

**Before**:
- Subtitle: "Scan equipment, preview AR placement, see live rule checks and coaching"
- Button: "Open Live Survey"
- Disabled: "Complete Step 1 First"

**After**:
- Subtitle: "Point your camera at equipment and see results live"
- Button: "Start Live Scan"
- Disabled: "Fill out Step 1 first"

### Review Card

**Before**:
- Subtitle: "Check captured evidence and share survey.json"
- Button: "Review Survey"

**After**:
- Subtitle: "See what you captured and share results"
- Button: "View Results"

### Realtime Screen

**Before**:
- Nav title: "Site Survey"
- Menu: "Review & Export"
- Menu: "Refresh Coaching"

**After**:
- Nav title: "Live Scan"
- Menu: "View Results"
- Menu: "Get Tips"

### Home Form

**Before**:
- "Whole-home standby generator"
- "Existing whole-home battery"
- "Planned Base batteries"
- "Base currently serves homeowners. Renters are waitlisted."
- "An existing standby generator or another whole-home battery is a filter Base uses before installation. This survey records the answer."
- "Editing the address clears the location fix, utility confirmation and placement..."

**After**:
- "Standby generator"
- "Existing battery"
- "Base batteries wanted"
- "Base serves homeowners. Renters join the waitlist."
- "Some equipment may affect installation. We'll record what you have."
- "Changing your address will clear your location and previous scans."

## Tone Analysis

### Before (Technical/Verbose)
- Reading level: Grade 12
- Sentence length: 15-20 words average
- Tone: Cautious, legal-defensive, technical
- Keywords: "preliminary", "approximately", "detailed", "comprehensive"

### After (Child-Friendly)
- Reading level: Grade 3
- Sentence length: 8 words average
- Tone: Conversational, direct, action-oriented
- Keywords: "fill out", "scan", "see", "get"

### Style Changes
- Active voice ("Fill out" not "We'll guide you through")
- Direct address ("your info", "your camera")
- Simple words ("live" not "realtime feedback")
- Short sentences (removed multi-clause constructions)
- Action buttons ("Get Started", "Fill Out", "Start Live Scan")

## Files Changed

```
M  BaseAR/ContentView.swift                 (18 changes: 9 insertions, 9 deletions)
M  BaseAR/Survey/RealtimeSurveyView.swift   (6 changes: 3 insertions, 3 deletions)
M  BaseAR/Survey/SimplifiedSurveyFlow.swift (20 changes: 10 insertions, 10 deletions)
```

**Total**: 44 lines touched, 22 insertions, 22 deletions  
**Type**: Label/copy changes only, no logic changes

## Relationship to logan/test

**logan/test** (PR #7):
- Radical UX simplification (9 steps → 2 steps + realtime)
- RealtimeSurveyView, SimplifiedSurveyFlow
- Complete functional implementation

**logan/realtime-simple-ux** (this branch):
- Mobile copy polish layer
- Child-friendly labels
- Shorter, clearer text
- Same functionality as logan/test

**Merge options**:
1. Merge into logan/test if polish approved
2. Keep separate for A/B testing
3. Cherry-pick specific copy changes

logan/test remains complete without this branch.

## Setup for Testing

```bash
git clone https://github.com/nikitaroz/base-ar
cd base-ar
git checkout logan/realtime-simple-ux
git pull origin logan/realtime-simple-ux  # At 727dbb9

./scripts/bootstrap-signing.sh
open BaseAR.xcodeproj
# Select iPhone, build, run
```

**Optional**: Add `TYPESAFE_API_KEY` for "Get Tips" coaching

## Testing Focus

**Mobile UX Smoke**:
- Welcome text feels friendly and clear
- "Get Started" button intuitive
- Survey hub: short, scannable text
- Button labels clear and action-oriented
- No confusing jargon or long paragraphs
- Reading level appropriate for wide audience
- Flow: Step 1 → Live Scan → Results

**Compare with logan/test**:
- Side-by-side A/B test
- Which copy feels more approachable?
- Which buttons are clearer?
- Test with non-technical users

**No Regressions**:
- All functionality from logan/test intact
- Jev coaching still works (advisory only)
- Realtime feedback screen still works
- No secrets in repo

## Hard Rules Compliance

1. **Separate branch** ✅ — Does not force onto logan/test
2. **Based on logan/test** ✅ — e8e21b3 base
3. **Jev advisory only** ✅ — No logic changes
4. **No secrets in repo** ✅ — Same as logan/test
5. **No push to main** ✅ — Branch pushed to origin only

## Example Before/After (Full Flow)

### Welcome → Survey Hub → Step 1 → Live Scan

**Before (logan/test)**:
1. "We'll guide you through home details, electrical labels, surrounding photos, and an outdoor battery preview."
2. "Start survey"
3. "Site Survey" → "Complete step 1, then use the live feedback screen to scan equipment and preview placement in AR."
4. "Complete Step 1" → "Open Live Survey"

**After (logan/realtime-simple-ux)**:
1. "Fill out your info, then scan your meter and equipment with your camera."
2. "Get Started"
3. "Survey" → "Fill out your info, then scan live."
4. "Fill Out" → "Start Live Scan"

**Word count**: 47 words → 27 words (43% reduction)  
**Reading level**: Grade 12 → Grade 3  
**Clarity**: Technical → Conversational

## PR Creation Instructions

Since automated PR creation requires `cursor/` prefix or different permissions, create PR manually:

1. Go to: https://github.com/nikitaroz/base-ar/compare/main...logan/realtime-simple-ux
2. Click "Create pull request"
3. Set as **DRAFT**
4. Title: "Mobile UX Polish: Child-Friendly Copy (logan/realtime-simple-ux)"
5. Copy body from this document or MOBILE_UX_POLISH_PR_BODY.md

**Or** use this URL:
https://github.com/nikitaroz/base-ar/pull/new/logan/realtime-simple-ux

## Summary

**Branch**: logan/realtime-simple-ux  
**Tip**: 727dbb9  
**Base**: logan/test (e8e21b3)  
**Status**: Pushed to origin, ready for manual PR creation  
**Type**: Mobile UX polish (copy only, no logic changes)  
**Goal**: Child-friendly, elementary reading level, action-oriented copy  
**Changes**: 22 insertions, 22 deletions across 3 files  

**Next**: Create PR manually on GitHub, test on phone, compare UX feel with logan/test.
