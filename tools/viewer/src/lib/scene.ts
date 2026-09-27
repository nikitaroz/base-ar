import * as THREE from "three"
import { OrbitControls } from "three/addons/controls/OrbitControls.js"
import { CELL, FT, IN, LABELS, type Analysis, type FloorCell, type GridCell, type Mark, type PLY, type Spot } from "./checker.js"

export type ColorMode = "camera" | "labels"
export type ViewMode = "orbit" | "top"

export const STATUS_HEX = { pass: 0x22c55e, conflict: 0xef4444, unknown: 0xf59e0b, offwall: 0x8a93a3 } as const
/** Scanned floor where no battery can stand: gray, or pale amber next to a wall that may just need scanning higher. */
export const FLOOR_HEX = { far: 0x9aa3b2, lowwall: 0xe8c47a } as const
/** ARKit classification colors, indexed by label. Matches the review screen: blue wall, cyan window, green floor. */
export const LABEL_RGB: [number, number, number][] = [
  [150, 150, 150], [59, 111, 216], [196, 214, 176], [190, 190, 190], [230, 138, 46], [201, 70, 143], [54, 201, 224], [138, 90, 43],
]
export const MARK_HEX: Record<string, number> = {
  meter_wall: 0xa855f7, meter_ground: 0xa855f7, panel_wall: 0x14b8a6, panel_ground: 0x14b8a6, gas_meter: 0xec4899,
}

interface Handlers {
  onHover: (cell: GridCell | FloorCell | null, x: number, y: number) => void
  onSelect: (spot: Spot, label: string) => void
}

/** Owns the WebGL view: mesh, marks, placement grid, battery. React only calls methods on it. */
export class SiteScene {
  private renderer: THREE.WebGLRenderer
  private scene = new THREE.Scene()
  private camera = new THREE.PerspectiveCamera(50, 1, 0.05, 200)
  private controls: OrbitControls
  // Eaves, porch roofs, and tree canopy hide the grid from above. The checks ignore them too.
  private cutPlane = new THREE.Plane(new THREE.Vector3(0, -1, 0), 1e6)
  private objects: THREE.Object3D[] = []
  private meshes: Record<"site" | "ceiling", THREE.Mesh> | null = null
  private grid: THREE.InstancedMesh | null = null
  /** Scanned floor where no battery can stand: faint gray ("far") and more visible pale amber ("lowwall"). */
  private floorLayers: { mesh: THREE.InstancedMesh; cells: FloorCell[] }[] = []
  private battery: THREE.Group | null = null
  private parts: { body: THREE.Mesh; pad: THREE.LineLoop; envelope: THREE.InstancedMesh; sides: THREE.Group } | null = null
  private analysis: Analysis | null = null
  private home: { target: THREE.Vector3; out: THREE.Vector3 } | null = null
  /** Analyzed cells, for framing the Top view. */
  private cellBounds: THREE.Box3 | null = null
  private floorY = 0
  private dragging = false
  private ray = new THREE.Raycaster()
  private ndc = new THREE.Vector2()
  private observer: ResizeObserver
  view: ViewMode = "orbit"

  private host: HTMLElement
  private handlers: Handlers

