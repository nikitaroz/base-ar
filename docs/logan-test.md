# Logan iPhone Test Stack

Branch: `logan/test`  
Based on: `cursor/phone-test-stack-7460` (guidance-integration + TypeSafe Jev)

## What This Branch Contains

This is the **combined phone test stack** with:

1. **Guided survey workflow** with spatial evidence and observation contracts
2. **TypeSafe Jev advisory** (optional, review-screen only)
3. **Durable capture** preservation and scene revision binding
4. **Austin deterministic rules** for placement color

### Key Integration Points

- **Observation contracts** bind captures to scene revisions
- **TypeSafe Jev** appears only when `TYPESAFE_API_KEY` is configured
- **Placement color** (green/amber/red) comes from measured evidence only
- **Advisory panel** never overrides rule outcomes

## Xcode Setup for Logan's iPhone

### 1. Clone and checkout

```bash
git clone https://github.com/nikitaroz/base-ar.git
cd base-ar
git checkout logan/test
```

### 2. Configure signing

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Edit `Config/Local.xcconfig`:

```
DEVELOPMENT_TEAM = YOUR_TEAM_ID
PRODUCT_BUNDLE_IDENTIFIER = com.example.BaseAR.logan
```

Find your Team ID: Xcode → Settings → Accounts → select account → Team ID

### 3. Xcode scheme setup

1. Open `BaseAR.xcodeproj`
2. Select **BaseAR** scheme (top toolbar)
3. Choose Logan's **physical iPhone** (iOS 17+)
4. Product → Scheme → Edit Scheme...
5. Run → Arguments → Environment Variables

### 4. TypeSafe API Key (Optional)

**Important**: Never commit `TYPESAFE_API_KEY` to git.

To enable the advisory panel, add the key in **Xcode scheme only**:

1. Product → Scheme → Edit Scheme...
2. Run → Arguments → Environment Variables
3. Add: `TYPESAFE_API_KEY` = `your_key_here`
4. Ensure "Active" checkbox is checked

**Without the key**: Advisory panel stays hidden, app works normally.  
**With the key**: Review screen shows collapsible "TypeSafe Jev Advisory" with refresh button.

### 5. Build and run

1. Cmd+R to build and run
2. Allow Camera and Location permissions
3. App should open to splash screen

## iPhone Smoke Test Checklist

Test outdoors or where the phone can see ground + walls. AR placement requires a physical device.

### Basic Flow

- [ ] Splash screen appears (Base Site Survey)
- [ ] Intro screen shows ("Let's get your battery placement")
- [ ] Hub shows four tiles
- [ ] Can navigate between all sections

### Home & Personal Info

- [ ] Name, email, phone fields accept input
- [ ] Address field works
- [ ] Radio buttons: own/rent, solar Y/N, generators, battery count (1 or 2)
- [ ] Map shows with location accuracy circle
- [ ] "Request Location" button works
- [ ] Form validates and saves

### Electrical Meter

- [ ] Camera opens for meter photo
- [ ] Can capture round meter photo
- [ ] Meter number field accepts input
- [ ] Photo appears in review
- [ ] Can retake photo

### Breaker Box

- [ ] Camera opens for breaker photo
- [ ] Can capture main disconnect/breaker photo
- [ ] Amperage field accepts numbers (e.g., 200)
- [ ] Photo appears in review
- [ ] Can retake photo

### Battery Placement (AR)

- [ ] AR view opens (outdoor/well-lit area works best)
- [ ] Ground plane detection works
- [ ] Can tap ground to place battery placeholder
- [ ] 3 ft × 3 ft footprint is visible
- [ ] Can move battery by dragging
- [ ] Can rotate battery
- [ ] "Mark Meter" button works
- [ ] "Mark Panel" button works
- [ ] "Mark Gas Meter" button works (if present)
- [ ] LiDAR mesh appears (on supported devices)
- [ ] Distance measurements appear
- [ ] Placement color changes based on measurements

### Review Screen

- [ ] Review screen shows all captured data
- [ ] Both photos visible (meter + breaker)
- [ ] Electrical values shown (meter number, amperage)
- [ ] Solar answer shown
- [ ] AR placement screenshot visible
- [ ] Rule results shown with pass/conflict/unknown
- [ ] Placement color badge (green/amber/red) matches rules
- [ ] "What's Missing" section lists incomplete items
- [ ] "Save Survey" button works
- [ ] Share button works

### TypeSafe Jev Advisory (If Key Configured)

- [ ] Advisory panel appears (collapsed by default)
- [ ] Can expand/collapse panel
- [ ] "Refresh" button triggers fetch
- [ ] Advisory questions appear:
  - [ ] visit_ready (yes/no/unknown)
  - [ ] next_action (proceed/need_more_photos/conflict)
  - [ ] blocking_gap (footprint/transfer_switch/ocr/photos/form/distances/none)
  - [ ] readiness_score (0-3)
- [ ] Advisory never changes placement color
- [ ] Advisory never changes rule outcomes
- [ ] Error states show gracefully (401/422/429/timeout)

