// Base Site Survey — offline siting checker.
// Reads the app's scene.ply (mesh, ARKit face labels, `mark` header lines) and optional survey.json,
// then tests every 10 cm ground cell within reach of the meter as a possible battery center.
// Plain ES module with no dependencies: the viewer bundles it, and Node can import it for testing.
// Prototype only. Not an electrical inspection, code review, or installation approval.

const FT = 0.3048, IN = 0.0254;
const L = { NONE: 0, WALL: 1, FLOOR: 2, CEILING: 3, TABLE: 4, SEAT: 5, WINDOW: 6, DOOR: 7, OVERLAY: 255 };
const LABEL_NAMES = ["none", "wall", "floor", "ceiling", "table", "seat", "window", "door"];

// Viewer defaults from Base's published Austin guidance. Drop a rules JSON into the viewer to override any key.
const AUSTIN = {
  id: "austin",
  main_breaker_amps: [150, 200],
  panel_amps_for_solar_or_two_batteries: 200,
  max_meter_distance_ft: 20,
  max_wall_distance_ft: 1,
  min_gas_distance_ft: 3,
  footprint_side_ft: 3,
  side_clearance_ft: 3,                // clear on both sides: "3 feet of clearance from … AC units, fences, other batteries"
  // Base publishes a 6 ft maximum. It does not publish a 3 ft minimum.
  meter_height_ft: [0, 6],
  working_space_in: [30, 36],          // width along the wall, depth out from the equipment
  transfer_switch_in: [13, 36, 30],    // along the wall, tall, out from the wall
  battery_in: [30.68, 35.9, 22],       // Base Core width, height, depth
  // Rough Austin area on the phone's property fix. Outside it, the answer is manual review.
  bbox: { lat: [30.05, 30.6], lon: [-98.05, -97.45] },
};

// Scan-quality tuning, matching CorePlacementMeasurer.
const CELL = 0.1;              // grid and coverage cell, m
const MIN_OBSTACLE_H = 0.08;   // grass, mulch, and the wall-to-ground seam are not obstacles
const MIN_WALL_COVERAGE = 0.9; // transfer-switch wall coverage; placement-envelope cells are stricter (all must pass)
const ROOF_H = 2.2;            // eaves and porch roofs are not obstacles
const HOUSE_WALL_H = 2.0;      // the wall a battery backs onto must be scanned at least this high
const WINDOW_TOP_H = 2.5;      // "in front of a window": any window on the wall above the cabinet, up to the eaves

const SOURCE_SPACING = "Base electrical and spacing requirements";
const SOURCE_PHOTOS = "Base home photo-review guidance";

const CHECK_META = {
  wall_distance: { title: "Within 1 ft of the wall", requirement: "Cabinet back must be within 1 ft of the exterior wall.", source: SOURCE_SPACING },
  meter_distance: { title: "Within 20 ft of the meter", requirement: "Battery should be within 20 ft of the electric meter.", source: SOURCE_SPACING },
  gas_clearance: { title: "3 ft from the gas meter", requirement: "Battery must remain at least 3 ft from a gas meter.", source: SOURCE_SPACING },
  footprint: { title: "3 × 3 ft placement area", requirement: "The complete 3 × 3 ft planning footprint must be outdoors, scanned, and clear.", source: SOURCE_SPACING },
  side_clearance: { title: "3 ft clear on both sides", requirement: "Keep 3 ft clear beside both sides of the 3 × 3 ft placement area.", source: SOURCE_PHOTOS, assumption: "Prototype geometry treats each side clearance as a full-depth 3 ft rectangle." },
  not_in_front_of_window: { title: "Not in front of a window", requirement: "Battery cannot be placed in front of a window.", source: SOURCE_SPACING },
  meter_and_panel_access: { title: "Clear of meter and panel access", requirement: "Battery cannot stand in front of electrical equipment.", source: SOURCE_SPACING, assumption: "Prototype geometry uses a 30 × 36 in ground keep-out area." },
  transfer_switch_space: { title: "Leaves transfer-switch space", requirement: "Leave clear wall and working space beside the meter for the transfer switch.", source: SOURCE_SPACING, assumption: "Prototype geometry uses a 13 in × 3 ft wall box extending 30 in outward." },
  meter_height: { title: "Meter no higher than 6 ft", requirement: "Electric meter must be no higher than 6 ft above the ground.", source: SOURCE_SPACING },
  meter_and_panel_same_wall: { title: "Meter and panel share a wall", requirement: "Meter and main breaker box must share the same wall.", source: SOURCE_SPACING },
  transfer_switch: { title: "Transfer-switch space", requirement: "A clear mounting and working area is needed beside the meter.", source: SOURCE_SPACING, assumption: "Prototype geometry uses a 13 in × 3 ft wall box extending 30 in outward." },
  main_breaker: { title: "Austin main breaker 150–200 A", requirement: "In Austin, the main breaker must be 150–200 A.", source: SOURCE_SPACING },
  solar_or_two_batteries: { title: "Solar or 2 batteries requires 200 A", requirement: "Solar or a dual-battery system requires a 200 A panel.", source: SOURCE_SPACING },
  exterior_install: { title: "Exterior installation", requirement: "Base batteries are installed outdoors, not inside or in a garage.", source: SOURCE_PHOTOS },
  single_main_breaker: { title: "One main breaker box", requirement: "The home must have only one main breaker box.", source: SOURCE_SPACING },
  panel_not_in_closet: { title: "Panel is not in a closet", requirement: "The main breaker box cannot be in a closet.", source: SOURCE_SPACING },
  equipment_condition: { title: "Meter and conduit condition", requirement: "Meter and conduit must be securely attached and undamaged.", source: SOURCE_SPACING },
  tight_alley_clearance: { title: "Tight-space walk-by clearance", requirement: "Tight spaces need a clear walk-by path and clearance from fixed features.", source: SOURCE_SPACING },
  rules_region: { title: "Rules region", requirement: "Confirm that the property is in Austin before relying on Austin-specific requirements.", source: SOURCE_SPACING },
};

