// Types for checker.js. Keep in step with what analyze() returns.

export type Vec3 = [number, number, number]
export type Status = "pass" | "conflict" | "unknown"

export interface Check {
  status: Status
  detail: string
  /** Internal decision path. */
  kind?: "scan" | "input" | "manual"
  evidence?: "scan" | "survey" | "manual"
  title?: string
  requirement?: string
  source?: string
  assumption?: string
  side?: string | null
}

export interface Spot {
  status: Status | "offwall"
  /** Only when offwall. "far": not within 1 ft of a house wall. "lowwall": next to a surface scanned too low to confirm it is one. */
  kind?: "far" | "lowwall"
  reason?: string
  checks: Record<string, Check>
  center: Vec3
  out: Vec3
  along: Vec3
  yaw: number
  wallPoint: Vec3
  pending: string[]
  envelope?: EnvelopeCell[]
  confirmed?: boolean
}

export interface EnvelopeCell {
  u: number
  w: number
  width: number
  depth: number
  region: "footprint" | "left_clearance" | "right_clearance"
  status: Status
  reason: string
}

export interface GridCell {
  x: number
  y: number
  z: number
  status: Status
  spot: Spot
}

/** A scanned floor cell where no battery can stand, and why. */
export interface FloorCell {
  x: number
  y: number
  z: number
  status: "offwall"
  kind: "far" | "lowwall"
  reason: string
}

export interface Mark {
  p: Vec3
  normal?: Vec3
  yaw?: number
}

export interface Rules {
  id: string
  regionDefaulted?: boolean
  main_breaker_amps: [number, number]
  panel_amps_for_solar_or_two_batteries: number
  max_meter_distance_ft: number
  max_wall_distance_ft: number
  min_gas_distance_ft: number
  footprint_side_ft: number
  side_clearance_ft: number
  meter_height_ft: [number, number]
  working_space_in: [number, number]
  transfer_switch_in: [number, number, number]
  battery_in: [number, number, number]
}

export type Verdict = "installable" | "installable_pending" | "not_installable" | "needs_more_scan" | "manual_review"

export interface Analysis {
  verdict: Verdict
  reason?: string
  notice: string
  region?: string
  marks: Record<string, Mark | string>
  groundY?: number
  conflicts?: string[]
  missing?: string[]
  site?: Record<string, Check>
  electrical?: Record<string, Check> | null
  grid?: GridCell[]
  floor?: FloorCell[]
  counts?: Record<Status | "far" | "lowwall", number>
  reach?: { center: Vec3; radius: number }
  best?: GridCell | null
  yourSpot?: Spot | null
  rules?: Rules
  meterFrame?: { point: Vec3; out: Vec3; along: Vec3 }
  transferBox?: { center: Vec3; along: Vec3; out: Vec3; size: Vec3 }
  evaluateAt?: (x: number, z: number, yaw?: number) => Spot
}

export interface PLY {
  positions: Float32Array
  colors: Uint8Array
  faces: Uint32Array
  labels: Uint8Array
  comments: string[]
  marks: Record<string, Mark | string>
}

export function parsePLY(text: string): PLY
export function readMarks(comments: string[]): Record<string, Mark | string>
export function analyze(ply: PLY, opts?: { survey?: unknown; rules?: Partial<Rules> | null; noGas?: boolean }): Analysis
export const AUSTIN: Rules
export const LABELS: Record<"NONE" | "WALL" | "FLOOR" | "CEILING" | "TABLE" | "SEAT" | "WINDOW" | "DOOR" | "OVERLAY", number>
export const LABEL_NAMES: string[]
export const FT: number
export const IN: number
export const CELL: number