  constructor(host: HTMLElement, handlers: Handlers) {
    this.host = host
    this.handlers = handlers
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true })
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, 2))
    this.renderer.localClippingEnabled = true
    this.renderer.setClearColor(0x000000, 0)
    // CSS owns the canvas's display size; setSize below only sizes the pixel buffer.
    Object.assign(this.renderer.domElement.style, { width: "100%", height: "100%", display: "block" })
    host.appendChild(this.renderer.domElement)
    this.controls = new OrbitControls(this.camera, this.renderer.domElement)
    this.controls.enableDamping = true
    this.scene.add(new THREE.HemisphereLight(0xffffff, 0x778899, 2.2))
    const sun = new THREE.DirectionalLight(0xffffff, 1.2)
    sun.position.set(3, 8, 5)
    this.scene.add(sun)
    this.observer = new ResizeObserver(() => this.resize())
    this.observer.observe(host)
    this.renderer.setAnimationLoop(() => { this.controls.update(); this.renderer.render(this.scene, this.camera) })
    this.bindPointer()
  }

  dispose() {
    this.observer.disconnect()
    this.renderer.setAnimationLoop(null)
    this.clear()
    this.renderer.dispose()
    this.renderer.domElement.remove()
  }

  private resize() {
    const r = this.host.getBoundingClientRect()
    this.renderer.setSize(r.width, r.height, false)
    this.camera.aspect = r.width / Math.max(r.height, 1)
    this.camera.updateProjectionMatrix()
  }

  private add<T extends THREE.Object3D>(o: T): T {
    this.scene.add(o)
    this.objects.push(o)
    return o
  }

  private clear() {
    for (const o of this.objects) {
      this.scene.remove(o)
      o.traverse((c) => {
        const m = c as THREE.Mesh
        m.geometry?.dispose()
        const mat = m.material as THREE.Material | THREE.Material[] | undefined
        if (Array.isArray(mat)) mat.forEach((x) => x.dispose())
        else mat?.dispose()
      })
    }
    this.objects = []
    this.meshes = this.grid = this.battery = this.parts = null
    this.cellBounds = null
    this.floorLayers = []
  }

  load(ply: PLY, a: Analysis, opts: { colorMode: ColorMode; showGrid: boolean; showFloor: boolean; showCeiling: boolean; cutAbove: boolean }) {
    this.clear()
    this.analysis = a

    // Site and ceiling as separate non-indexed meshes, each carrying camera and label colors.
    const { positions: P, colors: C, faces: F, labels: Lb } = ply
    const parts: Record<"site" | "ceiling", number[]> = { site: [], ceiling: [] }
    for (let f = 0; f < Lb.length; f++) {
      if (Lb[f] === LABELS.OVERLAY) continue
      ;(Lb[f] === LABELS.CEILING ? parts.ceiling : parts.site).push(f)
    }
    const meshes = {} as Record<"site" | "ceiling", THREE.Mesh>
    for (const name of ["site", "ceiling"] as const) {
      const list = parts[name]
      const pos = new Float32Array(list.length * 9), cam = new Uint8Array(list.length * 9), lab = new Uint8Array(list.length * 9)
      list.forEach((f, k) => {
        const lc = LABEL_RGB[Lb[f]] ?? [0, 0, 0]
        for (let v = 0; v < 3; v++) {
          const vi = F[f * 3 + v]
          for (let d = 0; d < 3; d++) {
            pos[k * 9 + v * 3 + d] = P[vi * 3 + d]
            cam[k * 9 + v * 3 + d] = C[vi * 3 + d]
            lab[k * 9 + v * 3 + d] = lc[d]
          }
        }
      })
      const g = new THREE.BufferGeometry()
      g.setAttribute("position", new THREE.BufferAttribute(pos, 3))
      g.userData = { cam: new THREE.BufferAttribute(cam, 3, true), lab: new THREE.BufferAttribute(lab, 3, true) }
      g.setAttribute("color", g.userData.cam)
      g.computeVertexNormals()
      meshes[name] = this.add(new THREE.Mesh(g, new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide, clippingPlanes: [this.cutPlane] })))
    }
    this.meshes = meshes
    this.floorY = a.groundY ?? new THREE.Box3().setFromBufferAttribute(meshes.site.geometry.attributes.position as THREE.BufferAttribute).min.y
    this.setColorMode(opts.colorMode)
    this.setCeiling(opts.showCeiling)
    this.setCutAbove(opts.cutAbove)

    // Taps sit on the wall's surface; draw them on top so the mesh never hides them.
    const marks = a.marks ?? {}
    for (const [name, hex] of Object.entries(MARK_HEX)) {
      const m = marks[name] as Mark | undefined
      if (!m || typeof m === "string") continue
      const s = this.add(new THREE.Mesh(new THREE.SphereGeometry(0.07, 20, 14), new THREE.MeshBasicMaterial({ color: hex, depthTest: false })))
      s.renderOrder = 5
      s.position.set(...m.p)
    }

    const meterWall = marks.meter_wall as Mark | undefined
    const target = meterWall ? new THREE.Vector3(...meterWall.p)
      : new THREE.Box3().setFromBufferAttribute(meshes.site.geometry.attributes.position as THREE.BufferAttribute).getCenter(new THREE.Vector3())
    if (a.groundY != null) target.y = a.groundY
    this.home = { target, out: a.meterFrame ? new THREE.Vector3(...a.meterFrame.out) : new THREE.Vector3(0, 0, 1) }
    this.setView(this.view)
    if (!a.grid || !a.rules) return

    // Candidate centers are deliberately small. The selected placement draws the full required envelope as
    // 10 cm squares, so the center ribbon cannot be mistaken for the area occupied by a battery.
    const mtx = new THREE.Matrix4(), col = new THREE.Color()
    const tiles = (cells: { x: number; y: number; z: number }[], size: number, opacity: number, hex: (i: number) => number, lift: number) => {
      const mesh = new THREE.InstancedMesh(new THREE.PlaneGeometry(size, size).rotateX(-Math.PI / 2),
        new THREE.MeshBasicMaterial({ transparent: true, opacity, depthWrite: false }), Math.max(cells.length, 1))
      mesh.count = cells.length
      cells.forEach((g, i) => { mesh.setMatrixAt(i, mtx.makeTranslation(g.x, g.y + lift, g.z)); mesh.setColorAt(i, col.setHex(hex(i))) })
      return mesh
    }
    const floor = a.floor ?? []
    this.cellBounds = new THREE.Box3()
    for (const g of [...a.grid, ...floor]) this.cellBounds.expandByPoint(new THREE.Vector3(g.x, g.y, g.z))
    if (this.view === "top") this.setView("top")
    for (const [kind, opacity] of [["far", 0.35], ["lowwall", 0.75]] as const) {
      const cells = floor.filter((f) => f.kind === kind)
      const mesh = tiles(cells, 0.08, opacity, () => FLOOR_HEX[kind], 0.018)
      mesh.renderOrder = 1
      mesh.visible = opts.showGrid && opts.showFloor
      this.floorLayers.push({ mesh: this.add(mesh), cells })
    }
    const grid = tiles(a.grid, 0.045, 0.8, (i) => STATUS_HEX[a.grid![i].status], 0.025)
    grid.renderOrder = 2
    grid.visible = opts.showGrid
    this.grid = this.add(grid)

    // How far a battery may be from the meter: a dashed ring on the ground.
    if (a.reach) {
      const { center, radius } = a.reach
      const ring = new THREE.LineLoop(
        new THREE.BufferGeometry().setFromPoints(Array.from({ length: 160 }, (_, k) => {
          const t = (k / 160) * Math.PI * 2
          return new THREE.Vector3(center[0] + Math.cos(t) * radius, center[1] + 0.03, center[2] + Math.sin(t) * radius)
        })),
        new THREE.LineDashedMaterial({ color: MARK_HEX.meter_wall, dashSize: 0.2, gapSize: 0.12, transparent: true, opacity: 0.8 }))
      ring.computeLineDistances()
      this.add(ring)
    }

    if (a.transferBox) {
      const t = a.transferBox
      const edges = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(...t.size)), new THREE.LineBasicMaterial({ color: MARK_HEX.meter_wall }))
      edges.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(new THREE.Vector3(...t.along), new THREE.Vector3(0, 1, 0), new THREE.Vector3(...t.out)))
      edges.position.set(...t.center)
      this.add(edges)
    }

    // Battery: cabinet, filled 3 ft placement area, and the full-depth side-clearance regions.
    const r = a.rules
    const [bw, bh, bd] = r.battery_in.map((v) => v * IN)
    const fp = r.footprint_side_ft * FT
    const side = r.side_clearance_ft * FT
    const outline = (w0: number, w1: number, d0: number, d1: number, dashed = false) => {
      const geo = new THREE.BufferGeometry().setFromPoints([[w0, d0], [w1, d0], [w1, d1], [w0, d1]].map(([x, z]) => new THREE.Vector3(x, 0.035, z)))
      const line = new THREE.LineLoop(geo, dashed ? new THREE.LineDashedMaterial({ color: 0xffffff, dashSize: 0.06, gapSize: 0.04 }) : new THREE.LineBasicMaterial({ color: 0xffffff }))
      if (dashed) line.computeLineDistances()
      return line
    }
    const body = new THREE.Mesh(new THREE.BoxGeometry(bw, bh, bd), new THREE.MeshLambertMaterial({ color: 0xe6e7ea, transparent: true, opacity: 0.92 }))
    body.position.y = bh / 2
    const pad = outline(-fp / 2, fp / 2, -fp / 2, fp / 2)
    const envelopeCapacity = Math.ceil(fp / CELL) ** 2 * 3
    const envelope = new THREE.InstancedMesh(
      new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2),
      new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.55, depthWrite: false, side: THREE.DoubleSide }),
      envelopeCapacity,
    )
    envelope.count = 0
    envelope.renderOrder = 4
    const sides = new THREE.Group()
    sides.add(
      outline(-fp / 2 - side, -fp / 2, -fp / 2, fp / 2, true),
      outline(fp / 2, fp / 2 + side, -fp / 2, fp / 2, true),
    )
    const battery = new THREE.Group()
    battery.add(body, envelope, pad, sides)
    battery.visible = false
    this.battery = this.add(battery)
    this.parts = { body, pad, envelope, sides }
  }

  /** Moves the battery to a spot and tints it by result. An off-wall drag keeps the cabinet under the pointer, gray. */
  showSpot(spot: Spot | null, at?: THREE.Vector3) {
    if (!this.battery || !this.parts || !spot) return
    const p = this.parts
    if (spot.status === "offwall") {
      if (at) this.battery.position.set(at.x, this.floorY, at.z)
      ;(p.body.material as THREE.MeshLambertMaterial).color.setHex(STATUS_HEX.offwall)
      p.envelope.count = 0
      for (const l of [p.pad, ...p.sides.children] as THREE.LineLoop[]) (l.material as THREE.LineBasicMaterial).color.setHex(STATUS_HEX.offwall)
      return
    }
    this.battery.visible = true
    this.battery.position.set(...spot.center)
    this.battery.rotation.set(0, spot.yaw, 0)
    const hex = STATUS_HEX[spot.status]
    ;(p.body.material as THREE.MeshLambertMaterial).color.setHex(spot.status === "pass" ? 0xe6e7ea : hex)
    const cells = spot.envelope ?? []
    const matrix = new THREE.Matrix4(), color = new THREE.Color()
    p.envelope.count = cells.length
    cells.forEach((cell, index) => {
      matrix.makeScale(cell.width * 0.92, 1, cell.depth * 0.92)
      matrix.setPosition(cell.u, 0.025, cell.w)
      p.envelope.setMatrixAt(index, matrix)
      p.envelope.setColorAt(index, color.setHex(STATUS_HEX[cell.status]))
    })
    p.envelope.instanceMatrix.needsUpdate = true
    if (p.envelope.instanceColor) p.envelope.instanceColor.needsUpdate = true
    for (const l of [p.pad, ...p.sides.children] as THREE.LineLoop[]) (l.material as THREE.LineBasicMaterial).color.setHex(hex)
  }

  setColorMode(mode: ColorMode) {
    if (!this.meshes) return
    for (const m of Object.values(this.meshes)) m.geometry.setAttribute("color", mode === "labels" ? m.geometry.userData.lab : m.geometry.userData.cam)
  }
  setGrid(on: boolean, floor: boolean) {
    if (this.grid) this.grid.visible = on
    for (const l of this.floorLayers) l.mesh.visible = on && floor
  }
  setCeiling(on: boolean) { if (this.meshes) this.meshes.ceiling.visible = on }
  setCutAbove(on: boolean) { this.cutPlane.constant = on ? this.floorY + 2.2 : 1e6 }

  /** Top: straight down, meter wall at the top of the screen. 3D: behind and above the yard. */
  setView(mode: ViewMode) {
    this.view = mode
    if (!this.home) return
    const { target, out } = this.home
    this.controls.target.copy(target)
    if (mode === "top") {
      // Look straight down at the analyzed cells, framed to fit, meter wall toward the top of the screen.
      const b = this.cellBounds && !this.cellBounds.isEmpty() ? this.cellBounds : null
      const center = b ? b.getCenter(new THREE.Vector3()).setY(target.y) : target.clone()
      const size = b ? b.getSize(new THREE.Vector3()) : new THREE.Vector3(10, 0, 10)
      const along = new THREE.Vector3(out.z, 0, -out.x)
      const across = Math.abs(size.x * along.x) + Math.abs(size.z * along.z)   // extent along the meter wall
      const deep = Math.abs(size.x * out.x) + Math.abs(size.z * out.z)         // extent out from it
      const half = Math.tan(THREE.MathUtils.degToRad(this.camera.fov / 2))
      const height = Math.max(deep, across / this.camera.aspect) / (2 * half) * 1.12 + 1
      this.controls.target.copy(center)
      this.camera.position.copy(center).addScaledVector(out, 0.001).add(new THREE.Vector3(0, height, 0))
      this.camera.up.set(-out.x, 0, -out.z)
      this.camera.lookAt(center)
      this.controls.update()
      return
    } else {
      this.camera.up.set(0, 1, 0)
      this.camera.position.copy(target).addScaledVector(out, 5).add(new THREE.Vector3(0, 7, 0))
    }
    this.camera.lookAt(target)
    this.controls.update()
  }

  // Hover a cell for its result, click to select it, drag the battery to move it.
  private bindPointer() {
    const el = this.renderer.domElement
    const aim = (e: PointerEvent | MouseEvent) => {
      const r = el.getBoundingClientRect()
      this.ndc.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1)
      this.ray.setFromCamera(this.ndc, this.camera)
      return r
    }
    // Bold candidate tiles win over the faint floor tiles under the same pointer.
    const cellAt = (): GridCell | FloorCell | null => {
      const a = this.analysis
      const hit = this.grid?.visible ? this.ray.intersectObject(this.grid)[0] : undefined
      if (hit?.instanceId != null && a?.grid) return a.grid[hit.instanceId]
      let nearest: { d: number; cell: FloorCell } | null = null
      for (const l of this.floorLayers) {
        const h = l.mesh.visible ? this.ray.intersectObject(l.mesh)[0] : undefined
        if (h?.instanceId != null && (!nearest || h.distance < nearest.d)) nearest = { d: h.distance, cell: l.cells[h.instanceId] }
      }
      return nearest?.cell ?? null
    }
    // A click only selects when the pointer barely moved: releasing an orbit or a battery drag is not a click.
    // A finger drifts more than a mouse during a tap, so touch gets a wider slop.
    let down = { x: 0, y: 0, slop: 4 }
    const endDrag = () => {
      if (!this.dragging) return
      this.dragging = false
      this.controls.enabled = true
    }
    el.addEventListener("pointerdown", (e) => {
      down = { x: e.clientX, y: e.clientY, slop: e.pointerType === "touch" ? 12 : 4 }
      if (!this.battery?.visible || !this.parts) return
      aim(e)
      if (this.ray.intersectObject(this.parts.body).length) {
        this.dragging = true
        this.controls.enabled = false
        el.setPointerCapture(e.pointerId)
      }
    })
    el.addEventListener("pointermove", (e) => {
      const a = this.analysis
      if (!a?.grid) return
      const r = aim(e)
      if (this.dragging && a.evaluateAt) {
        const p = this.ray.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), -this.floorY), new THREE.Vector3())
        if (!p) return
        const spot = a.evaluateAt(p.x, p.z)
        this.showSpot(spot, p)
        this.handlers.onSelect(spot, "dragged")
        this.handlers.onHover(null, 0, 0)
        return
      }
      const cell = cellAt()
      el.style.cursor = cell && cell.status !== "offwall" ? "pointer" : ""
      this.handlers.onHover(cell, e.clientX - r.left, e.clientY - r.top)
    })
    el.addEventListener("pointerup", endDrag)
    el.addEventListener("pointercancel", endDrag)
    el.addEventListener("lostpointercapture", endDrag)
    el.addEventListener("pointerleave", () => this.handlers.onHover(null, 0, 0))
    el.addEventListener("click", (e) => {
      const a = this.analysis
      if (!a?.grid || Math.hypot(e.clientX - down.x, e.clientY - down.y) > down.slop) return
      aim(e)
      const cell = cellAt()
      if (!cell || cell.status === "offwall") return
      const spot = cell.spot
      this.showSpot(spot)
      this.handlers.onSelect(spot, "clicked cell")
    })
  }
}
