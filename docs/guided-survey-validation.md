# Guided Survey Validation

This branch is a working implementation candidate, not a device-verified release. No unit tests were added, per `AGENTS.md`.

## Static checks

- **Swift syntax parsing:** All 26 app Swift files checked against the starting main commit; no new syntax-parser errors. Two empty `custom_operator` warnings in `SurveySession.swift` occur at the same `Bundle.main.object(...) as? String ?? ...` expressions in both baseline and branch; they are a parser limitation, not newly introduced parse errors.
- **Xcode project parsing:** The project file parses with the `pbxproj` tooling. Both new Swift source files have file references and are included in the `BaseAR` source build phase.
- **Mermaid validation:** The embedded diagram parses successfully as `flowchart-v2` with Mermaid.
- **Repository hygiene:** `git diff --check` passes; guided-documentation local links resolve.
- **Native build:** Not run. This Linux environment has neither Xcode nor the Apple SDKs. A syntax parser cannot type-check SwiftUI, validate actor isolation, or prove a device build.
- **Manual device run:** Not run. Real camera, OCR, AR, permissions and navigation need the checklist below.

## Xcode handoff

Check out `feat/guided-site-survey`, open `BaseAR.xcodeproj`, and use the repository's ignored `Config/Local.xcconfig` signing setup. Select the `BaseAR` scheme and an iPhone running iOS 17 or later.

For a simulator build on a Mac:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project BaseAR.xcodeproj \
  -scheme BaseAR \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

The simulator exercises forms and library-photo fallback, not physical camera or world tracking.

## Manual acceptance checklist

| Scenario | Expected outcome |
| --- | --- |
| Fresh installation | Start survey, then safety step. Continue and other steps unavailable until acknowledgment |
| Location denied | Typed address still usable; guide can advance; missing phone fix remains visible |
| Address corrected after capture | Utility, location, placement and photo/value acceptance invalidated; saved images remain drafts to recheck |
| Unknown utility | Can explicitly save unknown and advance. Program check remains unknown, no topology/replacement decision |
| Austin Energy selected, amps unconfirmed | Austin main comparison remains unknown |
| Another utility selected, 100A main | No false Austin-only 150–200A conflict |
| Invalid contact inputs | Home step identifies what to fix; reasoned deferral remains available |
| Camera denied | Settings/retry or safe deferral; no fake successful capture |
| Regular camera | Subject-specific coaching visible without covering shutter/cancel; readable with large text |
| Live scanner loses label | Old candidate is cleared and Use disabled; user can scan again or cancel |
| OCR proposes wrong ID | User can type the correct visible ID; no implicit confirmation |
| OCR finishes after manual edit | Older task does not overwrite the manual value |
| Retake confirmed meter/main image | Confirmation becomes false; previous numeric value is not silently accepted for the new image |
| Fence yes/no | Behind-fence slot appears only for yes; unanswered question remains missing |
| Solar/generator/existing battery | Energy-equipment overview appears if any are yes |
| Nameplate inaccessible | Do not open anything; defer panel context with a reason |
| Context photo accepted then retaken | Acceptance clears; new image needs checking |
| Leave form and return | Guide updates from current evidence; no second divergent copy of answers |
| No LiDAR / AR unsupported | Existing fallback works; unresolved data stays unknown and step can defer |
| Guided AR open | Equipment scan/manual marks, gas step, battery placement and save flow accessible by default |
| Save screenshot fails | Existing AR error/retry visible; no invented screenshot |
| Relaunch during survey | Resume at saved step with answers, photos and confirmation flags |
| Relaunch after AR save | Old screenshot remains evidence; reopening AR starts a fresh scan, not old coordinates |
| Missing image file | Resume removes acceptance/reference for missing file and asks for evidence again |
| Draft write failure | Visible save error; no claim that the draft was saved |
| Review feedback | Named revisit action returns to the correct guide step; deferral remains until explicitly removed |
| Share incomplete packet | JSON records unresolved items and reasons; all saved context JPEGs included |
| Cancel iOS sharing | No “submitted to Base” claim or submission-state transition |
| Start over | Explicit confirmation, then current survey data removed and new survey starts at safety |
| Complete every photo | Still preliminary; program/local/model review is unknown, not overall approval |

## Observational trial

Ask a participant to explain the difference between meter ID, usage reading, main-breaker amps and panel bus rating after the capture sequence. Watch for unsafe movement, opening covers, repeated retakes, confusion about photo acceptance, and difficulty finding a return-to-guide button.

Have an electrical reviewer inspect the exported packet without additional explanation. Record which image or missing field they need next; those requests should determine the next iteration rather than adding unverified automatic approval logic.
