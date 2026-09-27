# Electrical equipment guide

Reference for the equipment on a house exterior, what Base Power asks about each item, and what the app captures today. It is written for the people building the capture flow.

- Organized from `docs/context/sources/electrical-path-explainer.md`. Every claim in that explainer was checked against Base's pages and the repo's research.
- Base pages were fetched on 26 September 2026. Links are at the bottom: [H705] (edited 17 Aug 2026), [H641] (edited 29 Jul 2026), [H833] (edited 29 Jul 2026), [Core]. [Get Started] is a zip-gated join page. Per the repo report, its flow asks about solar, generators, and batteries, but not about the meter, the panel, or photos (`reports/Base battery form vs app.md:5`, `:12`).
- Code citations are for `origin/main` at `be3346c` (26 Sep 2026). They come from reading the code. Nothing here was run on a device.
- The app is a prototype. Nothing in it is final electrical, code, or permitting approval. Base's engineers make the call from photos, and electricians set the final spot on install day ([H705], [H641]).

---

## 1. Overview

```
Utility ──► ① Electric meter ──► ② Main disconnect ──► ③ Breaker panel ──► circuits
            (outside wall,        (one big switch         (the "main breaker box":
             utility's meter)      with the amp rating)     rows of small breakers)

After install, Base adds:
            ④ Transfer switch on the wall next to ①    ⑥ Base Core on the ground, within 20 ft of ①
Not on the power path, but limits the battery spot:
            ⑤ Gas meter (battery at least 3 ft away)
```

**② and ③ are often one box.** Base says the main switch is "either inside your main breaker box or outside next to your meter" ([H641]). If there is a small black or gray box on the meter enclosure, lift its lid to show the switch ([H641]). Base gives no figure for how often each layout occurs.

| Item | What Base asks | What the app captures today |
| --- | --- | --- |
| ① Meter | Close photo with a readable meter number; wide photos around it; no higher than 6 ft; 30 × 36 in clear space in front | Meter photo and number; meter height from the AR lock (3–6 ft rule) |
| ② Main disconnect | Sharp photo with the amp number readable; main breaker 150–200 A in Austin | Typed amperage only. No photo |
| ③ Breaker panel | Photo of the box and its surroundings; only one box; not in a closet; on the same wall as the meter; 30 × 36 in clear space | AR panel lock and same-wall check (wrongly fails opposite sides). No photo. One-box and closet rules are not captured |
| ④ Transfer switch | About 13 in wide, 30 in total clearance, on the wall next to the meter; 3 ft of wall in Base's typical layout | AR wall-space check (needs LiDAR). Reserves 13 in along the wall |
| ⑤ Gas meter | Battery at least 3 ft away. No photo slot | AR ground tap or a "No gas meter" button |
| ⑥ Base Core | 30.68 × 35.9 × 22 in; 3 ft × 3 ft area; within 20 ft of the meter and 1 ft of the wall; not in front of the meter, panel, solar equipment, or a window | Model exists, but the battery cannot be placed on `main` (see ⑥) |

---

## 2. Each item

### ① Electric meter

**What it is.** The utility's meter on an outside wall. Base calls it "your utility meter" ([H641]).

**How to recognize it**
- Base's description: "The gray box with a circular device protruding from it, located on the exterior of your home" ([H641]).
- Base's example photo in [H641] shows an Oncor smart meter under a round clear cover. It has an LCD display and a printed nameplate. A red box marks the meter number (`149 214 094`), which sits above a barcode. The same face also shows an FCC ID, a model number, `FORM 2S CL200 240V`, and a serial string (`BF149214094LGFOCS`).
- In AR, the meter is locked in one of two ways: the detector's `electricMeter` class, or holding the center dot on it for 0.5 s (`BaseAR/Placement/EquipmentDetecting.swift:10-12`, `BaseAR/Placement/PlacementARView.swift:1629-1673`, `:1888-1914`). `AGENTS.md` says not to add automatic equipment detection, and `docs/context/sources/repo-review-2026-09-26.md:68` already flags the conflict.

**What Base requires**

