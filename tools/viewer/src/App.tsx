import { useCallback, useEffect, useRef, useState } from "react"
import { CircleAlert, CircleCheck, CircleHelp, CircleX, Upload } from "lucide-react"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Switch } from "@/components/ui/switch"
import { Table, TableBody, TableCell, TableRow } from "@/components/ui/table"
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
  return <Badge className={cn("shrink-0 border-transparent", TONE[check.status].badge)}>{label}</Badge>
}

function ChecksTable({ checks }: { checks: Record<string, Check> }) {
  return (
    <Table>
      <TableBody>
        {Object.entries(checks).map(([k, v]) => (
          <TableRow key={k} className="hover:bg-transparent">
            <TableCell className="py-2 whitespace-normal">
              <div className="flex flex-wrap items-center gap-1.5">
                <span className="font-medium">{v.title ?? NAMES[k] ?? k}</span>
                {v.evidence && <Badge variant="outline" className="px-1.5 py-0 text-[10px] font-normal capitalize">{v.evidence}</Badge>}
              </div>
              {v.requirement && <div className="text-muted-foreground text-xs">Requirement: {v.requirement}</div>}
              <div className="text-xs">Evidence: {v.detail}</div>
              {v.assumption && <div className="text-amber-700 dark:text-amber-400 text-xs">Prototype assumption: {v.assumption}</div>}
              {v.source && SOURCE_URLS[v.source] && <a className="text-muted-foreground text-xs underline underline-offset-2" href={SOURCE_URLS[v.source]} target="_blank" rel="noreferrer">{v.source}</a>}
            </TableCell>
            <TableCell className="w-0 py-2 text-right align-top">
              <StatusBadge check={v} />
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
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

  return (
    <div className="flex h-dvh flex-col-reverse bg-background text-foreground md:flex-row">
      <aside className="h-[55%] shrink-0 border-t md:h-full md:w-[400px] md:border-t-0 md:border-r">
        <ScrollArea className="h-full">
          <div className="flex flex-col gap-4 p-4">
            <div>
              <h1 className="font-heading text-lg font-semibold tracking-tight">Site Scan Viewer</h1>
              <p className="text-muted-foreground text-sm">Scan-supported battery candidates from a Base Site Survey export. Files stay on this computer.</p>
            </div>

            <button
              type="button"
              onClick={() => picker.current?.click()}
              {...dropProps}
              className={cn("flex flex-col items-center gap-1 rounded-xl border border-dashed px-4 py-5 text-center text-sm transition-colors hover:bg-muted/50",
                dragOver && "border-primary bg-muted/50")}
            >
              <Upload className="text-muted-foreground size-5" />
              <span><span className="font-medium">Drop a Base Site Survey ZIP</span> <span className="text-muted-foreground">or scene.ply with optional survey.json</span></span>
              <span className="text-muted-foreground text-xs">or click to choose files</span>
            </button>
            <input ref={picker} type="file" multiple accept=".zip,.ply,.json,application/zip" hidden onChange={(e) => readFiles([...(e.target.files ?? [])])} />
            {(loaded.packetName || loaded.plyName || loaded.surveyName || loaded.rulesName) && (
              <div className="flex flex-wrap gap-1.5">
                {[loaded.packetName, loaded.plyName, loaded.surveyName, loaded.rulesName].filter(Boolean).map((n) => <Badge key={n} variant="secondary">{n}</Badge>)}
              </div>
            )}

            {analysis && verdict && (
              <>
                <Alert>
                  <VerdictIcon className={TONE[verdict.tone].text} />
                  <AlertTitle className={cn("text-base", TONE[verdict.tone].text)}>{verdict.title}</AlertTitle>
                  <AlertDescription>
                    <p>{analysis.reason ?? verdict.text}</p>
                    {analysis.region && (
                      <div className="mt-2 flex flex-wrap gap-1.5">
                        <Badge variant="outline">Rules: {analysis.region}</Badge>
                        {analysis.counts && (["pass", "conflict", "unknown"] as const).map((s) => (
                          <Badge key={s} variant="outline" className="gap-1.5"><span className={cn("size-2 rounded-full", SWATCH[s])} />{analysis.counts![s]}</Badge>
                        ))}
                      </div>
                    )}
                    {!!analysis.conflicts?.length && <ul className="mt-2 list-disc pl-4">{analysis.conflicts.map((c) => <li key={c}>{c}</li>)}</ul>}
                    {!!analysis.missing?.length && (
                      <>
                        <p className="mt-2 font-medium text-foreground">Still missing</p>
                        <ul className="list-disc pl-4">{analysis.missing.map((c) => <li key={c}>{c}</li>)}</ul>
                      </>
                    )}
                  </AlertDescription>
                </Alert>

                {analysis.grid && (
                  <Card size="sm">
                    <CardHeader>
                      <CardTitle>Selected spot</CardTitle>
                      <CardDescription>
                        {selected && selected.spot.status !== "offwall"
                          ? <span className={TONE[selected.spot.status].text}>
                              {{ pass: "Scan-eligible", conflict: "Blocked", unknown: "Not scanned enough" }[selected.spot.status]} · {selected.label}
                              {envelopeCounts && ` · ${envelopeCounts.pass} green, ${envelopeCounts.conflict} red, ${envelopeCounts.unknown} amber squares`}
                            </span>
                          : selected ? `Not a battery spot: ${selected.spot.reason}.` : "Click a cell, or drag the battery."}
                    </CardDescription>
                    </CardHeader>
                    <CardContent className="flex flex-col gap-3">
                      <div className="flex gap-2">
                        <Button size="sm" variant="outline" disabled={!analysis.best} onClick={() => analysis.best && choose(analysis.best.spot, "best spot")}>Best spot</Button>
                        <Button size="sm" variant="outline" disabled={!analysis.yourSpot?.center}
                          onClick={() => analysis.yourSpot && choose(analysis.yourSpot, analysis.yourSpot.confirmed ? "placed in the app" : "suggested in the app")}>
                          Spot from the app
                        </Button>
                      </div>
                      {selected && selected.spot.status !== "offwall" && <ChecksTable checks={selected.spot.checks} />}
                    </CardContent>
                  </Card>
                )}

                {analysis.site && (
                  <Card size="sm">
                    <CardHeader><CardTitle>Site</CardTitle></CardHeader>
                    <CardContent><ChecksTable checks={analysis.site} /></CardContent>
                  </Card>
                )}

                <Card size="sm">
                  <CardHeader>
                    <CardTitle>Electrical</CardTitle>
                    {!analysis.electrical && <CardDescription>Add survey.json for the breaker and solar checks.</CardDescription>}
                  </CardHeader>
                  {analysis.electrical && <CardContent><ChecksTable checks={analysis.electrical} /></CardContent>}
                </Card>

                <Card size="sm">
                  <CardHeader><CardTitle>View</CardTitle></CardHeader>
                  <CardContent className="flex flex-col gap-3">
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
                  </CardContent>
                </Card>

                <Card size="sm">
                  <CardHeader><CardTitle>Legend</CardTitle></CardHeader>
                  <CardContent className="grid grid-cols-2 gap-x-3 gap-y-1.5 text-xs text-muted-foreground">
                    <div className="col-span-2 mb-1">Small markers are possible battery centers. Select one to see every 10 cm square in the required placement envelope. The spot is scan-eligible only when every displayed square is green.</div>
                    {[
                      [SWATCH.pass, "Green square: scanned and clear"], [SWATCH.conflict, "Red square: blocked or crosses the wall"],
                      [SWATCH.unknown, "Amber square: ground not scanned"], ["bg-slate-400/60", "Scanned ground with no valid center (hover: why)"],
                      ["bg-amber-300/70", "Beside a wall scanned too low to confirm"], ["bg-purple-500", "Meter, 20 ft reach ring, transfer-switch space"],
                      ["bg-teal-500", "Panel"], ["bg-pink-500", "Gas meter"],
                    ].map(([c, t]) => <div key={t} className="flex items-center gap-2"><span className={cn("size-2.5 shrink-0 rounded-sm", c)} />{t}</div>)}
                    {colorMode === "labels" && ([[1, "Wall"], [2, "Floor"], [6, "Window"], [7, "Door"], [4, "Table"], [5, "Seat"], [0, "Other"]] as const).map(([i, t]) => (
                      <div key={t} className="flex items-center gap-2"><span className="size-2.5 shrink-0 rounded-sm" style={{ background: `rgb(${LABEL_RGB[i].join(",")})` }} />{t}</div>
                    ))}
                  </CardContent>
                </Card>
              </>
            )}

            <p className="text-muted-foreground text-xs">
              Preliminary survey only. Green means the complete placement envelope passed every check this scan can measure. It is not an electrical inspection, code review, permitting decision, or installation approval.
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
