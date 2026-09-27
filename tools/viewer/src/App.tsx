import { useCallback, useEffect, useRef, useState } from "react"
import { ChevronDown, CircleAlert, CircleCheck, CircleHelp, CircleX, Upload } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Switch } from "@/components/ui/switch"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { analyze, parsePLY, type Analysis, type Check, type FloorCell, type GridCell, type PLY, type Rules, type Spot, type Status } from "@/lib/checker.js"
import { LABEL_RGB, SiteScene, type ColorMode, type ViewMode } from "@/lib/scene"
import { cn } from "@/lib/utils"
import { readSurveyPacket } from "@/lib/zip"

const NAMES: Record<string, string> = {
  wall_distance: "Within 1 ft of the wall",
  meter_distance: "Within 20 ft of the meter",
  gas_clearance: "3 ft from the gas meter",
  footprint: "3 × 3 ft pad clear",
  side_clearance: "3 ft clear on both sides",
  not_in_front_of_window: "Not in front of a window",
  meter_and_panel_access: "Clear of meter and panel access",
  transfer_switch_space: "Leaves transfer-switch space",
  meter_height: "Meter no higher than 6 ft",
  meter_and_panel_same_wall: "Meter and panel on one wall",
  transfer_switch: "Transfer-switch space",
  main_breaker: "Main breaker 150–200 A",
  solar_or_two_batteries: "Solar or 2 batteries → 200 A",
}

const VERDICTS: Record<Analysis["verdict"], { tone: Status; title: string; text: string }> = {
  installable: { tone: "pass", title: "Candidate found", text: "At least one battery center passed every measured scan check." },
  installable_pending: { tone: "pass", title: "Candidate found—information missing", text: "A scan-supported candidate exists, but some survey answers or manual checks remain." },
  not_installable: { tone: "conflict", title: "Observed conflict", text: "" },
  needs_more_scan: { tone: "unknown", title: "More scan needed", text: "No candidate passed, and parts of the required placement area were not measured." },
  manual_review: { tone: "unknown", title: "Manual review required", text: "" },
}