| Requirement | Source |
| --- | --- |
| Photo "zoomed in enough for the meter number in the red box to be legible" | [H641] |
| Area around the meter, "from as far back as possible (at least 10 steps)" | [H641] |
| Area to the right and to the left of the meter, each from at least 10 steps. Each battery "is 3 feet wide, and needs 3 feet of clearance on both sides" | [H641] |
| The **adjacent** wall ("Wall adjacent to the wall with the meter"), "this entire side of the house from corner to corner" | [H641] |
| Area behind the fence, if a fence is on the meter wall | [H641] |
| Meter "no higher than 6 feet off the ground". Base does not say whether this is measured to the top or the center | [H705] |
| "In front of the meter and main breaker box there must be a clear space of 30 in high x 36 inches wide" | [H705] |
| "The meter and conduit must be securely attached and undamaged" | [H705] |
| The battery cannot be placed in front of electrical meters | [H705] |

**What the app captures**
- **Meter photo:** saved as `meter.jpg` (`BaseAR/Survey/SurveyStore.swift:157-160`). You can take it with a live scan or the camera (`BaseAR/Electrical/ElectricalCaptureView.swift:102-148`).
- **Meter number:** the field is `meterNumber`, with its source recorded as manual or OCR (`BaseAR/Survey/SurveySession.swift:105-107`). Live-scan reads are saved with the default `manual` source (`ElectricalCaptureView.swift:210`). Photo OCR takes a digit string on a line labeled "meter" or "mtr" (or the next line) first. If there is none, it takes the longest run of 5–12 digits (`BaseAR/Electrical/VisionElectricalRecognizer.swift:44-51`, `:78-96`). On Base's example face the serial repeats the same nine digits, so the fallback would probably still return the right number. Other faces may not work that way. The app shows "Confirm it matches the meter" (`SurveyStore.swift:175`), but it has no confirm step: any non-empty value clears the missing item (`BaseAR/Rules/SurveyEvaluating.swift:55-58`). This is inferred from the code and was not tested.
- **Meter height (AR):** nothing is tapped. The lock gives a point on the meter. `lockEquipment` then casts a ray straight down for the ground, and falls back to an estimated plane if needed (`PlacementARView.swift:1790-1798`, `:2077-2089`). Height is the lock point minus the ground point (`BaseAR/Placement/PlacementMeasuring.swift:485-490`). The detector locks at the center of its box (`PlacementARView.swift:1684`), so this is roughly the meter's center, not its top. The rule passes for 3–6 ft (`BaseAR/Rules/BaseRuleSet.swift:14-15`, `:184-199`). **Base publishes no 3 ft minimum.** The rule's unknown text still says "Tap the ground below the meter" (`BaseRuleSet.swift:191`), which is stale.
- **Front working space (AR):** there is one 30 × 36 in slab in front of the meter. The code uses the panel only when no meter is locked (`PlacementARView.swift:2091-2118`). It is drawn 30 in along the wall and 36 in out from it (`BaseAR/Rules/BaseRuleSet.swift:16-17`, `BaseAR/Placement/BatteryGeometry.swift:17-18`, `PlacementARView.swift:2110-2117`). Base's text says 30 in *high* × 36 in *wide* (see §4). The slab is placed only once a battery exists (`PlacementARView.swift:2093`, `PlacementMeasuring.swift:407-409`), so on `main` this check stays unknown.
  - Found during this check, from reading only: the scoring box test and coverage grid rotate by −yaw (`PlacementMeasuring.swift:670-676`, `:743`), but the drawn slab uses `simd_quatf(angle: yaw)` (`PlacementARView.swift:1566`). They agree only when the wall is at a multiple of 90° to the AR world axes. On other walls the scored slab is turned relative to the drawn one (at 45° it is 36 in along the wall). The 3 ft pad check uses the same helpers (`PlacementMeasuring.swift:283-302`). Not tested on a device.
- **Not captured:** the wide photos (§3), and whether the meter and conduit are attached and undamaged.

### ② Main disconnect (main breaker)

**What it is.** The single switch that shuts off the whole house. It carries the main amp rating.