function withMeta(checks) {
  for (const [key, value] of Object.entries(checks)) {
    const meta = CHECK_META[key];
    if (!meta) continue;
    value.title = meta.title;
    value.requirement = meta.requirement;
    value.source = meta.source;
    if (meta.assumption) value.assumption = meta.assumption;
    value.evidence = value.kind === "scan" ? "scan" : value.kind === "manual" ? "manual" : "survey";
  }
  return checks;
}

// ---------- reading ----------

function parsePLY(text) {
  const headerEnd = text.indexOf("end_header");
  if (!text.startsWith("ply") || headerEnd < 0) throw new Error("Not a PLY file.");
  const header = text.slice(0, headerEnd).split("\n");
  if (!header.some((l) => l.startsWith("format ascii"))) throw new Error("Only ASCII PLY is supported (the app writes ASCII).");
  if (!header.some((l) => l.trim() === "property uchar label")) {
    throw new Error("This scene.ply has no face labels. Export it again from the current app.");
  }
  let nv = 0, nf = 0;
  const comments = [];
  for (const l of header) {
    if (l.startsWith("element vertex")) nv = +l.split(/\s+/)[2];
    else if (l.startsWith("element face")) nf = +l.split(/\s+/)[2];
    else if (l.startsWith("comment ")) comments.push(l.slice(8).trim());
  }
  const body = text.slice(text.indexOf("\n", headerEnd) + 1).split("\n");
  const positions = new Float32Array(nv * 3), colors = new Uint8Array(nv * 3);
  for (let i = 0; i < nv; i++) {
    const p = body[i].split(" ");
    positions[i * 3] = +p[0]; positions[i * 3 + 1] = +p[1]; positions[i * 3 + 2] = +p[2];
    colors[i * 3] = +p[3]; colors[i * 3 + 1] = +p[4]; colors[i * 3 + 2] = +p[5];
  }
  const faces = new Uint32Array(nf * 3), labels = new Uint8Array(nf);
  for (let f = 0; f < nf; f++) {
    const p = body[nv + f].split(" ");
    faces[f * 3] = +p[1]; faces[f * 3 + 1] = +p[2]; faces[f * 3 + 2] = +p[3];
    labels[f] = +p[4];
  }
  return { positions, colors, faces, labels, comments, marks: readMarks(comments) };
}

// `mark <name> x y z [normal nx ny nz] [yaw r]` or `mark <name> <word>`, as MeasurementOverlay writes them.
function readMarks(comments) {
  const marks = {};
  for (const line of comments) {
    const p = line.split(/\s+/);
    if (p[0] !== "mark") continue;
    if (p.length === 3) { marks[p[1]] = p[2]; continue; }
    const m = { p: [+p[2], +p[3], +p[4]] };
    for (let i = 5; i < p.length;) {
      if (p[i] === "normal") { m.normal = [+p[i + 1], +p[i + 2], +p[i + 3]]; i += 4; }
      else if (p[i] === "yaw") { m.yaw = +p[i + 1]; i += 2; }
      else i++;
    }
    marks[p[1]] = m;
  }
  return marks;
}

// ---------- small vector helpers (horizontal work uses x and z) ----------

const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const add = (a, b, s = 1) => [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s];
const flat = (v) => { const l = Math.hypot(v[0], v[2]); return l < 1e-6 ? null : [v[0] / l, 0, v[2] / l]; };
const alongOf = (out) => [out[2], 0, -out[0]];  // cross(up, out)
const hdist = (a, b) => Math.hypot(a[0] - b[0], a[2] - b[2]);
const overlap = (a0, a1, b0, b1) => a0 < b1 && b0 < a1;
const key = (i, j) => (i + 50000) * 100000 + (j + 50000);
const col = (v) => Math.floor(v / CELL);

function coverageQuality(seen, width, height) {
  const total = width * height;
  const ratio = total ? seen.size / total : 0;
  const visited = new Set();
  let largestMissing = 0;
  for (let u = 0; u < width; u++) for (let v = 0; v < height; v++) {
    const start = u * height + v;
    if (seen.has(start) || visited.has(start)) continue;
    let size = 0;
    const queue = [start];
    visited.add(start);
    for (let q = 0; q < queue.length; q++) {
      const current = queue[q], cu = Math.floor(current / height), cv = current % height;
      size++;
      for (const [du, dv] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
        const nu = cu + du, nv = cv + dv, next = nu * height + nv;
        if (nu < 0 || nv < 0 || nu >= width || nv >= height || seen.has(next) || visited.has(next)) continue;
        visited.add(next); queue.push(next);
      }
    }
    largestMissing = Math.max(largestMissing, size);
  }
  return { ratio, largestMissing, complete: ratio >= MIN_WALL_COVERAGE && largestMissing <= 1 };
}

// ---------- scene index ----------

