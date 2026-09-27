# Scan coverage: when the meter-wall scan is good enough

Design note for step 2, the live AR scan. It covers how the app decides the scan around the meter wall can be trusted for clearances, and what it tells the user while they scan.

- Source: [`sources/scan-completeness-research.md`](sources/scan-completeness-research.md). This note turns that research into decisions and a spec; read the source for the citations.
- Code references are `origin/main` at `be3346c` (26 Sep 2026). Paths are under `BaseAR/`.
- Apple API facts were re-checked on 26 Sep 2026 against developer.apple.com and the `iPhoneOS27.0.sdk` ARKit headers (§2).
- Numbers from papers and vendors were not re-checked. They appear as "reported by <source>".
- Every threshold in §3.8 is a starting value to tune on a device. None of them comes from Apple.

---

## 1. TL;DR

- **Scan coverage is not placement color.** Coverage means "we looked at this patch well enough." Placement color keeps its meaning from `AGENTS.md`: green only when every required check has measured evidence and passes, amber for unknown, red for an observed conflict. A fully covered wall can still be amber. On `main` today the preview is never green; it can still be red from a non-battery check (§6).
- **Clip the mesh to a box at the meter wall.** Score only a gravity-aligned box about **3 m along the wall × 3 m out × 2.5 m up**. Anchor it on the meter wall lock and the ground under it, and widen it to include the battery pad. Ignore all mesh outside the box. Do not wait for a ceiling or a closed room, and do not require a "meter" class.
- **Count good views per 10 cm cell.** A view counts only when all of these hold:
  - tracking is `.normal`;
  - the camera is 0.3–4 m from the cell;
  - the view is within 60° of the surface normal (not edge-on);
  - the depth pixel is `.medium` or `.high` and agrees with the mesh within 5 cm.

  A cell with two good views from different positions counts as observed.
- **Show one line and one tint.** Show a single command aimed at the biggest hole (for example, "Step left along the wall.") and a single neutral tint on the cells not yet scanned. Never lock Submit behind coverage.
- **Grade every clearance** as `missing`, `uncertain`, `locallyUsable`, or `unavailable` (no LiDAR).
  - Close-range checks (1 ft to the wall, the 3 ft pad, transfer switch, working space, window, meter height) can reach `locallyUsable`. The sources report a 1–5 cm error class for close, repeated scans. Nobody has checked that outdoors on a house wall, so treat it as the best case, not a spec (§5.1).
  - The **20 ft meter distance** is measured by walking. Label it "about 0.1 m class." Never call it inch-accurate.

---

## 2. What Apple gives us, and what it does not