**How to recognize it**
- Base says the switch is "either inside your main breaker box or outside next to your meter" ([H641]).
- Base's disconnect example image in [H641] shows three cases side by side: a breaker handle marked "200" with its cover open, a closed gray box with a lift-up lid, and a breaker labeled "MAIN PRINCIPAL" with "200" on the handle.
- Base's example photo of a main breaker box shows the main breaker at the **bottom** of the panel, in its own cutout. The explainer said it sits "at the top". It can be at either end.
- Troubleshooting: "If there is an electrical box connected to your utility meter with a small black/grey box on it, lift the lid to show your main breaker switch underneath. If this is missed, the review process will be delayed" ([H641]).

**What Base requires**

| Requirement | Source |
| --- | --- |
| Photo of "the amperage number - usually 125, 150, or 200 - on your main switch… a clear, zoomed-in, focused shot" | [H641] |
| "The main breaker in the electrical panel must be 100-200A, depending on whether the home has solar and how many batteries we're installing. In Austin, it must be 150-200A" | [H705] |
| "Base systems only support up to 200 amps" (for a later panel upgrade) | [Core] FAQ |

**What the app captures**
- **Typed amperage:** stored in `mainBreakerAmperage` (`BaseAR/Survey/SurveySession.swift:109`) and entered in `BaseAR/Electrical/ElectricalCaptureView.swift:150-177`. A typed value of 150–200 shows a green "Confirmed" label (`:178-181`). Nothing backs that label except the typed number.
- **Austin rule:** `BaseAR/Rules/BaseRuleSet.swift:34-48`.
- **No photo.** `PhotoSlot` has only `.meter` (`BaseAR/Electrical/ElectricalCaptureView.swift:5-9`), and commit `a4c1bb6` removed `breaker.jpg`. The camera permission string still mentions "main breaker" (`BaseAR.xcodeproj/project.pbxproj:446`).
- **Amperage OCR:** a parser exists and ignores `CL`/class ratings (`BaseAR/Electrical/VisionElectricalRecognizer.swift:69-76`, `:180-183`). The UI never calls it: `case .breakerAmperage: break` (`ElectricalCaptureView.swift:215-216`).

### ③ Breaker panel (main breaker box)

**What it is.** The metal box with a door and rows of branch breakers. Base calls it the "main breaker box".

**How to recognize it**
- Base: "Usually located outside next to your meter or in your garage" ([H641]). Base's example photo shows a panel with an open door and a handwritten circuit directory.
- In AR, the scan asks for the panel first (`BaseAR/Placement/PlacementARView.swift:116-130`). It locks the same way as the meter: the `breakerPanel` detector class or the center-dot hold.

**What Base requires**

| Requirement | Source |
| --- | --- |
| Photo of the main breaker box | [H641] |
| Area around it, if not already captured: "outside next to your meter, in the garage, or in a closet" | [H641] |
| "There must only be 1 main breaker box" | [H705] |
| "Cannot be located in a closet, as it must be kept away from flammable materials" | [H705] |
| "The meter and main breaker box need to share the same wall (either next to each other on the same exterior wall or on opposite sides of the same wall)" | [H705] |
| 30 in high × 36 in wide clear space in front | [H705] |
| "If you have solar on your home, your electrical panel must be rated 200A". "For a dual battery system, your electrical panel must be rated 200A" | [H705] |
| The battery cannot be placed in front of breaker boxes | [H705] |
| Someone must be home on install day if the box is in the garage or inside. There are no panel changes on install day | [H833] |