// Rasterize every triangle at the same 10 cm resolution as the decision grid. Using only a face centroid can miss a
// fence edge or large triangle that crosses a clearance box while its centroid sits outside it.
function buildScene(ply) {
  const { positions: P, faces: F, labels: Lb } = ply;
  const xs = [], ys = [], zs = [], nxs = [], nys = [], nzs = [], lbs = [];
  for (let f = 0; f < Lb.length; f++) {
    if (Lb[f] === L.OVERLAY) continue;
    const a = F[f * 3] * 3, b = F[f * 3 + 1] * 3, c = F[f * 3 + 2] * 3;
    const ux = P[b] - P[a], uy = P[b + 1] - P[a + 1], uz = P[b + 2] - P[a + 2];
    const vx = P[c] - P[a], vy = P[c + 1] - P[a + 1], vz = P[c + 2] - P[a + 2];
    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    const len = Math.hypot(nx, ny, nz);
    if (len < 1e-12) continue;
    nx /= len; ny /= len; nz /= len;
    const ab = Math.hypot(ux, uy, uz), ac = Math.hypot(vx, vy, vz);
    const bc = Math.hypot(P[c] - P[b], P[c + 1] - P[b + 1], P[c + 2] - P[b + 2]);
    const steps = Math.max(1, Math.min(100, Math.ceil(Math.max(ab, ac, bc) / CELL)));
    for (let i = 0; i <= steps; i++) for (let j = 0; j <= steps - i; j++) {
      const u = i / steps, v = j / steps, w = 1 - u - v;
      xs.push(P[a] * w + P[b] * u + P[c] * v);
      ys.push(P[a + 1] * w + P[b + 1] * u + P[c + 1] * v);
      zs.push(P[a + 2] * w + P[b + 2] * u + P[c + 2] * v);
      nxs.push(nx); nys.push(ny); nzs.push(nz); lbs.push(Lb[f]);
    }
  }
  const S = { x: Float32Array.from(xs), y: Float32Array.from(ys), z: Float32Array.from(zs),
    nx: Float32Array.from(nxs), ny: Float32Array.from(nys), nz: Float32Array.from(nzs),
    label: Uint8Array.from(lbs), count: xs.length };
  // 10 cm columns: every sample, walls only, floor only.
  S.all = new Map(); S.walls = new Map(); S.floors = new Map();
  const push = (m, kk, i) => { const l = m.get(kk); if (l) l.push(i); else m.set(kk, [i]); };
  for (let i = 0; i < S.count; i++) {
    const kk = key(col(S.x[i]), col(S.z[i]));
    push(S.all, kk, i);
    const lb = S.label[i];
    if ((lb === L.WALL || lb === L.DOOR || lb === L.WINDOW) && Math.abs(S.ny[i]) < 0.45) push(S.walls, kk, i);
    if (lb === L.FLOOR && Math.abs(S.ny[i]) > 0.7) push(S.floors, kk, i);
  }
  return S;
}

function eachNear(map, x, z, r, fn) {
  const i0 = col(x - r), i1 = col(x + r), j0 = col(z - r), j1 = col(z + r);
  for (let i = i0; i <= i1; i++) for (let j = j0; j <= j1; j++) {
    const l = map.get(key(i, j));
    if (l) for (const s of l) fn(s);
  }
}

function median(a) { if (!a.length) return null; a.sort((p, q) => p - q); return a[a.length >> 1]; }

// Ground height near a point, from floor-labeled faces, so a sloped yard still works.
function groundNear(S, x, z, fallback, below = Infinity) {
  for (const r of [0.35, 0.8, 1.5]) {
    const ys = [];
    eachNear(S.floors, x, z, r, (i) => { if (S.y[i] < below) ys.push(S.y[i]); });
    if (ys.length >= 5) return median(ys);
  }
  return fallback;
}

// The house wall a battery at (x, z) would back onto: nearest wall faces, their shared plane, and its outdoor side.
// When there is none, `fail` says why: "none" (no wall faces nearby), "small" (a box, pipe, or post),
// or "low" (a flat surface that never reaches house-wall height in the scan; `top` is how high it goes).
function findWall(S, x, z, groundY, preferOut) {
  let best = -1, bestD = 0.9;
  eachNear(S.walls, x, z, 0.9, (i) => {
    const h = S.y[i] - groundY;
    if (h < 0.1 || h > 2.5) return;
    const d = Math.hypot(S.x[i] - x, S.z[i] - z);
    if (d < bestD) {
      if (preferOut) {  // an explicit battery yaw: only walls facing its back count
        const n = flat([S.nx[i], 0, S.nz[i]]);
        if (!n || Math.abs(dot(n, preferOut)) < 0.85) return;
      }
      bestD = d; best = i;
    }
  });
  if (best < 0) return { fail: "none" };
  // Face normals point toward where the phone was, so their plain sum says which side is outdoors.
  const n0 = flat([S.nx[best], 0, S.nz[best]]);
  let sx = 0, sz = 0, px = 0, pz = 0, cnt = 0;
  eachNear(S.walls, S.x[best], S.z[best], 0.5, (i) => {
    const n = flat([S.nx[i], 0, S.nz[i]]);
    if (!n || Math.abs(dot(n, n0)) < 0.85) return;
    if (Math.abs((S.x[i] - S.x[best]) * n0[0] + (S.z[i] - S.z[best]) * n0[2]) > 0.1) return;
    sx += n[0]; sz += n[2]; px += S.x[i]; pz += S.z[i]; cnt++;
  });
  // A wall is a sizable flat patch, not a meter box or a downspout: 20+ parallel faces within 0.5 m.
  if (cnt < 20 || Math.hypot(sx, sz) < cnt * 0.5) return { fail: "small" };  // too few faces, or no clear outdoor side
  const out = flat([sx, 0, sz]);
  const point = [px / cnt, groundY, pz / cnt];
  // A house wall rises past 2 m. AC units, bushes, and most fences do not, so they are obstacles, not walls to back onto.
  let top = 0;
  eachNear(S.walls, point[0], point[2], 0.6, (i) => {
    const n = flat([S.nx[i], 0, S.nz[i]]);
    if (n && Math.abs(dot(n, out)) > 0.85 && Math.abs((S.x[i] - point[0]) * out[0] + (S.z[i] - point[2]) * out[2]) < 0.15) {
      top = Math.max(top, S.y[i] - groundY);
    }
  });
  if (top < HOUSE_WALL_H) return { fail: "low", top };
  return { point, out, distance: (x - point[0]) * out[0] + (z - point[2]) * out[2] };
}

// ---------- analysis ----------