| API | What it tells us | What it does not tell us | Check (26 Sep 2026) |
|---|---|---|---|
| [`ARCoachingOverlayView`](https://developer.apple.com/documentation/arkit/arcoachingoverlayview) and [`Goal`](https://developer.apple.com/documentation/arkit/arcoachingoverlayview/goal-swift.enum) | Standard onboarding UI. The goals are `tracking`, `horizontalPlane`, `verticalPlane`, `anyPlane`, and `geoTracking`. With `activatesAutomatically`, it also appears "in limited tracking situations." It hides "after the coaching overlay determines the goal has been met." The delegate gets will-activate, did-deactivate, and did-request-session-reset. | It has no mesh goal, no progress value, and no idea of a region. When it hides, tracking (or one plane) exists. That says nothing about the meter, the pad, or the working space. | **Confirmed.** The five goals match the doc page and `ARCoachingOverlayView.h`. |
| [`ARCamera.TrackingState`](https://developer.apple.com/documentation/arkit/arcamera/trackingstate-swift.enum) | The states are `.normal`, `.notAvailable`, and `.limited(reason)`. The reasons are `initializing`, `excessiveMotion`, `insufficientFeatures`, and `relocalizing`. In `.limited`, Apple says anchor transforms "may not be accurate or consistent from one captured frame to the next." Apple also says the reason is "information you can present to the user." | It gives no drift estimate. `.normal` for the whole of a 6 m walk does not mean the two ends agree to the centimeter. | **Confirmed.** The research note calls one state "unavailable"; Apple's name is `notAvailable`. |
| [`supportsSceneReconstruction(_:)`](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/supportsscenereconstruction(_:)) and [`sceneReconstruction`](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/scenereconstruction) (`.mesh`, `.meshWithClassification`) | "Scene reconstruction requires a device with a LiDAR Scanner." Mesh anchors keep updating as ARKit refines them. With plane detection on, ARKit smooths the mesh where it detects a plane. With people occlusion on (`personSegmentation*`), ARKit removes mesh that overlaps people. `main` does not turn person segmentation on (`PlacementARView.swift:618-622`), so people stay in the mesh. | It gives no coverage percent, no hole list, no per-face confidence, and no vertex spacing. [`ARMeshAnchor`](https://developer.apple.com/documentation/arkit/armeshanchor) says a change in the mesh "is not intended to reflect in real time." | **Confirmed.** |
| [`ARMeshClassification`](https://developer.apple.com/documentation/arkit/armeshclassification) | One label per face: `none` (0), `wall`, `floor`, `ceiling`, `table`, `seat`, `window`, `door`. Raw values 0–7 follow the order in `ARMeshGeometry.h`. | There is no class for a meter, gas meter, soil, concrete, grass, or sky. `none` means "a face ARKit can't classify." It does not mean the face is missing. | **Confirmed.** |
| [`ARFrame.sceneDepth`](https://developer.apple.com/documentation/arkit/arframe/scenedepth), [`smoothedSceneDepth`](https://developer.apple.com/documentation/arkit/arframe/smoothedscenedepth), and [`frameSemantics`](https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct) `.sceneDepth` / `.smoothedSceneDepth` | LiDAR-only [`ARDepthData`](https://developer.apple.com/documentation/arkit/ardepthdata). The class overview says it describes "the distance to regions of the real world from the plane of the camera"; the `depthMap` page itself only says "estimated distance from the device to its environment, in meters." Read it as z from the camera plane, not slant range: that follows the class overview, and `main`'s own depth math already works that way (`PlacementARView.swift:1735`, `:2612-2625`). `confidenceMap` comes with it. The smoothed version is "averaged across several frames." Both are nil unless the semantic is on; check support with `supportsFrameSemantics(_:)`. | Depth covers only the current view. The fused mesh has no confidence at all. | **Confirmed.** Apple gates depth with `supportsFrameSemantics` and the mesh with `supportsSceneReconstruction`. Both need LiDAR, so in practice they are missing together. |
| [`ARConfidenceLevel`](https://developer.apple.com/documentation/arkit/arconfidencelevel) and [`confidenceMap`](https://developer.apple.com/documentation/arkit/ardepthdata/confidencemap) | The levels are `low` ("less confident"), `medium` ("moderately confident"), and `high` ("fairly confident"), with raw values 0, 1, and 2. Natural light lowers confidence on surfaces that are "highly reflective" or have "high light absorption." The confidence map is "useful in filtering out lower-accuracy depth values." | No level comes with a centimeter error. | **Confirmed.** The raw values come from the implicit `NS_ENUM` order in `ARDepthData.h`; the doc page does not list them. |
| [`worldAlignment = .gravity`](https://developer.apple.com/documentation/arkit/arconfiguration/worldalignment-swift.enum/gravity) | The y-axis is parallel to gravity, and `ARConfiguration.h` says this is the default. `main` never changes it, so a box with +Y up is already gravity-aligned. | — | **Confirmed.** |
| [`worldMappingStatus`](https://developer.apple.com/documentation/arkit/arframe/worldmappingstatus-swift.property) | Whether the session can save or relocalize a world map right now. | It is not a measurement-quality score. Do not use it as one. | **Confirmed.** |
| `rawFeaturePoints`, RoomPlan, Object Capture, the 5 m LiDAR range | See the research note. RoomPlan scans interior rooms and Object Capture orbits a small object, so neither fits a house wall. | — | Not re-checked in this pass. |

---

## 3. The algorithm (spec)

### 3.1 Count cells, not faces

ARKit keeps each mesh anchor's identifier but replaces its geometry on update. Face indices are therefore not a stable key. Count views per **world cell** instead. Start with 10 cm cells; `ScanIndex` already uses 10 cm (`Placement/PlacementMeasuring.swift:707`). Go down to 5 cm only if the device keeps up.

### 3.2 The box

**Frame.** Build the box from the meter wall lock, `meterWallHit` (position and normal, `Placement/PlacementARView.swift:548`). If the meter is not locked yet, use the panel wall lock.

- `n`: the horizontal wall normal. Flip it if needed so it points toward the camera.
- `a`: `normalize(cross(up, n))`, the direction along the wall.
- `up`: +Y.
- `g`: the ground height under the meter (`meterGroundPosition.y`). When enough ground cells under the meter are observed, use their median height instead (§5).
- **The wall plane.** Do not assume it passes through the lock point. A lock can come from a small depth patch on the meter itself (`PlacementARView.swift:1690-1698`, normal fit at `:1769-1787`), and the meter stands out from the siding by an amount nobody has measured. Once wall-like faces near the meter are in, refit the plane's offset (and `n`) from them, the same way `g` is refit from the ground.

**Extents,** measured in `(a, n, up)` from `(meter.x, g, meter.z)`:

| Axis | Range | Notes |
|---|---|---|
| along `a` | −1.5 … +1.5 m | Once a battery or a suggested battery spot exists, extend this side to the pad edge plus 0.3 m. Cap the total at 5 m. The suggested pad center sits 3 ft + 1.5 ft = 1.37 m along the wall from the meter (`PlacementARView.swift:1965-1966`) and about 0.36 m out (`:2054-2057`). Its far edge is about 1.83 m along the wall, which is outside a symmetric 3 m box. If the panel is on this wall, also extend to cover its 30 × 36 in slab (within the same 5 m cap). |
| out `n` | −0.15 … +2.85 m | Includes a little space behind the wall face to absorb noise. |
| up | −0.10 … +2.5 m | The transfer strip is 3 ft tall and centered on the meter lock height (`PlacementMeasuring.swift:616-619`). For a meter at 6 ft its top is about 2.3 m, so a 2.0 m box would cut it off. |

When the meter lock moves or is cleared, rebuild the box and drop all cell state.

**Required regions** are the parts of the box each check is graded on:

| Region | Grid | Shape and position | Graded for |
|---|---|---|---|
| `wallTransfer` | wall | 13 in × 3 ft strip beside the meter, on each side. Same placement as `transferSwitchFrame`: starts 8 cm from the lock point, centered at the lock height (`PlacementMeasuring.swift:606-630`). | transfer-switch-space |
| `groundTransfer` | ground | 13 in × 30 in in front of that strip | transfer-switch-space |
| `groundMeterWork` | ground | 30 × 36 in in front of the meter, and in front of the panel if it is on this wall | front-working-space |
| `groundPad` | ground | 3 × 3 ft pad at the placed or suggested battery position | planning-footprint |
| `wallPad` | wall | The cabinet's outline on the host wall, plus 5 cm | not-in-front-of-window, wall-distance |
| `groundMeterFoot` | ground | 0.3 m strip against the wall, under the meter | meter-height |

### 3.3 Cell occupancy (from the mesh)

- **Normalize each face normal first.** `main` stores the raw cross product `cross(b − a, c − a)` (`PlacementARView.swift:2506-2511`). Its length is twice the face area in m², so it is far below 1. As a result, `isOnWall`'s `|normal.y| < 0.45` test (`PlacementMeasuring.swift:645`) passes for nearly every face, and the 0.001 length floor in `unit()` (`:697-700`) drops any face smaller than about 5 cm². Whether ARKit faces get that small near the wall has not been checked. Fix this in both places; do not copy the old test as it is.
- **Wall grid** (2D over `a` × `up`). Holds faces within 0.20 m of the wall plane whose *unit* normal has `|normal.y| < 0.45` and `|dot(normal, n)| > 0.85`. These are the thresholds `isOnWall` uses (`PlacementMeasuring.swift:644-648`).
- **Ground grid** (2D over `a` × `n`). Holds faces whose unit normal has `normal.y > 0.8` and that lie within ±0.25 m of `g`.
- **Obstacle voxels** (3D, 10 cm). Any other face in the box between 0.08 m above `g` and the box top. Each check reads only the voxels inside its own volume.
- **Ignore the face label for geometry.** Outdoor ground is often labeled `none`, so grids are sorted by normal and height alone. `wall` is supporting evidence only. Do not require `floor`.
- **Sample every face.** For each face in the box, use its centroid and its three vertices. `main` takes the centroid of only every second face (`PlacementARView.swift:2488`, `:2500`). Read from `meshClouds` (`:561`), which already holds world positions and triangles.
- **Obstacles count as known.** A ground cell whose column contains an obstacle voxel counts as known (blocked), as `main` already does (`PlacementMeasuring.swift:705`).

### 3.4 Observation rule (per cell, per analyzed frame)

Run at about 5 Hz, off the main thread, on a copied frame: camera transform, intrinsics, image size, and a `DepthSample` copy.

- `p`: for an occupied cell, the mean of the mesh points that fell in it. For an empty cell, the grid-plane center (wall plane or `g`). Do not use the grid-plane center for occupied cells: wall cells take faces up to 0.20 m off the plane and ground cells up to ±0.25 m off `g`, so a 5 cm depth test against the plane would fail on sloped yards and uneven siding.
- `m`: the surface normal. Use `n` for wall cells, +Y for ground cells, and the mean unit face normal for obstacle voxels. Obstacle voxels use the same rule as cells, so "≥ 2 good views" in §5.2 is defined for them.

1. Skip the frame entirely unless tracking is `.normal`.
2. Project `p` into the image. It must land inside the image with a 5% margin.
3. Distance `|camera − p|` must be between 0.3 and 4.0 m.
4. The angle between `m` and `(camera − p)` must be at most 60°.
5. Read the depth pixel. Scale image coordinates to depth coordinates the way `depthPatch` does (`PlacementARView.swift:1711-1712`). Compute the camera-plane z as `-(worldToCamera · p).z`, the same math as `MeshColorCache.sample` (`:2612-2613`). Then take the first case that applies (5 cm stands for `depthAgreeTol`, §3.8):
   - Confidence is `low` (raw 0): `lowConf += 1`.
   - Depth is more than 5 cm nearer than z: something is in front of the cell (a person, a shrub). Count nothing.
   - The cell is not occupied: `emptyLooks += 1`. The view was clear, but there is no mesh there.
   - Depth is more than 5 cm farther than z: `disagree += 1`. The mesh says there is a surface, but depth sees past it (glass, or stale mesh).
   - Otherwise (occupied, depth within ±5 cm of z): a candidate good view.
6. **Distinct views only.** Count a candidate good view only if the camera has moved at least 0.25 m, or turned at least 10°, since that cell's last counted view. This keeps a user who holds still from piling up views.

**Cell states**

| State | Rule |
|---|---|
| `observed` | Occupied, `goodViews ≥ 2`, and `disagree ≤ goodViews` |
| `thin` | Occupied, but `goodViews == 1` or `disagree > goodViews` |
| `wontScan` | Not observed, and `lowConf + emptyLooks ≥ 6` from good poses. Typical causes: a glass meter cover, black siding, deep shade. |
| `unseen` | Everything else |

### 3.5 The hole set and the next instruction

- **Holes.** The hole set is every `unseen` or `thin` cell inside a required region. `wontScan` cells count against the grade but are not coached: they would look like holes forever. The user can finish anyway.
- **Target.** Group holes into 4-connected clusters on each grid. The target is the centroid of the largest cluster by area.
- **Direction.** Let `t` be `target − camera`, flattened to the ground, and `r` the camera's flattened right vector. Pick the first case that applies:
  1. `|dot(t, r)| > 0.5 m`: "Step left / right along the wall."
  2. The target is below the frame: "Aim lower, at the ground by the wall."
  3. The target is more than 4 m away, or seen at more than 60°: "Move closer."
  4. The camera is within 0.5 m of the wall: "Step back."
- **Priority for the single line:** tracking first, then the sun heuristic, then holes, then done (§4).

### 3.6 Stop rule

| Outcome | Condition | Effect |
|---|---|---|
| **Covered** | Every required region that exists is at least 90% `observed` or known-blocked. The largest hole cluster is under 0.05 m² (about 5 cells). At least 0.5 m² of wall and 0.5 m² of ground are observed. | Show "covered." Do not add coverage to Submit's enable rule. Today Submit is enabled only when the cue is `.ready` (panel, meter, and gas done, and look-around done or skipped; `PlacementARView.swift:116-122`, `:251`, `:321`). |
| **Plateau** | Observed area in the required regions grew less than 2% over the last 5 s of normal tracking, while the camera moved at least 0.5 m in that window. Or the step has lasted 120 s. | Show "Some spots didn't scan. You can finish." Holes keep their grades. |

The 120 s cap sits inside the 1–3 minute window reported by Scaniverse.

Neither stop rule changes a rule outcome. Only grades feed the rules (§5).

### 3.7 Freeze rule

**Freeze** a check's (outcome, value, grade) when all of these hold:

- Its region meets the `locallyUsable` coverage conditions in §5.1 (everything except being frozen).
- The outcome and value have held steady (value within 2 cm, or the same yes/no) across at least 3 evaluations spanning at least 1.5 s.
- Tracking stayed `.normal` the whole time.
- The host wall plane moved less than 2 cm.

A frozen result is not re-scored as the mesh keeps changing.

**Unfreeze** when any of these happens:

- The battery, meter, or panel moves. `main` already resets on a battery move for the footprint, window, and working-space checks (`PlacementMeasuring.swift:152-166`).
- Tracking goes to `.limited(.relocalizing)` or `.notAvailable`.
- The session is interrupted.
- More than 10% of a region's cells change occupancy.

A person who stands in the pad for more than 1.5 s will freeze a false obstacle, because `main` leaves people in the mesh (§2). This is a known limit; the user can clear it by moving the battery. Turning on `.personSegmentationWithDepth` might help. Whether it can run alongside scene reconstruction and smoothed depth on every LiDAR phone is **unverified**.

### 3.8 Settings to tune on device

| Setting | Start | Range to try | Why this value |
|---|---|---|---|
| `cellSize` | 0.10 m | 0.05–0.10 m | Research far-field spacing is about 8 cm at 2.5 m, and the detection floor is about 5 cm (reported by Luetzenburg 2021). |
| `minGoodViews` | 2 | 2–3 | Research: "seen more than once." |
| `distinctMove` / `distinctTurn` | 0.25 m / 10° | — | Stops a user who holds still from racking up views. |
| `maxViewAngle` | 60° | 60–70° | The edge-on cutoff. Apple does not publish one. |
| `range` | 0.3–4.0 m | max 3–5 m | Vendors advise 1–4 m; Apple's published range is 5 m (reported by the research note). The equipment lock already uses 0.2–5 m (`PlacementARView.swift:1732`). |
| `minConfidence` | `.medium` | — | Matches the lock, which rejects only `low` (`:1730`). |
| `depthAgreeTol` | 0.05 m | 0.03–0.08 m, or range-scaled | Borrowed from the ARKitScenes indoor filter (reported by arXiv:2111.08897), not from an outdoor calibration. `main`'s own PLY occlusion test allows `0.15 + 0.05·z` (`PlacementARView.swift:2625`). If a flat 5 cm rejects most views at 3–4 m, try a tolerance that grows with range. |
| `wontScanLooks` | 6 | 4–10 | — |
| `regionDone` | 90% | 80–95% | `main` uses 60% (`PlacementMeasuring.swift:189`); keep 60% as the `uncertain` floor. |
| `holeDone` | 0.05 m² | — | About 5 cells, well under the 0.84 m² pad. |
| `plateau` | < 2% over 5 s, with ≥ 0.5 m of camera motion | — | — |
| `stepCap` | 120 s | 60–180 s | Scaniverse's 1–3 min sweet spot (reported). |
| `freeze` | 3 evaluations over ≥ 1.5 s, < 2 cm plane motion | — | — |
| `analysisRate` | 5 Hz | 2–10 Hz | At the 5 m cap, up to about 1,500 ground cells plus 1,300 wall cells per pass. |
| Box | 3 × 3 × 2.5 m, pad margin 0.3 m, along-wall cap 5 m | — | Research: "on the order of 3 m wide, 3 m deep, and 2 m tall." Height raised to 2.5 m so the transfer strip fits (§3.2). |
| Meter-distance guard band | ± 0.5 ft | 0.3–0.7 ft | A bit over the 0.1 m walked class. |
| Close-range guard band | ± 2 in (5 cm) | 1–2 in | Upper end of the 1–5 cm class. |

---

## 4. Coaching copy

The app shows **one line** in the bottom bar. A new line replaces the old one; lines never stack. The orange `trackingMessage` caption (`PlacementARView.swift:211-216`) merges into this line. Top priority wins.

| Priority | Condition | Exact line | Wording origin |
|---|---|---|---|
| 1 | Coaching overlay active | *(nothing: the overlay speaks. The bottom bar is already hidden, `:197`)* | Apple |
| 2 | `.notAvailable` or `.limited(.initializing)` | Hold still a moment. | App text |
| 2 | `.limited(.excessiveMotion)` | Slow down. | RoomPlan `.slowDown` |
| 2 | `.limited(.insufficientFeatures)` | Point at the meter or a corner. | Tracking reason, plus RoomPlan `.lowTexture` |
| 2 | `.limited(.relocalizing)` | Point back at the meter. | App text |
| 3 | *Optional, heuristic:* more than 60% of depth pixels are `low` for 2 s while tracking is `.normal` | Turn so the sun is behind you. | Twindo and Polycam outdoor advice (reported). **The trigger itself is unverified; tune it on device.** |
| 4 | Largest hole is more than 0.5 m to the user's left or right | Step left along the wall. / Step right along the wall. | App text |
| 4 | Largest hole is below the frame (ground) | Aim lower, at the ground by the wall. | App text |
| 4 | Hole is in view but more than 4 m away, or seen edge-on | Move closer. | Object Capture sample, RoomPlan |
| 4 | Camera is within 0.5 m of the wall | Step back. | RoomPlan "move farther from the wall" |
| 5 | Covered stop rule met | This wall and the ground in front of it are covered. | App text |
| 5 | Plateau with holes left | Some spots didn't scan. You can finish. | App text |
| — | Phone has no LiDAR (`supportsSceneReconstruction` is false) | Tracking lines only, plus this line once: "This phone can't scan depth. Clearance checks will stay unknown." | App text |

**The tint.** Draw `unseen` and `thin` cells in the required regions as one translucent neutral tint, for example white at about 35% alpha. Build it as a single `ModelEntity` from quads and rebuild it at about 2 Hz. Remove each cell's tint once it is `observed`. Do not use the placement tone colors (green, amber, red) for coverage.

**Do not:**
- Show a percent, a haptic, or copy that implies accuracy ("inch-accurate", "precise"). A haptic may mean "frames are being kept," nothing more.
- Lock Submit behind coverage, or remove the way back to the hub. Keep "Can't move farther" (`:231-237`) or rename it "Finish anyway."
- Ask the user to rescan a patch already marked observed.
- Ask the user to walk around the meter or behind a fence or shrubs.
- Copy magicplan's "stay in the same spot," or Object Capture's orbit, flip, or turntable prompts.
- Treat a cleared tint (or a green check on a patch) as "the rule passed." It means the patch was observed. Never clear tint for cells the app filled in by guessing.
- Coach holes on a phone without LiDAR.
- Use `rawFeaturePoints` counts as a quality threshold.
- Treat `worldMappingStatus == .mapped`, or the coaching overlay going away, as coverage.

---

## 5. Accuracy grades and how rules use them

### 5.1 Grades

These grades are computed for each check's required region(s), from the cell states in §3.4.

| Grade | Meaning |
|---|---|
| `missing` | Less than 60% of the region is `observed` or known-blocked, or a hole of footprint scale (30% of the region or more), or the surface was never within 4 m under normal tracking. |
| `uncertain` | 60–90% observed; or most views were low-confidence or `wontScan`; or depth and mesh disagree on more than 25% of occupied cells; or the result has not frozen (§3.7). |
| `locallyUsable` | At least 90% observed or known-blocked, the hole rule is met, and the result is frozen. Only this grade lets a mesh-based check pass. |
| `unavailable` | `supportsSceneReconstruction` is false. There is no mesh and no depth, so no mesh grade exists. Do not call it "thin." |

**What "locally usable" is worth.** For close, repeated, high-confidence surfaces, the sources report a 1–5 cm class:
- Luetzenburg, Kroon, and Bjørk 2021: about ±1 cm for objects larger than about 10 cm; 0.02 m mean between repeat scans of a small outdoor patch, with 92% of points within 5 cm.
- Costantino et al. 2022 (abstract): 1–3 cm.

Walked paths are coarser:
- Treccani et al. 2024: 1 cm in some areas and 10 cm in others.
- Luetzenburg 2021, cliff scale: RMS 0.69 m.

No retrieved study has taped an ARKit mesh of a house wall at 1–6 m outdoors, so treat 1–5 cm as the best case, not a spec.

**The meter lock adds its own spread.** The lock is the detector box center, averaged over five hits that all sit within about 15 cm of each other (`PlacementARView.swift:376-393`). Meter height, the transfer strip position, and meter-relative distances carry that spread on top of any mesh error. The 2 in guard band does not cover it. Tune the band on a device, and do not describe meter height as a 1–5 cm measurement.

### 5.2 Per rule (`Rules/BaseRuleSet.swift:19-32`)

| Rule id | Evidence | Range class | Pass needs | Conflict needs | No LiDAR |
|---|---|---|---|---|---|
| `austin-main-breaker`, `solar-or-two-batteries` | Typed amperage | Not a scan check | Unchanged | Unchanged | Unchanged. Separately, `:59-60` passes solar / two batteries from main-breaker amps. The team rule says not to infer the panel bus rating from main-breaker amperage. That rule is in the task brief; `AGENTS.md` at `be3346c` does not say it in those words (see `electrical-equipment-guide.md`). That needs its own fix. |
| `planning-footprint` | Mesh occupancy in `groundPad` | Close | `groundPad` is `locallyUsable` and has no obstacle voxel | An obstacle voxel with ≥ 2 good views inside the pad. This is red even if the rest of the pad is thin: it is an observed conflict. | Unknown: "needs a LiDAR scan" |
| `meter-distance` (≤ 20 ft) | Horizontal battery-to-meter ground point | Close if ≤ 4 m (about 13 ft), otherwise **walked (~0.1 m class)** | d ≤ 19.5 ft. Between 19.5 and 20.5 ft the rule returns unknown: "within about 0.1 m of the limit." At the suggested spot (about 4.6 ft from the meter) the band never matters. | d ≥ 20.5 ft | Works from planes. |
| `wall-distance` (≤ 1 ft) | Mesh wall hit in `wallPad`, or a detected vertical plane (`PlacementMeasuring.swift:233-240`) | Close | ≤ 10 in, and either `wallPad` is `locallyUsable` or the hit is on an `existingPlane` | ≥ 14 in | Plane hit, labeled "detected plane." A tape on an estimated plane never counts (already true, `:261-270`). |
| `not-in-front-of-window` | `window` faces in `wallPad` | Close | `wallPad` is `locallyUsable` and has no `window` face | `window` faces with ≥ 2 good views overlapping the cabinet | Unknown. **A `wontScan` patch in `wallPad` keeps this unknown: glass is exactly what does not mesh.** `none` is not "not a window." |
| `meter-panel-access` | Cabinet corners vs the 30 × 36 in slabs from the wall locks (no mesh) | Close | No overlap, with a 2 in margin | Overlap by more than 2 in | Works. `uncertain` if either lock normal is the `(0,0,1)` fallback (`PlacementARView.swift:2197`). Prefer the refit wall normal (§3.2) over a depth-patch normal. |
| `gas-meter-clearance` (≥ 3 ft) | Horizontal battery-to-gas mark | Close | ≥ 3 ft + 2 in, and the gas mark is not on an estimated plane | ≤ 3 ft − 2 in | Works from planes. "No gas meter" is an answer, not a scan: make it attested (`usedMeasuredEvidence: false`), not `.pass` (`BaseRuleSet.swift:171-173`, `EligibilityRule.swift:19-21`). |
| `transfer-switch-space` | Mesh in `wallTransfer` and `groundTransfer` | Close | Both regions `locallyUsable` on one side, with no obstacle there | Both sides blocked by obstacles with ≥ 2 good views | Unknown: "needs a LiDAR scan" |
| `meter-height` (6 ft; the code's 3 ft minimum is not in `AGENTS.md`) | Wall lock y minus ground y | Close | In range with a 2 in margin, and the ground comes from observed `groundMeterFoot` cells or an existing plane | Out of range by more than 2 in | If the ground is from an estimated plane only (`groundUnder`, `:2082`) and the foot is not observed: unknown, "ground under the meter not scanned." |
| `front-working-space` | Mesh occupancy in `groundMeterWork` | Close | `locallyUsable` with no obstacle | Obstacle with ≥ 2 good views | Unknown: "needs a LiDAR scan" |
| `meter-panel-same-wall` | Wall lock normals, plus an offset ≤ 0.30 m (`PlacementMeasuring.swift:493-501`) | Close if the meter and panel are ≤ 4 m apart; walked beyond that. The 0.30 m tolerance already exceeds the walked error class. | Unchanged | Unchanged | Works. `uncertain` if either normal is the `(0,0,1)` fallback. |

**Phones without LiDAR can never be green.** The footprint, window, working-space, and transfer checks all stay unknown on those phones. Say so on Review. In `survey.json`, `placement.lidarMeshAvailable` is already written, but it is also `false` on LiDAR phones without mesh classification and before any placement is committed. So add an explicit field keyed on `supportsSceneReconstruction(.mesh)` (for example `scan.meshAvailable`), plus `unavailable` grades on those four rules.

**Explanation text** should name the grade, for example: "Pad scan uncertain: two views were edge-on. Move closer and scan the ground again." Rules keep returning only pass, conflict, or unknown. Grades decide which of the three a rule returns; they do not add a fourth color.

---

## 6. Current code vs this design

**The research note is stale on one point.** It says, as `AGENTS.md:75` does, that footprint clearance and transfer-switch space are "still unmeasured." That is wrong for the code on `main`:
- The measurer scores both from the mesh, at ≥ 60% coverage (`PlacementMeasuring.swift:274-304`, `:443-467`).

It is still true in practice, for a different reason:
- The current Scan screen never places a battery. `case .battery: break` (`PlacementARView.swift:815-816`) ignores the tap. The first `bind` removes the battery rig (`:1157-1183`). The battery suggestion is gated on `walkStep == .battery` (`:1270`, `:2004`), but the only code that sets it to `.battery`, `syncGuide` (`:1972`), has no caller. The tone passed to the AR view is hardcoded `.incomplete` (`:184`).
- Even a suggested battery would not count: the snapshot sets `batteryPosition` only after `confirmBatterySpot()` (`:2212-2221`, `:1983-1989`), which also has no caller.
- So `batteryPlaced` is always false. The footprint, wall, meter-distance, window, access, and working-space checks all stay unknown. So does the gas distance, unless the user taps "No gas meter", which passes today (§5.2).
- Transfer-switch space *can* be scored: it hangs off the meter wall lock alone (`PlacementMeasuring.swift:606-608`). But it is scored on a stale snapshot (see "Snapshot freshness" below).

| Element | `origin/main` today | Gap vs this design |
|---|---|---|
| Coaching overlay | Used: `goal = .tracking`, `activatesAutomatically` (`PlacementARView.swift:630-637`). The bottom bar hides while it is active (`:197`). Detection pauses (`:780-796`). | Fine for tracking. Add `coachingOverlayViewDidRequestSessionReset` handling. There is no coverage goal to use (§2). |
| Tracking state | Mapped to long sentences (`:2281-2301`) shown as an orange caption (`:211-216`). Blocks taps and locks (`:2273-2279`, `:1630`). The detector runs only on `.normal` (`Placement/EquipmentDetecting.swift:214-216`). | Mesh samples are accepted whatever the tracking state. There are no `sessionWasInterrupted` / `sessionInterruptionEnded` handlers, and results are not reset on relocalization. The world root is `AnchorEntity(world: .zero)` (`:648-650`) and marks are raw world points (`:548-553`), with no `ARAnchor`s, so they never get the transform updates ARKit gives anchors. The copy should become the short lines in §4. |
| Scene depth | `smoothedSceneDepth` if supported, else `sceneDepth` (`:618-622`). Used for the equipment-lock depth patch: `low` is rejected, the range is 0.2–5 m (`:1730-1732`). Also used for PLY color occlusion, with tolerance `0.15 + 0.05·z` (`:2600-2626`). | Not used for coverage at all. The camera-plane z math at `:2612-2613` is exactly what §3.4 needs. It is `private static`, so copy the math and use the §3.8 tolerance. (Using raw `sceneDepth` alongside smoothed for view counting is an option. Whether both semantics can be enabled together is **unverified**; smoothed is fine for a start.) |
| Mesh config | `.meshWithClassification` sets `lidarMeshAvailable = true` (`:610-613`). `.mesh`-only leaves it false (`:614-617`), and samples need a classification (`:2500`). | Fine as long as every LiDAR phone also supports classification (**unverified here**). The `unavailable` grade should key on `supportsSceneReconstruction(.mesh)`, not on classification. |
| Mesh sampling | The centroid of every 2nd face (`:2488`, `:2500-2512`), kept if within 8 m horizontally of the battery, meter, panel, or working space (`:2362-2384`). Processing runs on the main thread: the session delegate is on main (`EquipmentDetecting.swift:249`, `PlacementARView.swift:968-993`). | Replace the 8 m cylinder with the box in §3.2. Sample all faces plus their vertices, not every second centroid. Run the coverage math off main. |
| Coverage score | `ScanIndex`: 10 cm cells, and any face ever meshed counts as seen (`PlacementMeasuring.swift:704-775`). Ground coverage counts a column if it holds a face at *any* height (`:748`), so a porch ceiling, an eave, or a wall face over the pad counts as "ground seen." `minScanCoverage = 0.6` (`:189`) gates footprint (`:291`), working space (`:424`), and transfer (`:458`). | No view count, view angle, tracking check, or depth confidence. No `thin` or `wontScan` states. Ground cells should need ground-height, upward-facing faces or an obstacle. |
| Window check | `hasScan` within 2 m (`:341`). Then *any one* wall face inside the cabinet span passes it (`:362-366`). | One face is not coverage. A hole behind the cabinet (glass) must stay unknown. |
| Obstacles | Floor and ceiling are ignored. `none` (`.other`) counts as an obstacle unless it lies on the host wall (`:632-640`). Height filter 8 cm, and at least 2 samples (`:185-187`). | Sloped yard ground labeled `none` that rises more than 8 cm across the pad reads as an obstacle. Use the geometric ground test (§3.3) and require ≥ 2 good views. |
| Look-around | A pose checklist: be ≥ 8 ft from the lock, then face 40–140° left and right (`PlacementARView.swift:25-31`, `:1841-1875`). "Can't move farther" skips it (`:231-237`, `:1833-1838`). Copy: "Move farther away." / "Look left." / "Look right." (`:295-299`). | Not tied to the mesh. On LiDAR phones, replace it with hole-driven lines and the tint. Keep the escape button. It can stay as-is on phones without LiDAR. |
| Snapshot freshness | `emitPlanesIfNeeded` returns early without a battery rig (`:1040-1041`). So mesh growth after the last lock or gas action never reaches `scene`, and Submit commits that stale snapshot (`:333-336`). | Coverage, and today's transfer-switch result, are computed from old mesh. Emit when any lock exists. |
| Sticky transfer result | `applying()` keeps the old transfer value whenever the new one is nil (`PlacementMeasuring.swift:167-169`). Footprint, window, and working space were fixed in `be3346c` to clear instead (`:152-166`). | Transfer still carries a stale true/false. |
| Estimated planes | Estimated-plane tape is excluded from the wall distance (`:261-270`). Wall hits use only existing vertical planes (`PlacementARView.swift:2180-2194`). But the meter ground (`groundUnder`, `:2082`), `groundPosition` (`:1590-1596`), and the gas mark (`:1583-1586`) all accept `.estimatedPlane`, and their capture method is dropped. | Meter height and gas distance can rest on an estimated plane without any label. Carry the method through and grade those checks `uncertain`. |
| Wall normal fallback | `interpretWallHit` uses `(0,0,1)` when the hit has no `ARPlaneAnchor` (`:2194-2205`). This is probably rare, since these raycasts only allow `.existingPlaneGeometry` (`:2181`, `:2188`). Depth-patch locks get their normal from a 9 × 9 patch on the meter (`:1741`, `:1769-1787`). | Same-wall and access checks can use a fake or noisy normal. Mark the source and grade `uncertain` when it is not a plane anchor. |
| Phones without LiDAR | Mesh checks return nil (`PlacementMeasuring.swift:275`, `:340`, `:407`, `:457`), so they are unknown. Wall distance falls back to vertical planes (`:239`, `:540-571`). Locks use the wall plane first (`PlacementARView.swift:1687`, `:1917`). | Review never says "mesh unavailable." `lidarMeshAvailable` is stored (`Survey/SurveySession.swift:192`) and lands in `survey.json`, because the whole session is encoded (`Review/SurveyExporting.swift:89-98`). But `false` there also means "`.mesh` without classification" or "nothing committed yet," so it cannot say "no LiDAR." |
| Manual tape | The measurement mode code exists (`PlacementARView.swift:1415-1440`), but this screen passes `measurementMode: false` (`:175`). | Not reachable on this screen. Nothing to grade there yet. |
| `worldMappingStatus`, `rawFeaturePoints` | Not used. | Good. Keep it that way. |

---

## 7. Implementation tasks (in order, sized for a Cursor agent)

Hackathon rules apply: no unit tests (`AGENTS.md`), keep it simple, Apple frameworks only.

1. **Keep the snapshot fresh.** In `emitPlanesIfNeeded` (`Placement/PlacementARView.swift:1040-1046`), emit when a meter lock, panel lock, or battery rig exists, not only the battery rig. Keep the 0.4 s throttle.
2. **Add the box and grids.** New file `Placement/ScanCoverage.swift`. Add `ScanBox` (built from the meter wall frame, §3.2), the wall and ground grids, 3D obstacle voxels, and a per-cell struct `{occupied, goodViews, lowConf, disagree, emptyLooks, lastViewPose}`. Keep it pure Swift and `Sendable`, like `CorePlacementMeasurer`.
3. **Fill the grids from the mesh.** Rasterize face centroids and vertices inside the box from `meshClouds` (`PlacementARView.swift:561`), sorting them into wall, ground, or obstacle by unit normal and height (§3.3), not by class. `meshClouds` has no normals, so compute each face normal from its triangle and normalize it. Rebuild when mesh anchors update, off the main thread.
4. **Per-frame observation pass.** In `session(_:didUpdate:)` (`:953-966`), at 5 Hz while tracking is `.normal`, copy the camera transform, intrinsics, and `EquipmentPixelBuffer.depthSample(...)` (`Placement/EquipmentDetecting.swift:289-324`). Run §3.4 on a serial queue, using `EquipmentScanBridge` (`:180-258`) as the pattern. Reuse the projection from `MeshColorCache.sample` (`PlacementARView.swift:2610-2626`).
5. **Grades in the evidence.** Add `enum ScanGrade { missing, uncertain, locallyUsable, unavailable }`. Add a small `ScanCoverageEvidence` (`meshAvailable`, per-rule grades, observed/total cells per region) to `PlacementSceneSnapshot` / `PlacementMeasurements` (`Placement/PlacementMeasuring.swift:61-129`) and `PlacementEvidence` (`Survey/SurveySession.swift:184`). Carry it through `applying()`.
6. **The measurer uses grades.** Replace `ScanIndex.groundCoverage` / `wallCoverage` and `minScanCoverage` (`PlacementMeasuring.swift:189`, `:704-775`) with region grades from step 5. Require ≥ 2 good views for an obstacle. Treat upward-facing ground-height faces as ground whatever their class (`:632-640`). Normalize `ClassifiedMeshSample.normal` where it is built (`PlacementARView.swift:2506-2511`) so `isOnWall` and `horizontalUnit` work as intended (§3.3). Make the window check need `wallPad` to be `locallyUsable` instead of one face (`:339-367`).
7. **The rules read grades and guard bands.** In `Rules/BaseRuleSet.swift`, the footprint, window, working-space, and transfer rules pass only on `locallyUsable`, and their unknown text names the grade. Add guard bands to `distanceOutcome` (`:252-262`): 0.5 ft for the meter distance, 2 in for close checks, with the band itself returning unknown. Make "No gas meter" attested, not `.pass` (`:171-173`).
8. **One coaching line.** Add an `onCoverageLine` callback next to `onTrackingStatus` (`PlacementARView.swift:531`, `:191`). Render one line in `bottomBar` (`:206-261`) using the §4 table and priorities. Replace the long tracking strings at `:2281-2301` with the short lines.
9. **The tint.** Rebuild one `ModelEntity` from quads over `unseen` and `thin` cells at 2 Hz (`MeshResource.generate(from:)`; the target is iOS 17). Use a neutral color and never a tone color. Hide it while coaching is active.
10. **Replace look-around with coverage on LiDAR phones.** The `.lookAround` cue (`:33-39`, `:116-122`, `:295-299`) ends at the covered or plateau stop rule, or when the user taps "Can't move farther" (rename it "Finish anyway"). Keep today's pose checklist for phones without LiDAR.
11. **Build the pad region before the battery exists.** Compute the suggested pad from the `suggestBatterySpotIfNeeded` math (`:2003-2027`) as a required region, even while the battery is not rendered. Battery placement itself belongs to the placement workstream; only the region is needed here.
12. **Freeze and relocalization.** Implement §3.7. Add `sessionWasInterrupted`, `sessionInterruptionEnded`, and `coachingOverlayViewDidRequestSessionReset` handlers that unfreeze and re-grade. Fix the sticky transfer result (`PlacementMeasuring.swift:167-169`) so it clears like the footprint result.
13. **Label shaky endpoints.** Keep the capture method for the meter ground (`groundUnder`, `PlacementARView.swift:2077-2089`) and the gas mark (`:1583-1586`). Flag the `(0,0,1)` normal fallback (`:2197`). Grade the checks that use them `uncertain`.
14. **The no-LiDAR path.** When `supportsSceneReconstruction(.mesh)` is false, skip coverage, set the mesh-based grades to `unavailable`, show only tracking lines plus the one-time notice, and write an explicit `scan.meshAvailable: false`. Do not rely on `placement.lidarMeshAvailable` for this: it is also false on `.mesh`-only phones (§6). Files: `PlacementARView.swift`, `Survey/SurveySession.swift`, `Review/ReviewView.swift`.
15. **Review screen.** Show the grade next to each placement rule. Show the meter distance as "about X ft (walked, ~0.1 m class)" when it is over 4 m. Do not show a coverage percent as accuracy. File: `Review/ReviewView.swift`.
16. **An afternoon on a device (no code).** Tune §3.8 outdoors. Tape the wall clearance at about 1 m and the meter distance at about 6 m, in sun, on siding and a glass meter cover. That is the open gap the research names.

Also: `AGENTS.md:75` still says footprint and transfer-switch space are unmeasured. Whoever owns that file should update it to say what §6 says.