**What the app captures**
- **AR panel lock:** the lock sets a wall point and normal, plus a ground point cast straight down (`BaseAR/Placement/PlacementARView.swift:1790-1798`). The tap handler has a meter/panel branch (`:817-825`), but it cannot be reached: the screen binds only `.gasMeter` or `.battery` mode (`:174`), and taps work only during the gas step (`:180`).
- **Same-wall check:** `BaseAR/Placement/PlacementMeasuring.swift:492-501`, rule at `BaseAR/Rules/BaseRuleSet.swift:201-214`. It passes only when the two wall normals point the same way and the taps lie within 0.30 m of one plane (`PlacementMeasuring.swift:181-183`). The code comment says "Opposite walls fail". **Base explicitly allows opposite sides of the same wall**, for example a garage panel behind an outdoor meter. In that case the check returns a conflict. A required conflict turns the whole preview red (`BaseAR/Rules/EligibilityRule.swift:41-43`), even though Base allows the layout.
- **Battery kept out of the meter's and panel's 30 × 36 zones:** `PlacementMeasuring.swift:306-336`. Unknown on `main` because no battery is placed.
- **No panel photo and no area-around-panel photo.**
- **Not captured:** the one-box rule, the closet rule, and the panel's own rating. The solar or two-battery check reads the typed main breaker amperage instead (`BaseAR/Rules/BaseRuleSet.swift:50-73`; see §4).

### ④ Transfer switch

**What it is.** A switch Base installs to move the house to battery power during an outage. Base calls it the "automatic transfer switch" ([H705]). The Core spec lists "Auto-switch: Seamless (50 milliseconds)" ([Core]). For the 39.2 kWh battery (the Core), visit 1 is when "we'll install a device on your exterior wall, connect it to your main breaker box" ([H833]).

**How to recognize it.** Before install there is usually nothing to find. The capture job is to show **empty wall beside the meter**. This is inferred: no Base page says it outright. Base's join copy treats an existing whole-home standby generator setup as incompatible (`reports/Base battery form vs app.md:14`; `BaseAR/Survey/SurveySession.swift:114`).

**What Base requires**

| Requirement | Source |
| --- | --- |
| "Approximately 13 inches wide and requires a total clearance of 30 inches to accommodate National Electrical Code working space requirements" | [H705] |
| "Must be installed on the wall next to the electrical meter". Measure the distance to obstacles like fences or solar equipment | [H705] |
| Typical layout: "3ft of space allocated on the wall for mounting the automatic transfer switch, followed by a 3ft x 3ft ground footprint for the first battery, and another 3ft of space for the second battery" | [H705] |

The wall space needed is wider than 13 in. Base says 30 in of total clearance and allocates 3 ft of wall in its typical layout. Base does not say which way the 30 in runs. Our inference: Base ties it to NEC working space, which is 30 in wide along the equipment ([NEC summary]), so the 30 in probably runs along the wall. This is unverified.

**What the app captures**
- **Reserved box:** 13 in along the wall, "about 3 ft tall", 30 in out from the wall (`BaseAR/Placement/PlacementMeasuring.swift:53-59`). Rule: `BaseAR/Rules/BaseRuleSet.swift:216-232`.
- **When it can pass:** the check needs a LiDAR mesh and at least 60% scan coverage of the wall behind the box (`PlacementMeasuring.swift:189`, `:456-458`). Either side of the meter can pass (`:441-453`). It does not need a battery.
- **Differences from Base:**
  - The "3 ft tall" is not in Base's text. Base's 3 ft is wall length in the layout.
  - Only 13 in is reserved along the wall. The 30 in is put out from the wall, a direction Base does not give.
  - The box starts 0.08 m (about 3 in) to the side of the meter lock point (`PlacementMeasuring.swift:616`). That point is roughly the meter's center, so the box may overlap the side of the meter enclosure and read as blocked. Inferred from the code, not tested.
  - The battery suggestion uses the same 3 ft constant as a distance *along* the wall (`BaseAR/Placement/PlacementARView.swift:1964-1967`).

### ⑤ Gas meter

**What it is.** The gas utility's meter. It is not on the power path, but it limits where the battery can go.

**How to recognize it.** Base gives no description. The explainer's "gray pipe-and-dial unit, often on the same side of the house" is general knowledge and has no source.

**What Base requires**

| Requirement | Source |
| --- | --- |
| "Must be at least 3 feet apart from gas meters" | [H705] |
| Each battery "needs 3 feet of clearance from gas meters, AC units, fences, other batteries, or other obstructions" | [H641] |
| No gas-meter photo slot in the required list | [H641] |

