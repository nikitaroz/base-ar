# TypeSafe Jev Integration

## Overview

This document describes the TypeSafe Jev realtime advisory integration for Base Site Survey.

## Endpoint

- **URL**: `POST https://api.typesafe.ai/v1/systemone`
- **Auth**: `Authorization: Bearer <TYPESAFE_API_KEY>`
- **Model**: `jev-latest` (or pin `jev-1.13.0`)

## Configuration

The API key is loaded from:
1. Environment variable: `TYPESAFE_API_KEY`
2. Info.plist key: `TYPESAFE_API_KEY`
3. If neither is set, the advisory panel is hidden

## Request Structure

```json
{
  "model": "jev-latest",
  "state": {
    "photos": {
      "meterPhoto": true,
      "breakerPhoto": true,
      "arScreenshot": false
    },
    "distances": {
      "batteryPlaced": true,
      "meterMarked": true,
      "gasMarked": false,
      "panelMarked": true,
      "lidarAvailable": true,
      "meterFeet": 15.2,
      "wallFeet": 0.8,
      "gasFeet": null,
      "meterHeightFeet": 5.3,
      "workingSpaceWidthInches": null,
      "workingSpaceDepthInches": null,
      "meterAndPanelSameWall": true
    },
    "rules": [
      {
        "id": "austin-main-breaker",
        "title": "Austin main breaker",
        "status": "pass",
        "usedMeasuredEvidence": true,
        "isRequired": true
      }
    ],
    "form": {
      "homeownership": "own",
      "hasSolar": true,
      "hasStandby": false,
      "hasExistingBattery": false,
      "plannedCount": 1,
      "breakerA": 200,
      "meterNumberPresent": true
    },
    "policy": {
      "active": "austin",
      "catalogs": {
        "austin": {
          "breakerMin": 150,
          "breakerMax": 200,
          "solarTwoBatteryPanelA": 200,
          "footprintFeet": 3,
          "maxMeterDistanceFeet": 20,
          "maxWallDistanceFeet": 1,
          "minGasDistanceFeet": 3,
          "transferSwitchNote": "13 in wide, ~3 ft tall, 30 in clearance"
        },
        "houston": {
          "breakerMin": 150,
          "breakerMax": 200,
          "solarTwoBatteryPanelA": 200,
          "footprintFeet": 3,
          "maxMeterDistanceFeet": 20,
          "maxWallDistanceFeet": 1,
          "minGasDistanceFeet": 3,
          "transferSwitchNote": "13 in wide, ~3 ft tall, 30 in clearance"
        }
      }
    }
  },
  "questions": {
    "visit_ready": {
      "type": "noul",
      "instructions": "Is the survey ready for a Base engineer visit given measured evidence and policy?"
    },
    "next_action": {
      "type": "choice",
      "instructions": "What should the homeowner/operator do next?",
      "criteria": {
        "proceed": "enough evidence to proceed toward engineer visit",
        "need_more_photos": "more photos or capture needed",
        "conflict": "measured conflict blocks proceeding"
      }
    },
    "blocking_gap": {
      "type": "choice",
      "instructions": "Which missing or failing evidence is the highest-priority blocker?",
      "criteria": {
        "footprint": "3x3 footprint clearance unmeasured or failing",
        "transfer_switch": "transfer-switch space unmeasured or failing",
        "ocr": "meter/OCR or electrical numbers missing",
        "photos": "photo kit incomplete",
        "form": "home/personal form incomplete",
        "distances": "LiDAR/AR distances incomplete",
        "none": "no blocking gap"
      }
    },
    "readiness_score": {
      "type": "score",
      "instructions": "How ready is this survey for engineer review?",
      "criteria": [
        "not started / mostly empty",
        "partial capture, major gaps",
        "usable draft, a few gaps",
        "visit-ready with measured checks"
      ]
    }
  }
}
```

## Response Structure

```json
{
  "answers": {
    "visit_ready": {
      "noul": "yes",
      "confidence": 0.87
    },
    "next_action": {
      "choice": "proceed",
      "probabilities": {
        "proceed": 0.75,
        "need_more_photos": 0.20,
        "conflict": 0.05
      },
      "confidence": 0.75
    },
    "blocking_gap": {
      "choice": "none",
      "probabilities": {
        "none": 0.82,
        "footprint": 0.10,
        "transfer_switch": 0.05,
        "ocr": 0.02,
        "photos": 0.01,
        "form": 0.00,
        "distances": 0.00
      },
      "confidence": 0.82
    },
    "readiness_score": {
      "score": 3,
      "distribution": [0, 0, 2, 8],
      "confidence": 0.80
    }
  }
}
```

## Throttling & Events

The advisory is **event-driven and throttled**:
- Fetches when Review screen first appears
- Fetches when user taps Refresh button
- **Does not** fetch on every AR frame or survey change
- Debounced by design (1-2 second settle recommended if auto-fetch on change is added)

## Graceful Degradation

All errors return `JevAdvisory(status: .unavailable, reason: String)`:
- No API key configured → panel hidden
- Network offline → "Request failed" message
- 401 Unauthorized → "HTTP 401" message  
- 422 Validation error → "HTTP 422" message
- 429 Rate limit → "HTTP 429" message
- Timeout (15s) → timeout error message
- Any other error → localized error description

The advisory panel shows the error but never blocks survey completion.

## Hard Guarantees

✅ **Advisory only** — never overrides measured placement color  
✅ **Advisory only** — never overrides rule pass/conflict/unknown outcomes  
✅ Feature-flagged: panel hidden when key missing  
✅ No hardcoded secrets  
✅ App compiles and runs without the key  
✅ Tight exception in AGENTS.md  

## Files

- `BaseAR/Review/TypeSafeJevClient.swift` — Actor-based HTTP client
- `BaseAR/Review/TypeSafeJevAdvisoryView.swift` — SwiftUI advisory panel
- `BaseAR/Review/ReviewView.swift` — Integrated into review screen

## Testing Without API Key

The app works normally without `TYPESAFE_API_KEY`:
- Advisory panel is hidden
- Review screen shows all other content
- No network calls attempted
- No errors or warnings

## Testing With API Key

Set the key in environment or Info.plist:
```bash
export TYPESAFE_API_KEY=your_key_here
```

Then:
1. Complete survey sections
2. Navigate to Review
3. Advisory panel appears (collapsed by default)
4. Tap Refresh to fetch latest advisory
5. Expand panel to see answers
6. Check that placement color and rule outcomes remain unchanged