### Observation Contracts

- [ ] Captures preserve through navigation
- [ ] AR measurements don't revert unexpectedly
- [ ] Scene revision binding works
- [ ] Durable capture IDs stay consistent

### Placement Color Logic

Test that color changes correctly:

- [ ] **Amber** when evidence is missing (before placement, before measurements)
- [ ] **Green** only when all required checks pass with measured evidence
- [ ] **Red** when a measured conflict exists (e.g., wall distance > 1 ft)
- [ ] Color updates after AR measurements complete
- [ ] Color does NOT change when advisory refreshes

### Austin Rules Verification

With a complete survey, verify rule outcomes:

- [ ] Main breaker 150-200A → pass/conflict as expected
- [ ] Solar + 2 batteries requires 200A panel → enforced
- [ ] Battery within 20 ft of meter → measured
- [ ] Battery within 1 ft of wall → measured
- [ ] Battery at least 3 ft from gas meter → measured
- [ ] Meter height ≤ 6 ft → measured
- [ ] Working space in front of meter/panel → measured
- [ ] Transfer switch space beside meter → noted

### Error Cases

- [ ] Deny camera permission → graceful error
- [ ] Deny location permission → graceful error
- [ ] Go offline before review → survey still accessible
- [ ] Go offline during Jev refresh → shows "unavailable"
- [ ] Invalid Jev API key → shows 401 error gracefully
- [ ] AR fails (poor lighting) → shows guidance

## Known Limitations (Expected)

- Footprint clearance and transfer-switch space are **not fully measured** yet → preview may stay amber even when visually clear
- Simulator cannot run AR placement (world tracking needs device)
- GPS is property-level fix, not precise battery coordinates
- No backend submission (local JSON export only)
- TypeSafe Jev requires network and valid API key

## Troubleshooting

### Build Fails

- Verify `Local.xcconfig` exists and has valid `DEVELOPMENT_TEAM`
- Check bundle ID is unique
- Ensure physical device is selected, not simulator
- Clean build folder: Product → Clean Build Folder (Cmd+Shift+K)

### AR Not Working

- Test outdoors or in well-lit area with visible ground/walls
- Ensure camera permission granted
- Physical device required (not simulator)
- LiDAR works only on iPhone 12 Pro+ / iPad Pro 2020+

### Advisory Panel Not Showing

- Check `TYPESAFE_API_KEY` is set in Xcode scheme environment
- Verify key is active (checkbox checked)
- Restart Xcode and rebuild
- Check Console.app for TypeSafeJevClient logs

### Measurements Not Appearing

- Ensure battery is placed in AR view
- Mark meter, panel, and gas meter (if present)
- LiDAR mesh needs a few seconds to settle
- Move slowly and let ARKit track planes

### Location Inaccurate

- GPS accuracy varies (10-50m typical)
- Horizontal accuracy shown on map as circle
- This is property-level fix, not battery position
- Normal behavior per AGENTS.md constraints

## File Structure

Key files in this stack:

```
BaseAR/
├── Survey/
│   ├── SurveySession.swift       (Core data model)
│   └── SurveyStore.swift         (Composition root)
├── Electrical/
│   ├── MeterCaptureView.swift    (Meter photo)
│   └── BreakerCaptureView.swift  (Breaker photo)
├── Placement/
│   ├── PlacementView.swift       (AR walkthrough)
│   ├── BatteryGeometry.swift     (3D model)
│   └── PlacementMeasuring.swift  (Distance calculations)
├── Rules/
│   ├── EligibilityRule.swift     (Rule protocol)
│   └── BaseRuleSet.swift         (Austin rules)
├── Review/
│   ├── ReviewView.swift          (Review screen)
│   ├── TypeSafeJevClient.swift   (API client)
│   └── TypeSafeJevAdvisoryView.swift (Advisory panel)
└── Location/
    └── LocationService.swift     (GPS fix)

docs/
├── typesafe-jev-integration.md   (Jev API details)
├── guided-survey-workflow.md     (Survey flow)
└── guided-survey-validation.md   (Validation rules)
```

## References

- **TypeSafe Jev docs**: https://docs.typesafe.ai/
- **Base Core specs**: https://www.basepowercompany.com/specs/core
- **Base site guide**: https://help.basepowercompany.com/en/articles/10280705
- **Installation guide**: https://help.basepowercompany.com/en/articles/10280641

## PR Information

- **Branch**: `logan/test`
- **Base**: `chore/guidance-integration`
- **PR**: Will be opened as DRAFT
- **Title**: "logan/test: phone stack (integration + TypeSafe Jev)"
- **NEVER merge to main** — this is a test stack only

## Next Steps After Testing

1. Document any issues in PR comments
2. Screenshot unexpected behavior
3. Note which rules work vs. stay unknown
4. Test with and without `TYPESAFE_API_KEY`
5. Verify placement color logic independent of advisory
6. Check that captures persist through navigation
7. Confirm Austin rules are deterministic

Ready for Logan's iPhone testing.