**What the app captures**
- **AR:** a ground tap on the gas meter or a "No gas meter" button (`BaseAR/Placement/PlacementARView.swift:223-230`, `:826-830`). The distance is measured horizontally from the battery (`BaseAR/Placement/PlacementMeasuring.swift:194-195`). Rule: `BaseAR/Rules/BaseRuleSet.swift:165-182`.
- **"No gas meter" counts as measured.** It returns `.pass` (`BaseRuleSet.swift:171-173`), and `.pass` sets `usedMeasuredEvidence: true` (`BaseAR/Rules/EligibilityRule.swift:19-21`). One tap therefore counts as measured evidence, which breaks the "green only on measured evidence" rule. The attested pattern already exists at `BaseRuleSet.swift:91` and `:228` (`usedMeasuredEvidence: false`).
- **Not encoded:** the 3 ft clearance from AC units, fences, and other batteries ([H641]).

### ⑥ Base Core (battery)

**What Base requires**

| Requirement | Source |
| --- | --- |
| Width 30.68 in, height 35.9 in, depth 22 in | [Core] |
| "Each battery occupies a 3ft x 3ft area and is about 36 inches tall" | [H705] |
| "Should be installed within 20 feet of the electrical meter". No trenching or attic conduit | [H705] |
| "Should be placed within 1 foot of the wall" | [H705] |
| Not in front of electrical meters, breaker boxes, solar equipment, or windows | [H705] |
| Outside only: "Batteries can't be installed indoors or in garages" | [H641]; [H705] says all hardware goes on the exterior |
| Alleys: 32–38 in walk-by space "while maintaining a minimum clearance of 3 feet from walls or other fixed features" | [H705] |
| "Please do not pour your own concrete pad". For the 39.2 kWh battery, Base installs a pad on visit 1 | [H705], [H833] |

**What the app captures**
- **Model and pad:** a placeholder at 30.68 × 35.9 × 22 in (`BaseAR/Placement/BatteryGeometry.swift:3-8`, `BaseAR/Placement/BatteryCatalog.swift:17-23`) and a 3 ft pad (`BaseAR/Rules/BaseRuleSet.swift:13`).
- **Rules:**
  - Footprint: `BaseRuleSet.swift:75-95`
  - 20 ft to the meter: `:97-111`
  - 1 ft to the wall: `:113-127`
  - Window: `:129-145`
  - Meter and panel access: `:147-163`
- **The battery cannot be placed on `main`.**
  - The tap handler ignores it: `case .battery: break` (`BaseAR/Placement/PlacementARView.swift:815-816`).
  - The automatic suggestion runs only when `walkStep == .battery` (`:1270`, `:2004`). `walkStep` starts at `.scan` (`:511`) and changes only in `syncGuide` (`:1972-1973`), which nothing calls.
  - `confirmBatterySpot` (`:1983`) also has no caller. `batteryPosition` is set only after confirmation (`:2214-2221`), so a suggested spot would not count either.
  - Tape measurements cannot fill the gap: the screen always passes `measurementMode: false` (`:175`).
  - Result: every battery-dependent check stays unknown, and green is unreachable.
- **Not encoded:** the "3 ft of clearance on both sides" rule ([H641]), the alley walk-by rule, and the outdoor-only rule.

---

## 3. Base's nine photos vs the app

Base's list is in [H641]. Status key:
- **captured:** a saved photo or value
- **AR-derived:** the AR scan covers the same view or check but saves no photo of it
- **missing:** nothing