function pickRegion(survey, override) {
  if (override) return { ...AUSTIN, ...override };
  const fix = survey && survey.propertyLocation;
  const hasLocation = Number.isFinite(fix?.latitude) && Number.isFinite(fix?.longitude);
  if (hasLocation) {
    const b = AUSTIN.bbox;
    return fix.latitude >= b.lat[0] && fix.latitude <= b.lat[1] && fix.longitude >= b.lon[0] && fix.longitude <= b.lon[1] ? AUSTIN : null;
  }
  // Missing GPS should not erase otherwise useful geometry. Run the only bundled rule set, but keep the
  // regional assumption visible and unresolved so this can never silently become final approval.
  return { ...AUSTIN, id: "austin (default)", regionDefaulted: true };
}

function electrical(survey, rules) {
  const e = (survey && survey.electrical) || {};
  const amps = e.mainBreakerAmperage, bus = e.panelBusRatingAmps, solar = e.hasSolar, count = e.plannedBatteryCount;
  const out = {};
  const [lo, hi] = rules.main_breaker_amps;
  out.main_breaker = amps == null
    ? { status: "unknown", kind: "input", detail: "Breaker amperage not in survey.json" }
    : { status: amps >= lo && amps <= hi ? "pass" : "conflict", kind: "input", detail: `${amps} A stated, against ${lo}–${hi} A` };
  // Decided only from the panel bus rating read off the label. Never inferred from the main breaker.
  const need = rules.panel_amps_for_solar_or_two_batteries;
  const needs = solar === true || (count || 0) >= 2;
  const neither = solar === false && count != null && count < 2;
  let st, detail;
  if (neither) { st = "pass"; detail = "No solar, one battery"; }
  else if (!needs) { st = "unknown"; detail = "Solar or battery count not answered"; }
  else if (bus == null) { st = "unknown"; detail = "Panel bus rating not in survey.json"; }
  else if (bus >= need) { st = "pass"; detail = `${bus} A panel bus rating stated, covers ${solar ? "solar" : "two batteries"}`; }
  else { st = "conflict"; detail = `${solar ? "Solar" : "Two batteries"} needs a ${need} A panel; ${bus} A stated`; }
  out.solar_or_two_batteries = { status: st, kind: "input", detail };
  return withMeta(out);
}