const TONE = {
  pass: { text: "text-emerald-600 dark:text-emerald-400", badge: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400", label: "Pass" },
  conflict: { text: "text-destructive", badge: "bg-destructive/10 text-destructive dark:bg-destructive/20", label: "Blocked" },
  unknown: { text: "text-amber-600 dark:text-amber-400", badge: "bg-amber-500/15 text-amber-700 dark:text-amber-400", label: "Unknown" },
} as const

const SWATCH = { pass: "bg-emerald-500", conflict: "bg-red-500", unknown: "bg-amber-500" } as const

const SOURCE_URLS: Record<string, string> = {
  "Base electrical and spacing requirements": "https://help.basepowercompany.com/en/articles/10280705",
  "Base home photo-review guidance": "https://help.basepowercompany.com/en/articles/10280641",
  "Base Core specifications": "https://www.basepowercompany.com/specs/core",
}

function StatusBadge({ check }: { check: Check }) {
  const label = check.status === "unknown" && check.evidence === "manual" ? "Manual review" : TONE[check.status].label
  return <Badge className={cn("h-5 shrink-0 border-transparent px-1.5 text-[10px]", TONE[check.status].badge)}>{label}</Badge>
}

function checkCounts(checks: Record<string, Check>) {
  return Object.values(checks).reduce((counts, check) => {
    counts[check.status]++
    return counts
  }, { pass: 0, conflict: 0, unknown: 0 })
}

function ChecksList({ checks }: { checks: Record<string, Check> }) {
  return (
    <div className="divide-y rounded-lg border">
      {Object.entries(checks).map(([k, v]) => (
        <details key={k} className="group/check px-3 py-2">
          <summary className="flex cursor-pointer list-none items-center gap-2 text-sm [&::-webkit-details-marker]:hidden">
            <span className={cn("size-1.5 shrink-0 rounded-full", SWATCH[v.status])} />
            <span className="min-w-0 flex-1 truncate font-medium">{v.title ?? NAMES[k] ?? k}</span>
            <StatusBadge check={v} />
            <ChevronDown className="text-muted-foreground size-3.5 shrink-0 transition-transform group-open/check:rotate-180" />
          </summary>
          <div className="text-muted-foreground space-y-1 pt-2 pl-3.5 text-xs">
            <p className="text-foreground">{v.detail}</p>
            {v.requirement && <p>{v.requirement}</p>}
            {v.assumption && <p className="text-amber-700 dark:text-amber-400">Prototype assumption: {v.assumption}</p>}
            {v.source && SOURCE_URLS[v.source] && <a className="inline-block underline underline-offset-2" href={SOURCE_URLS[v.source]} target="_blank" rel="noreferrer">Source: {v.source}</a>}
          </div>
        </details>
      ))}
    </div>
  )
}

function CheckSection({ title, checks, children, open = false }: { title: string; checks?: Record<string, Check> | null; children?: React.ReactNode; open?: boolean }) {
  const counts = checks ? checkCounts(checks) : null
  return (
    <details open={open} className="group/section border-b pb-3 last:border-0">
      <summary className="flex cursor-pointer list-none items-center gap-2 py-1 text-sm font-semibold [&::-webkit-details-marker]:hidden">
        <span className="flex-1">{title}</span>
        {counts && <span className="text-muted-foreground flex gap-2 text-[11px] font-normal">
          {!!counts.pass && <span>{counts.pass} passed</span>}
          {!!counts.conflict && <span className={TONE.conflict.text}>{counts.conflict} blocked</span>}
          {!!counts.unknown && <span className={TONE.unknown.text}>{counts.unknown} open</span>}
        </span>}
        <ChevronDown className="text-muted-foreground size-4 transition-transform group-open/section:rotate-180" />
      </summary>
      <div className="pt-2">{children ?? (checks && <ChecksList checks={checks} />)}</div>
    </details>
  )
}

interface Loaded { ply?: string; plyName?: string; survey?: unknown; surveyName?: string; rules?: Partial<Rules>; rulesName?: string; packetName?: string }

export default function App() {
  const host = useRef<HTMLDivElement>(null)
  const sceneRef = useRef<SiteScene | null>(null)
  const picker = useRef<HTMLInputElement>(null)
  const [loaded, setLoaded] = useState<Loaded>({})
  const [status, setStatus] = useState<string | null>("Drop a Base Site Survey ZIP or scene.ply.")
  const [analysis, setAnalysis] = useState<Analysis | null>(null)
  const [ply, setPly] = useState<PLY | null>(null)
  const [selected, setSelected] = useState<{ spot: Spot; label: string } | null>(null)
  const [hover, setHover] = useState<{ cell: GridCell | FloorCell; x: number; y: number } | null>(null)
  const [dragOver, setDragOver] = useState(false)
  const [colorMode, setColorMode] = useState<ColorMode>("camera")
  const [view, setView] = useState<ViewMode>("orbit")
  const [showGrid, setShowGrid] = useState(true)
  const [showFloor, setShowFloor] = useState(true)
  const [showCeiling, setShowCeiling] = useState(false)
  const [cutAbove, setCutAbove] = useState(true)

  useEffect(() => {
    const scene = new SiteScene(host.current!, {
      onHover: (cell, x, y) => setHover(cell ? { cell, x, y } : null),
      onSelect: (spot, label) => setSelected({ spot, label }),
    })
    sceneRef.current = scene
    return () => scene.dispose()
  }, [])

  // ?ply=…&survey=…&rules=… loads files served next to the page.
  useEffect(() => {
    const q = new URLSearchParams(location.search)
    if (!q.get("ply")) return
    ;(async () => {
      const next: Loaded = {}
      for (const k of ["ply", "survey", "rules"] as const) {
        const url = q.get(k)
        if (!url) continue
        const text = await (await fetch(url)).text()
        const name = url.split("/").pop()
        if (k === "ply") Object.assign(next, { ply: text, plyName: name })
        else if (k === "survey") Object.assign(next, { survey: JSON.parse(text), surveyName: name })
        else Object.assign(next, { rules: JSON.parse(text), rulesName: name })
      }
      setLoaded(next)
    })()
  }, [])

  const readFiles = useCallback(async (files: File[]) => {
    const next: Loaded = { ...loaded }
    try {
      for (const f of files) {
        const lower = f.name.toLowerCase()
        if (lower.endsWith(".zip")) {
          const packet = await readSurveyPacket(f)
          Object.assign(next, packet, { packetName: f.name })
          continue
        }
        const text = await f.text()
        if (lower.endsWith(".ply")) { next.ply = text; next.plyName = f.name; continue }
        let json: Record<string, unknown>
        try { json = JSON.parse(text) as Record<string, unknown> }
        catch { throw new Error(`${f.name} is not valid JSON.`) }
        if (json.electrical || json.placement) { next.survey = json; next.surveyName = f.name }
        else { next.rules = json; next.rulesName = f.name }
      }
      setLoaded(next)
    } catch (error) {
      setStatus((error as Error).message)
    }
  }, [loaded])

  // Re-run the analysis whenever the inputs change.
  useEffect(() => {
    if (!loaded.ply) { if (loaded.survey || loaded.rules) setStatus("Add a scene.ply as well."); return }
    setStatus("Analyzing…")
    const t = setTimeout(() => {
      try {
        const p = parsePLY(loaded.ply!)
        const a = analyze(p, { survey: loaded.survey, rules: loaded.rules })
        setPly(p)
        setAnalysis(a)
        setStatus(null)
      } catch (err) {
        setStatus((err as Error).message)
      }
    }, 30)
    return () => clearTimeout(t)
  }, [loaded])

  useEffect(() => {
    const scene = sceneRef.current
    if (!scene || !ply || !analysis) return
    scene.load(ply, analysis, { colorMode, showGrid, showFloor, showCeiling, cutAbove })
    const fallback = analysis.grid?.find((cell) => cell.status === "unknown") ?? analysis.grid?.[0]
    const first = analysis.best ? { spot: analysis.best.spot, label: "best spot" }
      : analysis.yourSpot?.center ? { spot: analysis.yourSpot, label: "placed in the app" }
        : fallback ? { spot: fallback.spot, label: "candidate spot" } : null
    scene.showSpot(first?.spot ?? null)
    setSelected(first)
    // Display toggles are applied by their own effects; reload only on new data.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ply, analysis])

  useEffect(() => sceneRef.current?.setColorMode(colorMode), [colorMode])
  useEffect(() => sceneRef.current?.setView(view), [view])
  useEffect(() => sceneRef.current?.setGrid(showGrid, showFloor), [showGrid, showFloor])
  useEffect(() => sceneRef.current?.setCeiling(showCeiling), [showCeiling])
  useEffect(() => sceneRef.current?.setCutAbove(cutAbove), [cutAbove])

  const choose = (spot: Spot, label: string) => { sceneRef.current?.showSpot(spot); setSelected({ spot, label }) }
  const onDrop = (e: React.DragEvent) => { e.preventDefault(); setDragOver(false); readFiles([...e.dataTransfer.files]) }
  const dropProps = { onDragOver: (e: React.DragEvent) => { e.preventDefault(); setDragOver(true) }, onDragLeave: () => setDragOver(false), onDrop }

  const verdict = analysis ? VERDICTS[analysis.verdict] : null
  const VerdictIcon = verdict ? { pass: CircleCheck, conflict: CircleX, unknown: CircleHelp }[verdict.tone] : CircleAlert
  const envelopeCounts = selected?.spot.envelope?.reduce((counts, cell) => {
    counts[cell.status]++
    return counts
  }, { pass: 0, conflict: 0, unknown: 0 })
  const envelopeTotal = envelopeCounts ? envelopeCounts.pass + envelopeCounts.conflict + envelopeCounts.unknown : 0

  return (
    <div className="flex h-dvh flex-col-reverse bg-background text-foreground md:flex-row">
      <aside className="h-[55%] shrink-0 border-t md:h-full md:w-[360px] md:border-t-0 md:border-r">
        <ScrollArea className="h-full">
          <div className="flex flex-col gap-3 p-4">
            <div>
              <h1 className="font-heading text-lg font-semibold tracking-tight">Site Scan Viewer</h1>
              <p className="text-muted-foreground text-xs">Local, preliminary placement review</p>
            </div>

            <button
              type="button"
              onClick={() => picker.current?.click()}
              {...dropProps}
              className={cn("flex items-center justify-center gap-2 rounded-lg border border-dashed text-sm transition-colors hover:bg-muted/50",
                analysis ? "px-3 py-2" : "flex-col px-4 py-5 text-center",
                dragOver && "border-primary bg-muted/50")}
            >
              <Upload className={cn("text-muted-foreground", analysis ? "size-4" : "size-5")} />
              {analysis
                ? <span className="font-medium">Open another packet</span>
                : <><span className="font-medium">Drop survey ZIP or scan files</span><span className="text-muted-foreground text-xs">Files stay on this computer</span></>}
            </button>
            <input ref={picker} type="file" multiple accept=".zip,.ply,.json,application/zip" hidden onChange={(e) => readFiles([...(e.target.files ?? [])])} />

            {analysis && verdict && (
              <>
                <section className="rounded-xl border bg-card p-3 shadow-sm">
                  <div className="flex items-start gap-2.5">
                    <VerdictIcon className={cn("mt-0.5 size-5 shrink-0", TONE[verdict.tone].text)} />
                    <div className="min-w-0 flex-1">
                      <h2 className={cn("font-semibold", TONE[verdict.tone].text)}>{verdict.title}</h2>
                      <p className="text-muted-foreground mt-0.5 text-xs">{analysis.reason ?? verdict.text}</p>
                    </div>
                  </div>
                  <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 border-t pt-2 text-[11px]">
                    {analysis.region && <span className="text-muted-foreground">{analysis.region} rules</span>}
                    {analysis.counts && (["pass", "conflict", "unknown"] as const).map((s) => (
                      <span key={s} className="flex items-center gap-1"><span className={cn("size-1.5 rounded-full", SWATCH[s])} />{analysis.counts![s]}</span>
                    ))}
                  </div>
                </section>

                {analysis.grid && (
                  <section className="space-y-3 border-b pb-3">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <h2 className="text-sm font-semibold">Selected spot</h2>
                        {selected && selected.spot.status !== "offwall"
                          ? <p className={cn("mt-0.5 text-xs", TONE[selected.spot.status].text)}>
                              {{ pass: "Scan-eligible", conflict: "Blocked", unknown: "Needs more scan" }[selected.spot.status]} · {selected.label}
                            </p>
                          : <p className="text-muted-foreground mt-0.5 text-xs">{selected ? selected.spot.reason : "Select a marker on the scan"}</p>}
                      </div>
                      {envelopeCounts && <div className="shrink-0 text-right text-xs">
                        {envelopeCounts.pass === envelopeTotal
                          ? <span className={TONE.pass.text}>All {envelopeTotal} cells clear</span>
                          : <><span className={TONE.conflict.text}>{envelopeCounts.conflict} blocked</span><br /><span className={TONE.unknown.text}>{envelopeCounts.unknown} unscanned</span></>}
                      </div>}
                    </div>
                    <div className="flex gap-2">
                      <Button size="sm" variant="outline" disabled={!analysis.best} onClick={() => analysis.best && choose(analysis.best.spot, "best spot")}>Best</Button>
                      <Button size="sm" variant="outline" disabled={!analysis.yourSpot?.center}
                        onClick={() => analysis.yourSpot && choose(analysis.yourSpot, analysis.yourSpot.confirmed ? "placed in the app" : "suggested in the app")}>
                        App placement
                      </Button>
                    </div>
                    {selected && selected.spot.status !== "offwall" && <CheckSection title="Placement checks" checks={selected.spot.checks} />}
                  </section>
                )}

                {analysis.site && <CheckSection title="Site review" checks={analysis.site} />}
                {analysis.electrical
                  ? <CheckSection title="Electrical" checks={analysis.electrical} />
                  : <CheckSection title="Electrical"><p className="text-muted-foreground text-xs">Add survey.json for breaker and solar checks.</p></CheckSection>}

                <CheckSection title="View">
                  <div className="flex flex-col gap-3">
                    <div className="flex flex-wrap gap-2">
                      <Tabs value={colorMode} onValueChange={(v) => setColorMode(v as ColorMode)}>
                        <TabsList><TabsTrigger value="camera">Camera color</TabsTrigger><TabsTrigger value="labels">ARKit labels</TabsTrigger></TabsList>
                      </Tabs>
                      <Tabs value={view} onValueChange={(v) => setView(v as ViewMode)}>
                        <TabsList><TabsTrigger value="orbit">3D</TabsTrigger><TabsTrigger value="top">Top</TabsTrigger></TabsList>
                      </Tabs>
                    </div>
                    {([["grid", "Placement grid", showGrid, setShowGrid], ["floor", "Whole scanned floor, with reasons", showFloor, setShowFloor],
                      ["cut", "Cut away above 2.2 m", cutAbove, setCutAbove], ["ceiling", "Ceiling and roof", showCeiling, setShowCeiling]] as const).map(([id, text, value, set]) => (
                      <div key={id} className="flex items-center justify-between">
                        <Label htmlFor={id} className="font-normal">{text}</Label>
                        <Switch id={id} checked={value} onCheckedChange={set} />
                      </div>
                    ))}
                  </div>
                </CheckSection>

                <CheckSection title="Legend">
                  <div className="grid grid-cols-2 gap-x-3 gap-y-1.5 text-xs text-muted-foreground">
                    <div className="col-span-2 mb-1">Markers are possible battery centers. A selected spot passes only when its full envelope is green.</div>
                    {[
                      [SWATCH.pass, "Clear"], [SWATCH.conflict, "Blocked"],
                      [SWATCH.unknown, "Unscanned"], ["bg-slate-400/60", "No valid center"],
                      ["bg-amber-300/70", "Wall not confirmed"], ["bg-purple-500", "Meter / reach"],
                      ["bg-teal-500", "Panel"], ["bg-pink-500", "Gas meter"],
                    ].map(([c, t]) => <div key={t} className="flex items-center gap-2"><span className={cn("size-2.5 shrink-0 rounded-sm", c)} />{t}</div>)}
                    {colorMode === "labels" && ([[1, "Wall"], [2, "Floor"], [6, "Window"], [7, "Door"], [4, "Table"], [5, "Seat"], [0, "Other"]] as const).map(([i, t]) => (
                      <div key={t} className="flex items-center gap-2"><span className="size-2.5 shrink-0 rounded-sm" style={{ background: `rgb(${LABEL_RGB[i].join(",")})` }} />{t}</div>
                    ))}
                  </div>
                </CheckSection>
              </>
            )}

            <p className="text-muted-foreground border-t pt-3 text-[11px]">
              Preliminary only. Green is scan-supported, not installation approval.
            </p>
          </div>
        </ScrollArea>
      </aside>

      <main className="relative min-h-0 flex-1 bg-muted/40" {...dropProps}>
        <div ref={host} className="absolute inset-0" />
        {status && <div className="text-muted-foreground pointer-events-none absolute inset-0 grid place-items-center p-6 text-center">{status}</div>}
        {hover && (
          <div className="bg-popover text-popover-foreground pointer-events-none absolute z-10 max-w-72 rounded-lg border px-3 py-2 text-xs shadow-md"
            style={{ left: Math.min(hover.x + 14, (host.current?.clientWidth ?? 600) - 300), top: hover.y + 14 }}>
            {hover.cell.status === "offwall" ? (
              <>
                <div className={cn("mb-1 font-medium", hover.cell.kind === "lowwall" ? TONE.unknown.text : "text-muted-foreground")}>
                  {hover.cell.kind === "lowwall" ? "Wall not confirmed" : "No battery here"}
                </div>
                <div className="text-muted-foreground">{hover.cell.reason}</div>
              </>
            ) : (
              <>
                <div className={cn("mb-1 font-medium", TONE[hover.cell.status].text)}>{{ pass: "Fits", conflict: "Blocked", unknown: "Not scanned enough" }[hover.cell.status]}</div>
                {Object.entries(hover.cell.spot.checks).filter(([, v]) => v.status !== "pass").map(([k, v]) => (
                  <div key={k}><span className={TONE[v.status].text}>{NAMES[k] ?? k}:</span> <span className="text-muted-foreground">{v.detail}</span></div>
                ))}
                {hover.cell.status === "pass" && <div className="text-muted-foreground">Every measured check passes. Click to inspect.</div>}
              </>
            )}
          </div>
        )}
        {analysis?.grid && (
          <Badge variant="outline" className="bg-background/80 text-muted-foreground absolute bottom-3 left-3 hidden backdrop-blur md:inline-flex">
            Drag to orbit · scroll to zoom · hover a cell · drag the battery to move it
          </Badge>
        )}
      </main>
    </div>
  )
}