| # | Base composition | App today | Status |
| --- | --- | --- | --- |
| 1 | Electric meter, meter number legible | `meter.jpg` plus `meterNumber` (`SurveyStore.swift:157-160`) | captured |
| 2 | Area around the meter, at least 10 steps back | Look-around step "Move farther away", met at 8 ft from the panel lock, or the meter lock if there is no panel (`PlacementARView.swift:296`, `:1842`, `:1854`). Base gives no feet figure. 8 ft is probably less than 10 steps (unverified). Only one frame, `placement.jpg`, is saved at Submit (`PlacementARView.swift:320-345`, `SurveyStore.swift:211-213`) | AR-derived (no photo) |
| 3 | Area to the right of the meter, at least 10 steps | "Look right" step (`PlacementARView.swift:298`, `:1867-1868`). No photo | AR-derived (no photo) |
| 4 | Area to the left of the meter, at least 10 steps | "Look left" step (`PlacementARView.swift:297`, `:1865-1866`). No photo | AR-derived (no photo) |
| 5 | Adjacent wall, corner to corner | Nothing | missing |
| 6 | Behind the fence, if applicable | Nothing | missing |
| 7 | Main breaker box | AR panel lock only. No photo slot (`ElectricalCaptureView.swift:5-9`) | missing |
| 8 | Main disconnect with the amp number visible | Typed `mainBreakerAmperage` only | missing (value typed, no photo) |
| 9 | Area around the main breaker box | Nothing | missing |

App-only extras: `placement.jpg`, `survey.json`, and a LiDAR `scene.ply`. The `.ply` is written when Review shares the survey, and only when a mesh exists (`SurveyStore.swift:217-221`, `:252-263`).

`reports/Base battery form vs app.md:39` and `:49-50` say a breaker photo is captured. That is out of date: commit `a4c1bb6` removed `breaker.jpg`. Today the app covers 1 of the 9 compositions with a photo.

---

## 4. Common confusions

**Meter number vs usage reading.**
- The meter number is the printed ID on the nameplate. In Base's example it is the number in the red box, above a barcode ([H641]).
- It is not the LCD reading. It is also not the other codes on the face, such as the FCC ID, the serial string, or `FORM 2S CL200`.
- `CL200` is the meter's class rating, not a breaker size. That is general electrical knowledge, not a Base statement. The amperage parser already ignores `CL` numbers (`VisionElectricalRecognizer.swift:180-183`).
- The data model keeps the meter number and the amperage as separate fields (`SurveySession.swift:104-109`), and the UI says so (`ElectricalCaptureView.swift:143`).

**Main breaker amperage vs branch breakers.**
- Base wants "the amperage number - usually 125, 150, or 200 - on your main switch" ([H641]).
- The 15 A and 20 A numbers on the small branch breakers are not it. That example is general knowledge, not Base text.

**Main breaker rating vs panel rating.** Base uses two different words, and does not define the second:
- **Main breaker:** "The main breaker in the electrical panel must be 100-200A, depending on whether the home has solar and how many batteries we're installing. In Austin, it must be 150-200A" ([H705]). The Austin rule needs the number on the main switch.
- **Panel:** for solar or two batteries, "your electrical panel must be **rated** 200A" ([H705]). Base does not say whether this means the bus rating, the main breaker, or the service size (`research_notes/Base battery form vs app/eligibility_requirements.md:46`). The main-breaker sentence's "depending on whether the home has solar" hints that it could mean the main breaker, but Base never says so.

The app treats them as the same number. The solar or two-battery check passes whenever the typed main breaker is at least 200 A. Below 200 A, it conflicts if solar or two batteries is reported, and passes if neither is (`BaseAR/Rules/BaseRuleSet.swift:56-71`). The team rule says not to infer panel bus rating from main-breaker amperage. That rule is in the team's agent brief. `docs/context/sources/repo-review-2026-09-26.md:54` attributes it to `AGENTS.md`, but `AGENTS.md` at `be3346c` says only "Solar or two batteries requires a 200A panel". To follow the rule, this check needs its own panel-rating evidence, such as a photo of the panel label. Until then it should stay unknown.

**Where the main switch is.** It can be at the top or the bottom of the panel, or in a separate box beside the meter under a lid ([H641] photos and text).

**Which wall is "corner to corner".** Base means the wall **adjacent** to the meter wall ([H641]), not the meter wall.

**30 × 36 in orientation.**
- Base's text is "30 in high x 36 inches wide" ([H705]).
- The app models the space as 30 in wide × 36 in deep, up to 2 m high (`BaseRuleSet.swift:16-17`, `PlacementMeasuring.swift:405-437`).
- The app's version matches the usual NEC 110.26 framing: 36 in deep, 30 in wide, 6.5 ft high ([NEC summary]). That comes from secondary summaries. It was not checked against the code text.
- Which framing Base means is unresolved. Ask Base, or record both.

