# Site Scan Viewer

A browser tool for reviewing a Base Site Survey export. Drop in the shared `BaseSiteSurvey-*.zip`, or loose `scene.ply` and optional `survey.json`. It shows the LiDAR scan in 3D and answers one question: **where does this scan support a possible Base Core placement?**

Nothing is uploaded; the files stay in the browser. Prototype only: not an electrical inspection, code review, or installation approval.

If the packet has no usable property coordinates, the viewer still draws and evaluates the placement grid using the bundled Austin defaults. It labels that fallback as a manual-review item. Coordinates explicitly outside the supported Austin region still produce “Manual review required” instead of applying the wrong regional rules.

Built with React, Vite, Tailwind, [shadcn/ui](https://ui.shadcn.com), and three.js.

## Run it

From anywhere:

```bash
npm --prefix /path/to/base-ar/tools/viewer install
npm --prefix /path/to/base-ar/tools/viewer run dev
```

Open http://localhost:5173 and drop the packet or files. In Claude Code, the `viewer` entry in `.claude/launch.json` does the same.

`npm run build` writes one self-contained `dist/index.html`, about 1 MB with scripts and fonts inlined. Send that file to a reviewer; they open it and drop in the export. With a server, `?ply=…&survey=…&rules=…` loads files served next to the page.

It needs an export from the current app: per-face ARKit labels (`property uchar label`) and `mark` header lines. An older export is rejected with a message.

## What you see

Small colored markers cover scanned ground within 20 ft of the meter. Each marker is a possible battery-center position, not the battery footprint:

| Square | Meaning |
|---|---|
| Green | A possible battery center. Every 10 cm square in its complete 3 × 3 ft area and side-clearance regions is green, and every other measured scan check passes. |
| Red | Within 1 ft of a house wall, but a check fails. Hover to see which. |
| Amber | Within 1 ft of a house wall, but not enough ground was scanned to tell. |
| Faint gray | Scanned, but no battery can stand here. Hover for why, for example "About 4 ft from the nearest house wall." |
| Pale amber | Beside a surface scanned too low to confirm it is a house wall: a fence, a unit, or a wall that needs scanning higher. |
| None | That ground was not scanned. |

Select a center to see the cabinet and every 10 cm square in the full 3 × 3 ft planning footprint and both full-depth side-clearance regions. The selected spot is scan-eligible only when **all of those squares are green**. One red square makes the spot an observed conflict; one amber square makes it need more scan. Candidate centers form a narrow ribbon along the house because the cabinet must be within 1 ft of the wall while its full planning area remains outdoors. A dashed ring marks the 20 ft reach from the meter. Purple dots are the meter taps, teal the panel, pink the gas meter. The purple box beside the meter is the transfer-switch space.

- **Verdict** at the top of the panel: candidate found; candidate found with information missing; observed conflict; more scan needed (with what to scan next); or manual review. It is never installation approval.
- **Selected spot**: the best spot is chosen on load. Click any colored cell, or drag the battery, to see every check for that spot. "Spot from the app" shows where the homeowner or the app placed it.
- **Site** and **Electrical** cards: checks that apply to the whole site. The breaker and solar checks come from `survey.json`.
- **View**: camera color or ARKit labels, 3D or Top, and switches for the grid, the gray floor layer, cutting away everything above 2.2 m (eaves, roofs, canopy), and the ceiling.

## How a spot is checked

Each cell is a possible battery center. The cabinet (30.68 in W × 35.9 in H × 22 in D) is turned so its back faces the nearest house wall.

- A **house wall** is a flat patch of at least 20 wall-labeled faces that rises past 2 m in the scan. Its outdoor side is the side its face normals point to, which is toward where the phone was. AC units, bushes, fences, meter boxes, and downspouts are obstacles, not walls to back onto.
- The spot is a **candidate** only if the cabinet's back is within 1 ft of that wall. Everything else is gray, with the reason.

At a candidate, the checker runs:

| Check | Rule |
|---|---|
| Within 1 ft of the wall | Cabinet back to wall |
| Within 20 ft of the meter | Horizontal distance to the meter tap |
| 3 ft from the gas meter | Needs the gas meter marked, or "no gas meter" in `survey.json` |
| 3 × 3 ft pad clear | No obstacle faces from 8 cm up to cabinet height |
| 3 ft clear on both sides | No obstacles beside the cabinet |
| Not in front of a window | No window on the wall above the cabinet, up to 2.5 m |
| Clear of meter and panel access | Outside their own 30 × 36 in working space |
| Leaves transfer-switch space | Outside the 13 in × 3 ft box beside the meter |

Clear only counts when every 10 cm square in the complete placement envelope holds floor-like scanned surface and no rasterized obstacle triangle occupies it. Coverage from walls, roofs, or objects above the ground does not count. Any unscanned square is amber, never green. Faces under 8 cm (grass, mulch, and the rounded seam where the wall meets the ground) are not obstacles. The separate transfer-switch wall-area check still requires at least 90% observed coverage with no adjacent missing-cell cluster.

Site-wide checks: meter height no higher than 6 ft, meter and panel on one wall, and transfer-switch space on either side of the meter (the clear side is used). Published requirements the packet cannot establish remain explicit manual-review items.

Sources: [electrical and spacing requirements](https://help.basepowercompany.com/en/articles/10280705) ("cannot be placed in front of electrical equipment … or windows") and [placement requirements](https://help.basepowercompany.com/en/articles/10280641) ("3 feet of clearance from gas meters, AC units, fences, other batteries, or other obstructions"; "3 feet of clearance on both sides").

## What was built, and why

The app already measured distances and ran the rules for the one spot the user placed. The question was whether the scan could answer "can a battery go here?" on its own.

1. **No machine learning.** There are no labeled installs to train on, and the rules are fixed distances and boxes. Checking them directly gives an answer every reviewer can trace to a measurement.
2. **A Python prototype on `scene 4.ply`** slid the battery along the meter wall in 10 cm steps. It found a clear 4.9–9.2 ft stretch past the panel, and four problems in the app's checks (see below).
3. **Offline review, not only on-device.** The phone gives the homeowner immediate feedback. The full export goes to a reviewer, who can re-check it with other rules, for a region without rules, or when something looks wrong.
4. **This viewer** replaced the Python script. The single strip along the meter wall became a grid over every cell within reach, which finds spots on other walls and around corners. It was then rebuilt on shadcn/ui.
5. **The whole scanned floor** was added after "why are the squares not on all the floor?" Gray cells with reasons make it clear the whole yard was considered, and pale amber cells say what to scan next.
6. **The window and side-clearance rules** were added after checking Base's pages. The first window check only looked at the cabinet's 36 in height, so a battery right under a typical window passed. On `scene 8.ply`'s real windows, the fix blocks 105 cells instead of 70. "3 ft clear on both sides" was not encoded anywhere before.

## Changes made to the app for this

In `BaseAR/`, committed in `a4c1bb6`:

- **ARKit face labels in `scene.ply`.** Each face carries `property uchar label` with ARKit's raw classification (0 none, 1 wall, 2 floor, 3 ceiling, 4 table, 5 seat, 6 window, 7 door, 255 overlay). Before, the labels were discarded on export.
- **`mark` header lines.** The exact taps: `meter_ground`, `meter_wall` with its normal, `panel_ground`, `panel_wall` with its normal, `gas_meter`, `battery` or `battery_suggested` with yaw, `working_space`, and `transfer_switch_preferred_side`. Before, tools had to guess them from the colored overlay.
- **The overlay export was restored.** A merge (`acf59e8`) had dropped the battery, markers, and check comments from `scene.ply`.
- **Four fixes in `CorePlacementMeasurer`**, all found on scene 4:
  - Unscanned ground no longer counts as clear. The check now needs 60% coverage instead of "any scan within 2 m".
  - The 2 cm wall-to-ground seam no longer blocks the pad. The minimum obstacle height is now 8 cm, and one stray face is ignored.
  - The transfer switch is checked on both sides of the meter.
  - A new rule keeps the battery out of the meter's and panel's working space.
- **The wall behind the cabinet** must face the cabinet's back, sit behind it, and be more than 10 cm up. A sideways seam face used to win at 0.00 ft.

## How it was checked

- `scene 4.ply` predates labels and marks, so a stand-in was built from it: labels from surface angles, marks from its overlay markers. Result: installable. The meter-wall run matches the Python prototype. The app's suggested spot is correctly flagged for standing in front of the meter and panel.
- The app's own Swift measurer was compiled on a Mac and run on the same mesh. It agreed with the checker at five test spots.
- `scene 8.ply` (indoors, real labels, no meter tap) gives "manual review", and the label view matches the room.
- Checked in the browser at desktop and phone widths, light and dark themes, with no console errors. Analysis takes about 4 s for a 400k-face scan.

## Known gaps

- The viewer's strict all-cells-green placement rule, 8 cm obstacle floor, and 2 m house-wall heuristic still need calibration across more outdoor scans. Uncertainty remains amber.
- The app's Swift checks do not yet have the window-above-cabinet fix, the 3 ft side clearance, or the 2 m house-wall rule.
- Rules are copied by hand between `checker.js` and `BaseAR/Rules/BaseRuleSet.swift`. A shared rules file would need an Xcode project change.
- Ground suitability, property-line setbacks, doors, permits, equipment condition, panel location, and tight-space walk-by clearance stay with manual review.

## Files

- `src/lib/checker.js`: parsing, geometry, and rules. A plain ES module with types in `checker.d.ts`. Node can import it for testing.
- `src/lib/scene.ts`: the three.js view (mesh, grid layers, marks, reach ring, battery, pointer handling).
- `src/lib/zip.ts`: dependency-free local extraction of `scene.ply` and `survey.json` from the app's ZIP packet.
- `src/App.tsx`: the panel, built from shadcn components in `src/components/ui`.

The thresholds at the top of `checker.js` mirror `BaseAR/Rules/BaseRuleSet.swift` and `CorePlacementMeasurer`. Change both together. To try other rules without editing code, drop a `.json` with any of the `AUSTIN` keys.