function analyze(ply, opts = {}) {
  const survey = opts.survey || null;
  const rules = pickRegion(survey, opts.rules);
  const marks = ply.marks;
  const result = { marks, notice: "Preliminary survey only. Not an electrical inspection, code review, or installation approval." };
  if (!rules) return { ...result, verdict: "manual_review", reason: "No siting rules for this property's region." };
  result.region = rules.id;
  const mw = marks.meter_wall;
  if (!mw || !mw.normal) return { ...result, verdict: "manual_review", reason: "The meter was not tapped on the wall, so there is nothing to measure from." };

  const S = buildScene(ply);
  const noGas = !!opts.noGas || !!(survey && survey.placement && survey.placement.gasMeterNotPresent);
  const [bw, bh, bd] = rules.battery_in.map((v) => v * IN);
  const fp = rules.footprint_side_ft * FT;
  const side = (rules.side_clearance_ft ?? 3) * FT;
  const [wsW, wsD] = rules.working_space_in.map((v) => v * IN);
  const [tsA, tsH, tsO] = rules.transfer_switch_in.map((v) => v * IN);
  const meterWall = mw.p;
  const meterGround = marks.meter_ground ? marks.meter_ground.p : null;
  const panelWall = marks.panel_wall ? marks.panel_wall.p : null;
  const panelNormal = marks.panel_wall ? marks.panel_wall.normal : null;
  const gas = marks.gas_meter ? marks.gas_meter.p : null;
  const groundY = meterGround ? meterGround[1] : groundNear(S, meterWall[0], meterWall[2], null, meterWall[1]);
  if (groundY == null) return { ...result, verdict: "needs_more_scan", reason: "No ground was scanned under the meter." };
  result.groundY = groundY;

  // Meter wall frame: the tap's plane normal, flipped toward open ground; the siding sits a little behind the meter's face.
  let mOut = flat(mw.normal);
  let vote = 0;
  eachNear(S.floors, meterWall[0], meterWall[2], 2, (i) => {
    const d = (S.x[i] - meterWall[0]) * mOut[0] + (S.z[i] - meterWall[2]) * mOut[2];
    if (Math.abs(d) > 0.2 && S.y[i] < groundY + 0.15) vote += d > 0 ? 1 : -1;
  });
  if (vote < 0) mOut = [-mOut[0], 0, -mOut[2]];
  const offs = [];
  eachNear(S.walls, meterWall[0], meterWall[2], 0.8, (i) => {
    const n = flat([S.nx[i], 0, S.nz[i]]);
    const d = (S.x[i] - meterWall[0]) * mOut[0] + (S.z[i] - meterWall[2]) * mOut[2];
    if (n && Math.abs(dot(n, mOut)) > 0.85 && Math.abs(d) < 0.3) offs.push(d);
  });
  const shift = median(offs) || 0;
  const mFrame = { point: add([meterWall[0], groundY, meterWall[2]], mOut, shift), out: mOut, along: alongOf(mOut) };
  const toM = (p) => { const r = sub(p, mFrame.point); return [dot(r, mFrame.along), dot(r, mFrame.out), p[1] - groundY]; };

  // Is sample i part of the wall plane (point, out)? Such faces are the wall, never an obstacle.
  const onPlane = (i, point, out) => {
    const lb = S.label[i];
    if (!(lb === L.WALL || lb === L.DOOR || lb === L.WINDOW) || Math.abs(S.ny[i]) >= 0.45) return false;
    const n = flat([S.nx[i], 0, S.nz[i]]);
    return !!n && Math.abs(dot(n, out)) > 0.85 && Math.abs((S.x[i] - point[0]) * out[0] + (S.z[i] - point[2]) * out[2]) < 0.2;
  };
  const isObstacleLabel = (lb) => lb !== L.FLOOR && lb !== L.CEILING;

  // ----- site-level checks -----
  const site = {};
  const [, hHi] = rules.meter_height_ft;
  const mh = meterWall[1] - groundY;
  site.meter_height = meterGround
    ? { status: mh / FT <= hHi ? "pass" : "conflict", kind: "scan", detail: `${(mh / FT).toFixed(1)} ft measured (maximum ${hHi} ft)` }
    : { status: "unknown", kind: "scan", detail: "No ground tap under the meter" };
  if (panelWall) {
    const off = Math.abs(toM(panelWall)[1]);
    const parallel = !panelNormal || Math.abs(dot(flat(panelNormal) || mOut, mOut)) >= 0.96;
    site.meter_and_panel_same_wall = { status: off < 0.3 && parallel ? "pass" : "conflict", kind: "scan", detail: `Panel measured ${(off / FT).toFixed(1)} ft off the meter's wall plane` };
  } else {
    site.meter_and_panel_same_wall = { status: "unknown", kind: "scan", detail: "Panel not tapped on the wall" };
  }

  for (const key of ["exterior_install", "single_main_breaker", "panel_not_in_closet", "equipment_condition", "tight_alley_clearance"]) {
    site[key] = { status: "unknown", kind: "manual", detail: "Not established by the exported mesh or survey answers; a reviewer must confirm it." };
  }
  if (rules.regionDefaulted) {
    site.rules_region = { status: "unknown", kind: "manual", detail: "No usable property coordinates were exported, so the viewer used Austin defaults. Confirm the property is in Austin." };
  }

  // Transfer switch: both sides of the meter; the preferred side wins when both are clear.
  const [mu] = toM(meterWall);
  const panelU = panelWall ? toM(panelWall)[0] : null;
  const sides = {};
  for (const s of [1, -1]) {
    const c = mu + s * (tsA / 2 + 0.08);
    const box = { u: [c - tsA / 2, c + tsA / 2], w: [0.05, tsO], h: [Math.max(mh - tsH / 2, MIN_OBSTACLE_H), mh + tsH / 2] };
    let blocked = 0;
    const wallWidth = Math.max(1, Math.ceil((box.u[1] - box.u[0]) / CELL));
    const wallHeight = Math.max(1, Math.ceil((box.h[1] - box.h[0]) / CELL));
    const wallSeen = new Set();
    const center = add(add(mFrame.point, mFrame.along, c), mFrame.out, tsO / 2);
    eachNear(S.all, center[0], center[2], 1.2, (i) => {
      const [u, w, h] = toM([S.x[i], S.y[i], S.z[i]]);
      if (u < box.u[0] || u > box.u[1] || h < box.h[0] || h > box.h[1]) return;
      if (onPlane(i, mFrame.point, mOut)) {
        const ui = Math.min(wallWidth - 1, Math.floor((u - box.u[0]) / CELL));
        const hi = Math.min(wallHeight - 1, Math.floor((h - box.h[0]) / CELL));
        if (ui >= 0 && hi >= 0) wallSeen.add(ui * wallHeight + hi);
        return;
      }
      if (isObstacleLabel(S.label[i]) && w >= box.w[0] && w <= box.w[1]) blocked++;
    });
    const observed = coverageQuality(wallSeen, wallWidth, wallHeight);
    const name = panelU == null ? (s > 0 ? "side_a" : "side_b") : (Math.sign(panelU - mu) === s ? "panel_side" : "far_side");
    sides[name] = { box, blocked, coverage: observed.ratio, status: !observed.complete ? "unknown" : blocked === 0 ? "pass" : "conflict" };
  }
  const clearSides = Object.keys(sides).filter((k) => sides[k].status === "pass");
  const tsSide = clearSides[0] || null;
  site.transfer_switch = {
    status: tsSide ? "pass" : Object.values(sides).every((v) => v.status === "conflict") ? "conflict" : "unknown",
    kind: "scan",
    detail: Object.entries(sides).map(([k, v]) => `${k.replace("_", " ")}: ${v.status === "pass" ? "clear" : v.status === "conflict" ? "blocked" : `${Math.round(v.coverage * 100)}% scanned`}`).join(", "),
    side: tsSide,
  };
  const tsBox = tsSide ? sides[tsSide].box : null;
  if (tsBox) {
    const c = (tsBox.u[0] + tsBox.u[1]) / 2;
    result.transferBox = {
      center: add(add(add(mFrame.point, mFrame.along, c), mFrame.out, (tsBox.w[0] + tsBox.w[1]) / 2), [0, 1, 0], (tsBox.h[0] + tsBox.h[1]) / 2),
      along: mFrame.along, out: mFrame.out, size: [tsBox.u[1] - tsBox.u[0], tsBox.h[1] - tsBox.h[0], tsBox.w[1] - tsBox.w[0]],
    };
  }

  // Keep-out boxes in front of the meter and the panel.
  const equipment = [["meter", meterWall, mw.normal], ["panel", panelWall, panelNormal]];

  // ----- one battery spot -----
  function computeAt(x, z, yaw) {
    const preferOut = yaw == null ? null : [Math.sin(yaw), 0, Math.cos(yaw)];
    const gY0 = groundNear(S, x, z, groundY);
    const wall = findWall(S, x, z, gY0, preferOut);
    const off = (kind, reason) => ({ status: "offwall", kind, reason, center: [x, gY0, z] });
    if (wall.fail === "none") return off("far", "No house wall within 3 ft. The battery must be within 1 ft of one.")
    if (wall.fail === "small") return off("far", "The nearest vertical surface is small (a box, pipe, or post), not a wall.")
    if (wall.fail === "low") {
      return off("lowwall", `The nearest wall is only scanned ${(wall.top / FT).toFixed(1)} ft high. It may be a fence or a unit, or a house wall that needs scanning higher (above ${(HOUSE_WALL_H / FT).toFixed(1)} ft).`)
    }
    const out = wall.out, along = alongOf(out);
    const back = wall.distance - bd / 2;  // cabinet back to wall
    if (back < -0.03) return off("far", "Inside or behind the wall.")
    if (back > rules.max_wall_distance_ft * FT) {
      return off("far", `The cabinet would stand ${(back / FT).toFixed(1)} ft from the wall. It must be within ${rules.max_wall_distance_ft} ft.`)
    }
    const c = [x, gY0, z];
    const checks = {};
    const loc = (i) => { const r = [S.x[i] - c[0], S.y[i] - gY0, S.z[i] - c[2]]; return [dot(r, along), dot(r, out), r[1]]; };
    const inFront = (i) => (S.x[i] - wall.point[0]) * out[0] + (S.z[i] - wall.point[2]) * out[2] >= 0.05;

    checks.wall_distance = { status: "pass", kind: "scan", detail: `${Math.max(back / FT, 0).toFixed(2)} ft behind the cabinet` };
    const dMeter = hdist(c, meterWall) / FT;
    checks.meter_distance = { status: dMeter <= rules.max_meter_distance_ft ? "pass" : "conflict", kind: "scan",
      detail: `${dMeter.toFixed(1)} ft (max ${rules.max_meter_distance_ft})` };
    if (gas) {
      const dGas = hdist(c, gas) / FT;
      checks.gas_clearance = { status: dGas >= rules.min_gas_distance_ft ? "pass" : "conflict", kind: "scan", detail: `${dGas.toFixed(1)} ft (min ${rules.min_gas_distance_ft})` };
    } else {
      checks.gas_clearance = noGas ? { status: "pass", kind: "input", detail: "Homeowner said there is no gas meter" }
        : { status: "unknown", kind: "input", detail: "Gas meter not marked or answered" };
    }

    // Build the required envelope as visible 10 cm squares. Every square must be observed, outdoors, and clear.
    const makeRegion = (region, u0, u1, w0, w1, maxHeight) => {
      const width = Math.max(1, Math.ceil((u1 - u0) / CELL));
      const depth = Math.max(1, Math.ceil((w1 - w0) / CELL));
      const cellWidth = (u1 - u0) / width, cellDepth = (w1 - w0) / depth;
      const cells = [];
      for (let ui = 0; ui < width; ui++) for (let wi = 0; wi < depth; wi++) {
        const u = u0 + (ui + 0.5) * cellWidth, w = w0 + (wi + 0.5) * cellDepth;
        let outdoors = true;
        for (const su of [-1, 1]) for (const sw of [-1, 1]) {
          const corner = add(add(c, along, u + su * cellWidth / 2), out, w + sw * cellDepth / 2);
          if ((corner[0] - wall.point[0]) * out[0] + (corner[2] - wall.point[2]) * out[2] < -0.02) outdoors = false;
        }
        cells.push({ u, w, width: cellWidth, depth: cellDepth, region, maxHeight, outdoors, seen: false, blocked: false });
      }
      return { region, u0, u1, w0, w1, width, depth, cellWidth, cellDepth, cells };
    };
    const padRegion = makeRegion("footprint", -fp / 2, fp / 2, -fp / 2, fp / 2, bh);
    const leftRegion = makeRegion("left_clearance", -fp / 2 - side, -fp / 2, -fp / 2, fp / 2, 2);
    const rightRegion = makeRegion("right_clearance", fp / 2, fp / 2 + side, -fp / 2, fp / 2, 2);
    const regions = [padRegion, leftRegion, rightRegion];
    const cellAt = (region, u, w) => {
      if (u < region.u0 || u > region.u1 || w < region.w0 || w > region.w1) return null;
      const ui = Math.min(region.width - 1, Math.max(0, Math.floor((u - region.u0) / region.cellWidth)));
      const wi = Math.min(region.depth - 1, Math.max(0, Math.floor((w - region.w0) / region.cellDepth)));
      return region.cells[ui * region.depth + wi];
    };

    let windowHit = false, wallSeen = false, windowLow = Infinity;
    const R = fp / 2 + side + 0.2;
    eachNear(S.floors, x, z, R, (i) => {
      const [u, w, h] = loc(i);
      if (Math.abs(h) > 0.25) return;
      for (const region of regions) {
        const cell = cellAt(region, u, w);
        if (cell) cell.seen = true;
      }
    });
    eachNear(S.all, x, z, R, (i) => {
      const [u, w, h] = loc(i);
      if (onPlane(i, wall.point, out)) {
        if (Math.abs(u) <= bw / 2 + 0.05 && h >= -0.05) {
          if (h <= bh + 0.05) wallSeen = true;
          if (S.label[i] === L.WINDOW && h <= WINDOW_TOP_H) { windowHit = true; windowLow = Math.min(windowLow, h); }
        }
        return;
      }
      if (!isObstacleLabel(S.label[i]) || h < MIN_OBSTACLE_H || h > ROOF_H || !inFront(i)) return;
      // Samples are at most one decision-cell apart. Conservatively touch neighboring cells too, so a thin
      // triangle crossing a cell cannot disappear merely because its raster samples landed just outside it.
      for (const region of regions) for (const du of [-CELL, 0, CELL]) for (const dw of [-CELL, 0, CELL]) {
        const cell = cellAt(region, u + du, w + dw);
        if (cell && h <= cell.maxHeight) cell.blocked = true;
      }
    });
    const finish = (region) => region.cells.map((cell) => ({
      u: cell.u, w: cell.w, width: cell.width, depth: cell.depth, region: cell.region,
      status: !cell.outdoors || cell.blocked ? "conflict" : cell.seen ? "pass" : "unknown",
      reason: !cell.outdoors ? "Crosses the house wall" : cell.blocked ? "Detected geometry occupies this square" : cell.seen ? "Scanned floor is clear" : "Ground was not scanned",
    }));
    const padCells = finish(padRegion), leftCells = finish(leftRegion), rightCells = finish(rightRegion);
    const envelope = [...padCells, ...leftCells, ...rightCells];
    const summarize = (cells) => ({
      conflict: cells.filter((cell) => cell.status === "conflict").length,
      unknown: cells.filter((cell) => cell.status === "unknown").length,
      pass: cells.filter((cell) => cell.status === "pass").length,
    });
    const padSummary = summarize(padCells), sideSummary = summarize([...leftCells, ...rightCells]);
    checks.footprint = padSummary.conflict
      ? { status: "conflict", kind: "scan", detail: `${padSummary.conflict} of ${padCells.length} placement squares are blocked or cross the wall` }
      : padSummary.unknown
        ? { status: "unknown", kind: "scan", detail: `${padSummary.unknown} of ${padCells.length} placement squares are not scanned` }
        : { status: "pass", kind: "scan", detail: `All ${padSummary.pass} placement squares are scanned and clear` };
    checks.side_clearance = sideSummary.conflict
      ? { status: "conflict", kind: "scan", detail: `${sideSummary.conflict} of ${leftCells.length + rightCells.length} side-clearance squares are blocked or cross the wall` }
      : sideSummary.unknown
        ? { status: "unknown", kind: "scan", detail: `${sideSummary.unknown} of ${leftCells.length + rightCells.length} side-clearance squares are not scanned` }
        : { status: "pass", kind: "scan", detail: `All ${sideSummary.pass} side-clearance squares are scanned and clear` };
    checks.not_in_front_of_window = windowHit
      ? { status: "conflict", kind: "scan", detail: `A window is on the wall above the cabinet (from ${(windowLow / FT).toFixed(1)} ft up)` }
      : wallSeen ? { status: "pass", kind: "scan", detail: "No window on the wall above the cabinet" }
        : { status: "unknown", kind: "scan", detail: "Wall behind the cabinet not scanned" };

    // Cabinet footprint corners, for access and transfer-switch overlap.
    const corners = [];
    for (const su of [-1, 1]) for (const sw of [-1, 1]) corners.push(add(add(c, along, su * bw / 2), out, sw * bd / 2));
    const blocks = [];
    let accessUnknown = false;
    for (const [name, p, nrm] of equipment) {
      if (!p || !nrm) { accessUnknown = true; continue; }
      let eo = flat(nrm);
      if ((c[0] - p[0]) * eo[0] + (c[2] - p[2]) * eo[2] < 0) eo = [-eo[0], 0, -eo[2]];
      const ea = alongOf(eo);
      const us = corners.map((q) => (q[0] - p[0]) * ea[0] + (q[2] - p[2]) * ea[2]);
      const ws = corners.map((q) => (q[0] - p[0]) * eo[0] + (q[2] - p[2]) * eo[2]);
      if (overlap(Math.min(...us), Math.max(...us), -wsW / 2, wsW / 2) && overlap(Math.min(...ws), Math.max(...ws), 0, wsD)) blocks.push(name);
    }
    checks.meter_and_panel_access = blocks.length ? { status: "conflict", kind: "scan", detail: `Stands in front of the ${blocks.join(" and ")}` }
      : accessUnknown ? { status: "unknown", kind: "scan", detail: "Meter or panel not tapped on the wall" }
        : { status: "pass", kind: "scan", detail: "Clear of the meter and panel" };
    if (tsBox) {
      const m = corners.map(toM);
      const hit = overlap(Math.min(...m.map((q) => q[0])), Math.max(...m.map((q) => q[0])), ...tsBox.u)
        && overlap(Math.min(...m.map((q) => q[1])), Math.max(...m.map((q) => q[1])), ...tsBox.w)
        && overlap(0, bh, ...tsBox.h);
      checks.transfer_switch_space = hit ? { status: "conflict", kind: "scan", detail: "Blocks the transfer-switch space" }
        : { status: "pass", kind: "scan", detail: "Leaves the transfer-switch space free" };
    }

    withMeta(checks);
    const vals = Object.values(checks);
    const status = vals.some((v) => v.status === "conflict") ? "conflict"
      : vals.some((v) => v.status === "unknown" && v.kind === "scan") ? "unknown" : "pass";
    return {
      status, checks, envelope, center: c, out, along, yaw: Math.atan2(out[0], out[2]),
      wallPoint: wall.point, pending: Object.keys(checks).filter((k) => checks[k].status === "unknown" && checks[k].kind === "input"),
    };
  }

  // Candidate centers live on the same 10 cm lattice as the visible envelope. Cache them so grid generation
  // and later battery dragging never recompute the same geometry.
  const evaluationCache = new Map();
  function evaluateAt(x, z, yaw) {
    if (yaw != null) return computeAt(x, z, yaw);
    const i = col(x), j = col(z), cacheKey = key(i, j);
    if (!evaluationCache.has(cacheKey)) evaluationCache.set(cacheKey, computeAt((i + 0.5) * CELL, (j + 0.5) * CELL));
    return evaluationCache.get(cacheKey);
  }

  // ----- the grid: every scanned 10 cm ground cell within reach of the meter -----
  // Candidates (a battery could stand here) go in `grid`. Every other scanned floor cell goes in `floor`
  // with the reason it cannot, so the map covers the whole yard and a gap only means "not scanned".
  const reach = rules.max_meter_distance_ft * FT;
  const i0 = col(meterWall[0] - reach), i1 = col(meterWall[0] + reach);
  const j0 = col(meterWall[2] - reach), j1 = col(meterWall[2] + reach);
  const W = i1 - i0 + 1, H = j1 - j0 + 1;

  // Distance to the nearest house-wall column (wall faces scanned past house-wall height), by
  // propagating each cell's nearest seed to its neighbors. Approximate, and plenty for "about 6 ft away".
  const seedX = new Float32Array(W * H).fill(NaN), seedZ = new Float32Array(W * H).fill(NaN);
  const queue = [];
  for (const [k, list] of S.walls) {
    const i = Math.floor(k / 100000) - 50000, j = (k % 100000) - 50000;
    if (i < i0 || i > i1 || j < j0 || j > j1) continue;
    if (!list.some((s) => S.y[s] - groundY >= HOUSE_WALL_H)) continue;
    const c = (j - j0) * W + (i - i0);
    seedX[c] = (i + 0.5) * CELL; seedZ[c] = (j + 0.5) * CELL; queue.push(c);
  }
  for (let q = 0; q < queue.length; q++) {
    const c = queue[q], ci = c % W, cj = (c / W) | 0;
    for (let di = -1; di <= 1; di++) for (let dj = -1; dj <= 1; dj++) {
      const ni = ci + di, nj = cj + dj;
      if ((!di && !dj) || ni < 0 || nj < 0 || ni >= W || nj >= H) continue;
      const n = nj * W + ni, x = (ni + i0 + 0.5) * CELL, z = (nj + j0 + 0.5) * CELL;
      const d = Math.hypot(x - seedX[c], z - seedZ[c]);
      if (Number.isNaN(seedX[n]) || d < Math.hypot(x - seedX[n], z - seedZ[n]) - 1e-6) {
        seedX[n] = seedX[c]; seedZ[n] = seedZ[c]; queue.push(n);
      }
    }
  }
  const houseWallDistance = (i, j, x, z) => {
    const c = (j - j0) * W + (i - i0);
    return Number.isNaN(seedX[c]) ? Infinity : Math.hypot(x - seedX[c], z - seedZ[c]);
  };
  const candidateBand = bd / 2 + rules.max_wall_distance_ft * FT + 0.9;  // beyond this no wall search can succeed

  const grid = [], floor = [];
  for (let i = i0; i <= i1; i++) {
    for (let j = j0; j <= j1; j++) {
      const x = (i + 0.5) * CELL, z = (j + 0.5) * CELL;
      if (Math.hypot(x - meterWall[0], z - meterWall[2]) > reach) continue;
      const scannedGround = S.floors.has(key(i, j));
      let nearWall = false;
      eachNear(S.walls, x, z, 0.8, () => { nearWall = true; });
      if (!scannedGround && !nearWall) continue;  // never scanned: leave the gap
      const dHouse = houseWallDistance(i, j, x, z);
      const farReason = dHouse === Infinity ? "No house wall was scanned within reach of the meter."
        : `About ${Math.max(1, Math.round(dHouse / FT))} ft from the nearest house wall. The battery must be within ${rules.max_wall_distance_ft} ft of one.`;
      if (!nearWall && dHouse > candidateBand) {
        floor.push({ x, z, y: groundNear(S, x, z, groundY), status: "offwall", kind: "far", reason: farReason });
        continue;
      }
      const spot = evaluateAt(x, z);
      if (spot.status === "offwall") {
        const reason = spot.reason.startsWith("No house wall within") ? farReason : spot.reason;
        if (scannedGround || spot.kind === "lowwall") floor.push({ x, z, y: spot.center[1], status: "offwall", kind: spot.kind, reason });
      } else {
        grid.push({ x, z, y: spot.center[1], status: spot.status, spot });
      }
    }
  }

  // Best green cell: most green neighbors (room to slide), then closest to the meter.
  const green = new Set(grid.filter((g) => g.status === "pass").map((g) => key(col(g.x), col(g.z))));
  let best = null, bestScore = -Infinity;
  for (const g of grid) {
    if (g.status !== "pass") continue;
    let room = 0;
    for (let di = -2; di <= 2; di++) for (let dj = -2; dj <= 2; dj++) if (green.has(key(col(g.x) + di, col(g.z) + dj))) room++;
    const score = Math.min(room, 15) * 100 - hdist([g.x, 0, g.z], meterWall);
    if (score > bestScore) { bestScore = score; best = g; }
  }

  withMeta(site);
  const elec = survey ? electrical(survey, rules) : null;
  const checks = { ...site, ...(elec || {}) };
  const nameOf = (k) => CHECK_META[k]?.title || k;
  const conflicts = Object.entries(checks).filter(([, v]) => v.status === "conflict").map(([k, v]) => `${nameOf(k)}: ${v.detail}`);
  const missing = Object.entries(checks).filter(([, v]) => v.status === "unknown").map(([k, v]) => `${nameOf(k)}: ${v.detail}`);
  if (!survey) missing.push("electrical: load survey.json for the breaker and solar checks");
  if (best) for (const p of best.spot.pending) missing.push(`${nameOf(p)}: ${best.spot.checks[p].detail}`);
  let verdict;
  if (conflicts.length) verdict = "not_installable";
  else if (best) verdict = missing.length ? "installable_pending" : "installable";
  else if (grid.some((g) => g.status === "unknown") || floor.some((f) => f.kind === "lowwall")) verdict = "needs_more_scan";
  else { verdict = "not_installable"; conflicts.push("No spot within reach of the meter passes the siting checks"); }

  const placed = marks.battery || marks.battery_suggested;
  const yourSpot = placed ? { confirmed: !!marks.battery, ...evaluateAt(placed.p[0], placed.p[2], placed.yaw) } : null;

  const counts = { pass: 0, conflict: 0, unknown: 0, far: 0, lowwall: 0 };
  for (const g of grid) counts[g.status]++;
  for (const f of floor) counts[f.kind]++;
  // Say what to scan next when nothing passed.
  const scanHints = [];
  if (verdict === "needs_more_scan") {
    if (counts.lowwall) scanHints.push("Some walls near the meter were only scanned low. Sweep the phone up each wall past the roofline.");
    if (counts.unknown) scanHints.push("Parts of the ground beside the wall were not scanned. Walk the phone along the wall at knee height.");
  }
  return { ...result, verdict, reason: scanHints.join(" ") || undefined, conflicts, missing, site, electrical: elec, grid, floor, counts, best, yourSpot, rules,
    reach: { center: [meterWall[0], groundY, meterWall[2]], radius: reach }, meterFrame: mFrame, evaluateAt, labelNames: LABEL_NAMES };
}

export { parsePLY, readMarks, analyze, AUSTIN, L as LABELS, LABEL_NAMES, FT, IN, CELL };
