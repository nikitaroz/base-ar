# Phone Test Stack — Quick Start

Branch: `cursor/phone-test-stack-7460`  
PR: https://github.com/nikitaroz/base-ar/pull/6 (DRAFT)

## What's in this stack

**Base**: `chore/guidance-integration` (spatial evidence + observation contracts)  
**Added**: TypeSafe Jev realtime advisory (PR #4)

Advisory is **optional and advisory-only** — it never overrides:
- Measured green/amber/red placement preview color
- Austin deterministic rule pass/conflict/unknown outcomes

## Xcode setup (5 steps)

1. **Checkout**: `git checkout cursor/phone-test-stack-7460`
2. **Config**: Copy `Config/Local.xcconfig.example` → `Config/Local.xcconfig`
3. **Team**: Edit `Local.xcconfig` with your Apple development team + unique bundle ID
4. **Scheme**: Open `BaseAR.xcodeproj`, select `BaseAR` scheme, pick physical iPhone (iOS 17+)
5. **Jev (optional)**: To enable advisory panel, add `TYPESAFE_API_KEY` to Xcode environment or Info.plist

Without the key: advisory panel stays hidden, app works normally.  
With key: review screen shows collapsible "TypeSafe Jev Advisory" with refresh button.

## Physical iPhone testing

- Run outdoors or where phone can see ground + wall
- Camera and location permissions required
- AR placement needs physical device (simulator can walk survey without world tracking)

## What was merged

### From guidance-integration
- Spatial evidence integration contract
- Observation generation safety and scene revision binding
- Durable capture preservation during navigation handoff

### From TypeSafe Jev (PR #4)
- `TypeSafeJevClient` — event-driven API client (`POST https://api.typesafe.ai/v1/systemone`)
- `TypeSafeJevAdvisoryView` — collapsible panel in ReviewView
- Four advisory questions: visit_ready, next_action, blocking_gap, readiness_score
- Graceful degradation on 401/422/429/timeout to "advisoryUnavailable"
- AGENTS.md exception documented

### Conflict resolution
- **README.md** merged: kept Local.xcconfig setup step, added TypeSafe optional step 4, added "TypeSafe Jev Advisory" section

## Files changed from guidance-integration

```
M  AGENTS.md                                    (TypeSafe exception)
M  BaseAR.xcodeproj/project.pbxproj             (TypeSafe files in build)
M  BaseAR/Review/ReviewView.swift               (TypeSafeJevAdvisoryView integrated)
A  BaseAR/Review/TypeSafeJevClient.swift        (NEW: API client)
A  BaseAR/Review/TypeSafeJevAdvisoryView.swift  (NEW: UI panel)
M  README.md                                    (Setup + TypeSafe section)
A  docs/typesafe-jev-integration.md             (NEW: Integration docs)
```

## Hard constraints preserved

✅ DRAFT PR only — base = `chore/guidance-integration`, NOT main  
✅ Advisory only — never overrides measured placement color  
✅ Never overrides `EligibilityRule` outcomes  
✅ Austin deterministic utility rules remain authoritative  
✅ No hardcoded API keys — `TYPESAFE_API_KEY` via env/Info.plist only  
✅ No ARKit/LiDAR math rewriting beyond compile requirements  
✅ OpenJEV (PR #2) NOT included — TypeSafe only

## PR Details

**Title**: Phone Test Stack: Guidance Integration + TypeSafe Jev Advisory  
**URL**: https://github.com/nikitaroz/base-ar/pull/6  
**Status**: DRAFT  
**Base**: `chore/guidance-integration`  
**Branch**: `cursor/phone-test-stack-7460`

Ready for tonight's phone testing.