**Same wall.** "Opposite sides of the same wall" counts ([H705]). The app currently fails that case (see ③).

---

## 5. Explainer claims and code constants checked

These statements in the explainer, or constants in the code, are wrong or have no support in Base's pages or the repo research.

| Claim | Where | Finding |
| --- | --- | --- |
| The main switch "sits at the top of the breaker panel" | Explainer | **Not always true.** Base's example panel has the main at the bottom |
| The ② and ③ box is "often" the same | Explainer | Both layouts are sourced ([H641]). How often each occurs is unsourced |
| The main disconnect can be "under the meter" | Explainer | Unsourced. Base says "outside next to your meter" |
| The main switch is "usually labeled MAIN" | Explainer | One Base example has a "MAIN PRINCIPAL" label. "Usually" is unsourced |
| The amp number is "the most current your home can draw" | Explainer | General knowledge, not in Base's pages |
| "100, 125, 150 or 200" | Explainer | [H641] says "usually 125, 150, or 200". 100 is only the bottom of the general 100–200 A band ([H705]) |
| "200 A if you have solar or want two batteries", placed under the main disconnect | Explainer | **Not confirmed.** Base words this as the *panel* rating and does not define it ([H705]). Do not treat it as the main breaker number |
| The meter "doesn't switch anything", and small breakers "trip if overloaded" | Explainer | General knowledge, not in Base's pages |
| "The whole wall corner to corner" | Explainer | **Wrong wall.** Base asks for the adjacent wall |
| "About 10 steps back" | Explainer | Base says "at least 10 steps". `AGENTS.md` also says "about" |
| Gas meter is a "gray pipe-and-dial unit, often on the same side" and "shows up in the wide shots" | Explainer | Unsourced |
| "You don't have [a transfer switch] yet" | Explainer | Inference, not stated by Base |
| Transfer-switch wall space is "about 13 in wide" | Explainer | **Too small.** The 13 in switch width is sourced, but the space needs 30 in of total clearance, with 3 ft allocated in the typical layout ([H705]) |
| 15 A and 20 A branch breakers | Explainer | General knowledge. Base only says which number it wants |
| Meter height minimum of 3 ft | `BaseRuleSet.swift:14` | **Unsourced.** Base gives only a maximum of 6 ft |
| Transfer-switch box "about 3 ft tall", 30 in "out from the wall" | `PlacementMeasuring.swift:53-59`, `BaseRuleSet.swift:219` | **Unsourced.** Base gives no height and no direction for the 30 in |
| 8 ft counts as "farther away" | `PlacementARView.swift:1854` | App choice. Base says at least 10 steps |

These explainer numbers match Base's pages:
- Meter no higher than 6 ft
- 30 × 36 in clear space in front of the meter and the panel
- 150–200 A main breaker in Austin
- Only one main breaker box, and not in a closet
- Meter and panel on the same wall, either side by side or on opposite sides
- At least 3 ft from a gas meter
- Transfer switch beside the meter (the 13 in is the switch width only)
- Core about 31 × 36 × 22 in, which rounds [Core]'s 30.68 × 35.9 × 22 in
- 3 ft × 3 ft area
- Within 20 ft of the meter and within 1 ft of the wall. Both of these are "should", not "must"

The explainer's wide-photo list leaves out "behind the fence" and names the wrong wall. Base's full kit is the nine compositions in §3.

The explainer's tile table is out of date. There is one "Electrical" tile for the meter photo, meter number, and breaker size, and it has no breaker photo. The AR tile is "Site measurements" (`BaseAR/ContentView.swift:250-267`).

[H705]: https://help.basepowercompany.com/en/articles/10280705
[H641]: https://help.basepowercompany.com/en/articles/10280641
[H833]: https://help.basepowercompany.com/en/articles/10280833
[Core]: https://www.basepowercompany.com/specs/core
[Get Started]: https://www.basepowercompany.com/get-started
[NEC summary]: https://www.ecmag.com/magazine/articles/article-detail/no-room-for-error-working-space-around-electrical-equipment
