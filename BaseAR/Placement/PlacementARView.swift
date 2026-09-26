import ARKit
import RealityKit
import SwiftUI

enum PlacementTarget: String, CaseIterable, Identifiable {
    case battery
    case meter
    case panel
    case gasMeter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .meter: "Meter"
        case .panel: "Panel"
        case .gasMeter: "Gas"
        }
    }

    var hint: String {
        switch self {
        case .battery:
            "Tap the ground to place the battery. Drag to move it. Twist with two fingers to rotate."
        case .meter:
            "Tap the ground below the electric meter, then tap the meter on the wall. Meter height needs both taps."
        case .panel:
            "Tap the ground below the main breaker panel, then tap the panel on the wall."
        case .gasMeter:
            "Tap the ground at the gas meter if you can see one."
        }
    }
}

struct PlacementARView: View {
    var store: SurveyStore
    var onContinue: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: PlacementTarget = .battery
    @State private var yawRadians: Float
    @State private var scene: PlacementSceneSnapshot
    @State private var screenshotToken: UUID? = nil
    /// Set while a save waits for its screenshot. Cleared when it advances, so the view can save again after Back.
    @State private var pendingSave: UUID? = nil
    @State private var statusMessage: String? = nil
    @State private var isVisible = false

    init(store: SurveyStore, onContinue: @escaping () -> Void) {
        self.store = store
        self.onContinue = onContinue
        let existing = store.placementController
        _scene = State(initialValue: existing?.scene ?? PlacementSceneSnapshot())
        _yawRadians = State(initialValue: existing?.yawRadians ?? 0)
    }

    private var isSaving: Bool { pendingSave != nil }

    private var arSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    private var liveAssessment: SurveyAssessment {
        if scene.hasPlacedContent {
            return store.assessment(applying: scene)
        }
        return SurveyAssessment(
            results: store.session.ruleResults,
            placementTone: store.session.placementTone,
            missingInformation: store.session.missingInformation
        )
    }

    var body: some View {
        Group {
            if arSupported {
                arScreen
            } else {
                unsupportedScreen
            }
        }
        .navigationTitle("Placement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            guard arSupported else { return }
            isVisible = true
            let controller = store.requirePlacementController()
            controller.resume()
            scene = controller.scene
            yawRadians = controller.yawRadians
        }
        .onDisappear {
            isVisible = false
            store.placementController?.pauseIfIdle()
        }
        .onChange(of: scenePhase) { _, phase in
            guard isVisible, arSupported else { return }
            if phase == .active {
                store.placementController?.resume()
            } else if phase == .background {
                store.placementController?.pauseIfIdle()
            }
        }
    }

    private var arScreen: some View {
        let tone = liveAssessment.placementTone
        return ZStack {
            if let controller = store.placementController {
                PlacementARRepresentable(
                    controller: controller,
                    mode: mode,
                    yawRadians: yawRadians,
                    tone: tone,
                    screenshotToken: screenshotToken,
                    onSceneChange: { scene = $0 },
                    onYawChange: { yawRadians = $0 },
                    onScreenshot: handleScreenshot,
                    onFailure: { statusMessage = $0 }
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 12) {
                controlsCard
                Spacer()
                readoutCard(tone: tone)
            }
            .padding()
        }
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Place", selection: $mode) {
                ForEach(PlacementTarget.allCases) { target in
                    Text(target.title).tag(target)
                }
            }
            .pickerStyle(.segmented)
            Text(mode.hint)
                .font(.footnote)
            Text(scene.lidarMeshAvailable
                 ? "LiDAR mesh is on. Placement also works from ground and wall planes."
                 : "Using ground and wall planes. This iPhone has no LiDAR mesh.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func readoutCard(tone: PlacementTone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ToneStyle.title(tone))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToneStyle.color(tone))
            Text("Preview \(formatInches(BatteryGeometry.widthInches)) in W × \(formatInches(BatteryGeometry.heightInches)) in H × \(formatInches(BatteryGeometry.depthInches)) in D, on a \(Int(BaseRuleSet.footprintSideFeet)) ft × \(Int(BaseRuleSet.footprintSideFeet)) ft pad.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(distanceLine)
                .font(.footnote)
            HStack {
                // Positive yaw about +Y turns counterclockwise seen from above, which reads as "left".
                Button("Rotate left") { yawRadians += .pi / 12 }
                    .accessibilityLabel("Rotate battery left 15 degrees")
                Button("Rotate right") { yawRadians -= .pi / 12 }
                    .accessibilityLabel("Rotate battery right 15 degrees")
            }
            .buttonStyle(.bordered)
            .disabled(scene.batteryPosition == nil)
            attestationToggles
            Button {
                saveAndReview()
            } label: {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Save placement and review")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
            Text("Green only when every required check has measured evidence and passes. Teal means a pass relied on an attestation, not a measurement. This is not installation approval.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var attestationToggles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("I visually confirmed the 3 ft × 3 ft footprint is clear", isOn: footprintAttestBinding)
                .font(.footnote)
            Toggle("I visually confirmed transfer-switch space beside the meter", isOn: transferSwitchAttestBinding)
                .font(.footnote)
            Text("Attestations are your statements, not app measurements.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .disabled(scene.batteryPosition == nil && store.session.placement.batteryPosition == nil)
    }

    private var footprintAttestBinding: Binding<Bool> {
        Binding(
            get: { store.session.placement.footprintClearAttested == true },
            set: { store.setFootprintClearAttested($0) }
        )
    }

    private var transferSwitchAttestBinding: Binding<Bool> {
        Binding(
            get: { store.session.placement.transferSwitchSpaceAttested == true },
            set: { store.setTransferSwitchSpaceAttested($0) }
        )
    }

    private var unsupportedScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AR placement needs a physical iPhone.")
            Text("This device cannot start world tracking, so the battery preview, meter mark, and placement photo stay empty. The review will list them as missing.")
                .foregroundStyle(.secondary)
            Button("Continue to review") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var distanceLine: String {
        let measured = store.measurements(for: scene)
        return [
            feetLabel("Meter", measured.distanceToMeterFeet),
            feetLabel("Wall", measured.distanceToWallFeet),
            feetLabel("Gas", measured.distanceToGasMeterFeet)
        ].joined(separator: "  ·  ")
    }

    private func feetLabel(_ name: String, _ feet: Double?) -> String {
        guard let feet else { return "\(name): —" }
        return String(format: "%@: %.1f ft", name, feet)
    }

    private func formatInches(_ inches: Float) -> String {
        String(format: "%g", inches)
    }

    private func saveAndReview() {
        guard !isSaving else { return }
        // Nothing placed in this session: keep any earlier placement evidence and screenshot.
        guard scene.hasPlacedContent else {
            onContinue()
            return
        }
        var committed = scene
        committed.batteryYawRadians = yawRadians
        store.commitPlacement(committed)
        let token = UUID()
        pendingSave = token
        screenshotToken = token
        statusMessage = nil
        Task {
            try? await Task.sleep(for: .seconds(5))
            failScreenshot(token)
        }
    }

    private func handleScreenshot(_ image: UIImage?) {
        if let image {
            store.attachPlacementScreenshot(image)
            advance(pendingSave)
        } else {
            failScreenshot(pendingSave)
        }
    }

    private func advance(_ token: UUID?) {
        guard let token, token == pendingSave else { return }
        pendingSave = nil
        onContinue()
    }

    private func failScreenshot(_ token: UUID?) {
        guard let token, token == pendingSave else { return }
        pendingSave = nil
        screenshotToken = nil
        statusMessage = "Placement screenshot did not capture. Tap Save again."
    }
}

private struct PlacementARRepresentable: UIViewRepresentable {
    var controller: PlacementSceneController
    var mode: PlacementTarget
    var yawRadians: Float
    var tone: PlacementTone
    var screenshotToken: UUID?
    var onSceneChange: (PlacementSceneSnapshot) -> Void
    var onYawChange: (Float) -> Void
    var onScreenshot: (UIImage?) -> Void
    var onFailure: (String) -> Void

    func makeUIView(context: Context) -> ARView {
        controller.prepareIfNeeded()
        return controller.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        controller.bind(
            mode: mode,
            yawRadians: yawRadians,
            tone: tone,
            screenshotToken: screenshotToken,
            onSceneChange: onSceneChange,
            onYawChange: onYawChange,
            onScreenshot: onScreenshot,
            onFailure: onFailure
        )
    }
}

/// Owns the AR session for one survey. The placement screen can disappear without dropping marks,
/// because a new session would not share the old world coordinates.
@MainActor
final class PlacementSceneController: NSObject, ARSessionDelegate {
    let arView = ARView(frame: .zero)
    private(set) var scene = PlacementSceneSnapshot()
    var yawRadians: Float = 0

    private var mode: PlacementTarget = .battery
    private var configuration: ARWorldTrackingConfiguration?
    private var isPrepared = false
    private var screenshotInFlight = false
    private var pauseRequested = false
    private var onSceneChange: ((PlacementSceneSnapshot) -> Void)?
    private var onYawChange: ((Float) -> Void)?
    private var onScreenshot: ((UIImage?) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var root: AnchorEntity?
        var batteryRig: Entity?
        var batteryBody: ModelEntity?
        var footprintPad: ModelEntity?
        var meterMarker: ModelEntity?
        var meterWallMarker: ModelEntity?
        var meterWallHit: (position: SIMD3<Float>, normal: SIMD3<Float>)?
        var panelMarker: ModelEntity?
        var panelWallMarker: ModelEntity?
        var panelWallHit: (position: SIMD3<Float>, normal: SIMD3<Float>)?
        var gasMarker: ModelEntity?
        var planes: [UUID: PlaneSample] = [:]
        /// Sub-sampled world-space mesh vertices, keyed by ARMeshAnchor identifier so removals stay cheap.
        var meshSamples: [UUID: [SIMD3<Float>]] = [:]
        var lidarMeshAvailable = false
        var appliedYaw: Float = 0
        var rotationStartYaw: Float = 0
        var appliedTone: PlacementTone?
        var lastScreenshotToken: UUID?
        var lastPlaneEmit = Date.distantPast

        func prepareIfNeeded() {
            guard !isPrepared else { return }
            isPrepared = true
            arView.automaticallyConfigureSession = false
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.environmentTexturing = .automatic
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                configuration.sceneReconstruction = .mesh
                lidarMeshAvailable = true
                arView.environment.sceneUnderstanding.options.insert(.occlusion)
                arView.debugOptions.insert(.showSceneUnderstanding)
            }
            self.configuration = configuration
            arView.session.delegate = self

            let coaching = ARCoachingOverlayView()
            coaching.session = arView.session
            coaching.goal = .horizontalPlane
            coaching.activatesAutomatically = true
            coaching.frame = arView.bounds
            coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            arView.addSubview(coaching)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            tap.require(toFail: rotation)
            arView.addGestureRecognizer(tap)
            arView.addGestureRecognizer(pan)
            arView.addGestureRecognizer(rotation)

            let anchor = AnchorEntity(world: .zero)
            arView.scene.addAnchor(anchor)
            root = anchor
            emit()
        }

        func bind(
            mode: PlacementTarget,
            yawRadians: Float,
            tone: PlacementTone,
            screenshotToken: UUID?,
            onSceneChange: @escaping (PlacementSceneSnapshot) -> Void,
            onYawChange: @escaping (Float) -> Void,
            onScreenshot: @escaping (UIImage?) -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.mode = mode
            self.onSceneChange = onSceneChange
            self.onYawChange = onYawChange
            self.onScreenshot = onScreenshot
            self.onFailure = onFailure
            if abs(appliedYaw - yawRadians) > 0.0001 {
                self.yawRadians = yawRadians
                appliedYaw = yawRadians
                applyYaw()
                emit()
            }
            if appliedTone != tone {
                appliedTone = tone
                applyTone()
            }
            if let screenshotToken, screenshotToken != lastScreenshotToken {
                lastScreenshotToken = screenshotToken
                takeScreenshot()
            }
        }

        func resume() {
            pauseRequested = false
            prepareIfNeeded()
            guard let configuration else { return }
            arView.session.run(configuration, options: [])
        }

        func pauseIfIdle() {
            guard isPrepared else { return }
            guard !screenshotInFlight else {
                pauseRequested = true
                return
            }
            pauseRequested = false
            // Any in-flight rotation gesture is invalidated by pausing the session.
            rotationStartYaw = appliedYaw
            arView.session.pause()
        }

        func stop() {
            onSceneChange = nil
            onYawChange = nil
            onScreenshot = nil
            onFailure = nil
            screenshotInFlight = false
            pauseRequested = false
            if isPrepared {
                arView.session.pause()
                arView.session.delegate = nil
            }
            arView.removeFromSuperview()
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let point = gesture.location(in: arView)
            var didPlace = false
            switch mode {
            case .battery:
                if let position = groundPosition(in: arView, at: point) {
                    placeBattery(at: position)
                    didPlace = true
                }
            case .meter, .panel:
                // Two-stage: try a wall hit first (user tilting at the meter/panel on a vertical plane); fall back to a ground hit.
                if let wallHit = wallHit(in: arView, at: point) {
                    placeWallMarker(kind: mode, hit: wallHit)
                    didPlace = true
                } else if let position = groundPosition(in: arView, at: point) {
                    placeMarker(kind: mode, at: position)
                    didPlace = true
                }
            case .gasMeter:
                if let position = groundPosition(in: arView, at: point) {
                    placeMarker(kind: .gasMeter, at: position)
                    didPlace = true
                }
            }
            if didPlace { emit() }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard mode == .battery, batteryRig != nil else { return }
            let finished = gesture.state == .ended || gesture.state == .cancelled
            if let position = groundPosition(in: arView, at: gesture.location(in: arView)) {
                batteryRig?.position = position
            } else if !finished {
                return
            }
            if finished {
                emitGestureEnded()
            } else {
                emitPlanesIfNeeded()
            }
        }

        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard mode == .battery, batteryRig != nil else { return }
            switch gesture.state {
            case .began:
                rotationStartYaw = appliedYaw
            case .changed, .ended:
                // Gesture rotation is clockwise-positive on screen; yaw about +Y is counterclockwise-positive from above.
                let yaw = rotationStartYaw - Float(gesture.rotation)
                yawRadians = yaw
                appliedYaw = yaw
                applyYaw()
                onYawChange?(yaw)
                if gesture.state == .changed {
                    emitPlanesIfNeeded()
                } else {
                    emitGestureEnded()
                }
            case .cancelled:
                // System cancels happen on scenePhase changes or interruptions; roll back the partial rotation.
                yawRadians = rotationStartYaw
                appliedYaw = rotationStartYaw
                applyYaw()
                onYawChange?(rotationStartYaw)
                emitGestureEnded()
            default:
                break
            }
        }

        func applyYaw() {
            batteryRig?.orientation = simd_quatf(angle: appliedYaw, axis: SIMD3(0, 1, 0))
        }

        func applyTone() {
            guard let tone = appliedTone else { return }
            let color = ToneStyle.uiColor(tone)
            batteryBody?.model?.materials = [SimpleMaterial(color: color, isMetallic: false)]
            footprintPad?.model?.materials = [UnlitMaterial(color: color.withAlphaComponent(0.35))]
        }

        func takeScreenshot() {
            screenshotInFlight = true
            arView.snapshot(saveToHDR: false) { [weak self] image in
                Task { @MainActor in
                    self?.finishScreenshot(image)
                }
            }
        }

        private func finishScreenshot(_ image: UIImage?) {
            screenshotInFlight = false
            onScreenshot?(image)
            if pauseRequested {
                pauseIfIdle()
            }
        }

        func emit() {
            let snapshot = makeSnapshot()
            scene = snapshot
            let change = onSceneChange
            Task { @MainActor in
                change?(snapshot)
            }
        }

        nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            upsertPlanes(from: anchors)
            upsertMesh(from: anchors)
        }

        nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            upsertPlanes(from: anchors)
            upsertMesh(from: anchors)
        }

        /// LiDAR mesh anchors update many times a second; skip the hop to the main actor when no wall changed.
        private nonisolated func upsertPlanes(from anchors: [ARAnchor]) {
            let samples = Self.planeSamples(from: anchors)
            guard !samples.isEmpty else { return }
            Task { @MainActor in
                self.upsert(samples)
            }
        }

        private nonisolated func upsertMesh(from anchors: [ARAnchor]) {
            let samples = Self.meshSamples(from: anchors)
            guard !samples.isEmpty else { return }
            Task { @MainActor in
                self.upsertMesh(samples)
            }
        }

        nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            let ids = anchors.map(\.identifier)
            Task { @MainActor in
                for id in ids {
                    self.planes.removeValue(forKey: id)
                    self.meshSamples.removeValue(forKey: id)
                }
                self.emitPlanesIfNeeded()
            }
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            let message = error.localizedDescription
            Task { @MainActor in
                self.onFailure?(message)
            }
        }

        private func upsert(_ samples: [PlaneSample]) {
            for sample in samples {
                planes[sample.id] = sample
            }
            emitPlanesIfNeeded()
        }

        private func upsertMesh(_ samples: [(id: UUID, points: [SIMD3<Float>])]) {
            for sample in samples {
                meshSamples[sample.id] = sample.points
            }
            emitPlanesIfNeeded()
        }

        private func emitPlanesIfNeeded() {
            guard batteryRig != nil else { return }
            let now = Date()
            guard now.timeIntervalSince(lastPlaneEmit) > 0.4 else { return }
            lastPlaneEmit = now
            emit()
        }

        private func emitGestureEnded() {
            lastPlaneEmit = Date()
            emit()
        }

        private func placeBattery(at position: SIMD3<Float>) {
            if batteryRig == nil {
                let rig = Entity()
                let padMesh = MeshResource.generateBox(
                    width: BatteryGeometry.footprintMeters,
                    height: 0.012,
                    depth: BatteryGeometry.footprintMeters
                )
                let pad = ModelEntity(mesh: padMesh, materials: [UnlitMaterial(color: UIColor.systemOrange.withAlphaComponent(0.35))])
                pad.position.y = 0.006

                let bodyMesh = MeshResource.generateBox(
                    width: BatteryGeometry.widthMeters,
                    height: BatteryGeometry.heightMeters,
                    depth: BatteryGeometry.depthMeters
                )
                let body = ModelEntity(mesh: bodyMesh, materials: [SimpleMaterial(color: .systemOrange, isMetallic: false)])
                body.position.y = 0.012 + BatteryGeometry.heightMeters / 2

                let markMesh = MeshResource.generateBox(width: 0.08, height: 0.08, depth: 0.02)
                let mark = ModelEntity(mesh: markMesh, materials: [UnlitMaterial(color: .darkGray)])
                mark.position = SIMD3(
                    0,
                    BatteryGeometry.heightMeters * 0.72,
                    BatteryGeometry.depthMeters / 2 + 0.01
                )

                rig.addChild(pad)
                rig.addChild(body)
                rig.addChild(mark)
                root?.addChild(rig)
                batteryRig = rig
                footprintPad = pad
                batteryBody = body
                applyTone()
            }
            batteryRig?.position = position
            applyYaw()
        }

        private func placeMarker(kind: PlacementTarget, at position: SIMD3<Float>) {
            let existing: ModelEntity?
            switch kind {
            case .meter: existing = meterMarker
            case .panel: existing = panelMarker
            case .gasMeter: existing = gasMarker
            case .battery: existing = nil
            }
            if let existing {
                existing.position = SIMD3(position.x, position.y + 0.14, position.z)
                return
            }
            let marker: ModelEntity
            switch kind {
            case .meter:
                let mesh = MeshResource.generateBox(width: 0.14, height: 0.28, depth: 0.14)
                marker = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)])
            case .panel:
                let mesh = MeshResource.generateBox(width: 0.14, height: 0.28, depth: 0.14)
                marker = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .systemIndigo, isMetallic: false)])
            case .gasMeter:
                let mesh = MeshResource.generateSphere(radius: 0.08)
                marker = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .systemPurple, isMetallic: false)])
            case .battery:
                return
            }
            marker.position = SIMD3(position.x, position.y + 0.14, position.z)
            root?.addChild(marker)
            switch kind {
            case .meter: meterMarker = marker
            case .panel: panelMarker = marker
            case .gasMeter: gasMarker = marker
            case .battery: break
            }
        }

        private func placeWallMarker(kind: PlacementTarget, hit: (position: SIMD3<Float>, normal: SIMD3<Float>)) {
            let color: UIColor
            switch kind {
            case .meter: color = .systemBlue
            case .panel: color = .systemIndigo
            default: return
            }
            let existing: ModelEntity?
            switch kind {
            case .meter: existing = meterWallMarker
            case .panel: existing = panelWallMarker
            default: existing = nil
            }
            let marker: ModelEntity
            if let existing {
                marker = existing
            } else {
                // Small disc on the wall so the user sees where their tap landed.
                let mesh = MeshResource.generateBox(width: 0.10, height: 0.10, depth: 0.02)
                marker = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: color, isMetallic: false)])
                root?.addChild(marker)
                switch kind {
                case .meter: meterWallMarker = marker
                case .panel: panelWallMarker = marker
                default: break
                }
            }
            marker.position = hit.position
            // Rotate the disc so its short axis points along the wall's outward normal.
            marker.orientation = simd_quatf(from: SIMD3(0, 0, 1), to: hit.normal)
            switch kind {
            case .meter: meterWallHit = hit
            case .panel: panelWallHit = hit
            default: break
            }
        }

        private func groundPosition(in arView: ARView, at point: CGPoint) -> SIMD3<Float>? {
            let hit = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first
                ?? arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first
            guard let hit else { return nil }
            let column = hit.worldTransform.columns.3
            return SIMD3(column.x, column.y, column.z)
        }

        private func wallHit(in arView: ARView, at point: CGPoint) -> (position: SIMD3<Float>, normal: SIMD3<Float>)? {
            // Prefer real plane geometry so the meter/panel snaps to the actual detected wall.
            guard let hit = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .vertical).first else {
                return nil
            }
            let column = hit.worldTransform.columns.3
            let position = SIMD3<Float>(column.x, column.y, column.z)
            var normal = SIMD3<Float>(0, 0, 1)
            if let planeAnchor = hit.anchor as? ARPlaneAnchor {
                // The plane's local +Y in world space is the outward normal for a vertical ARPlaneAnchor.
                let up = planeAnchor.transform * SIMD4<Float>(0, 1, 0, 0)
                normal = SIMD3(up.x, up.y, up.z)
                let len = simd_length(normal)
                if len > 0.0001 { normal /= len }
            }
            return (position, normal)
        }

        private func makeSnapshot() -> PlacementSceneSnapshot {
            var snapshot = PlacementSceneSnapshot()
            snapshot.lidarMeshAvailable = lidarMeshAvailable
            snapshot.verticalPlanes = Array(planes.values)
            snapshot.batteryYawRadians = appliedYaw
            if let batteryRig {
                snapshot.batteryPosition = PlacementAnchor(batteryRig.position(relativeTo: nil))
            }
            if let meterMarker {
                snapshot.meterPosition = PlacementAnchor(grounded(meterMarker.position(relativeTo: nil)))
            }
            if let meterWallHit {
                snapshot.meterWallPosition = PlacementAnchor(meterWallHit.position)
                snapshot.meterWallNormal = PlacementAnchor(meterWallHit.normal)
                // Fall back to projecting the wall X/Z as the ground position when the user only tapped the wall.
                if snapshot.meterPosition == nil {
                    snapshot.meterPosition = PlacementAnchor(SIMD3(meterWallHit.position.x, meterWallHit.position.y, meterWallHit.position.z))
                }
            }
            if let panelMarker {
                snapshot.panelPosition = PlacementAnchor(grounded(panelMarker.position(relativeTo: nil)))
            }
            if let panelWallHit {
                snapshot.panelWallPosition = PlacementAnchor(panelWallHit.position)
                snapshot.panelWallNormal = PlacementAnchor(panelWallHit.normal)
                if snapshot.panelPosition == nil {
                    snapshot.panelPosition = PlacementAnchor(SIMD3(panelWallHit.position.x, panelWallHit.position.y, panelWallHit.position.z))
                }
            }
            if let gasMarker {
                snapshot.gasMeterPosition = PlacementAnchor(grounded(gasMarker.position(relativeTo: nil)))
            }
            if snapshot.batteryPosition != nil {
                snapshot.meshPointsNearBattery = meshPointsNearBattery(radiusMeters: 3)
            }
            return snapshot
        }

        /// Filter the whole mesh point cloud to those within a small bounding cylinder around the battery.
        /// Keeps the snapshot small (bounded by device room size) and skips the far walls entirely.
        private func meshPointsNearBattery(radiusMeters: Float) -> [PlacementAnchor] {
            guard let batteryRig else { return [] }
            let battery = batteryRig.position(relativeTo: nil)
            let radiusSquared = radiusMeters * radiusMeters
            var result: [PlacementAnchor] = []
            for (_, points) in meshSamples {
                for point in points {
                    let dx = point.x - battery.x
                    let dz = point.z - battery.z
                    if dx * dx + dz * dz <= radiusSquared {
                        result.append(PlacementAnchor(point))
                    }
                }
            }
            return result
        }

        private func grounded(_ position: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(position.x, position.y - 0.14, position.z)
        }

        /// Sub-sample vertices from every ARMeshAnchor to world space. Skips non-mesh anchors and empty geometries.
        /// Sampling `sampleStride` vertices keeps the point cloud small enough for per-frame checks; grass and curbs still register.
        private nonisolated static func meshSamples(from anchors: [ARAnchor], sampleStride: Int = 24) -> [(id: UUID, points: [SIMD3<Float>])] {
            anchors.compactMap { anchor in
                guard let mesh = anchor as? ARMeshAnchor else { return nil }
                let geometry = mesh.geometry
                let vertices = geometry.vertices
                let vertexCount = vertices.count
                guard vertexCount > 0 else { return nil }
                let stride = vertices.stride
                let offset = vertices.offset
                let basePointer = vertices.buffer.contents().advanced(by: offset)
                let transform = mesh.transform
                let floatSize = MemoryLayout<Float>.size
                var points: [SIMD3<Float>] = []
                points.reserveCapacity(vertexCount / sampleStride + 1)
                var index = 0
                while index < vertexCount {
                    let vertexPointer = basePointer.advanced(by: index * stride)
                    let x = vertexPointer.load(as: Float.self)
                    let y = vertexPointer.advanced(by: floatSize).load(as: Float.self)
                    let z = vertexPointer.advanced(by: floatSize * 2).load(as: Float.self)
                    let world = transform * SIMD4<Float>(x, y, z, 1)
                    points.append(SIMD3(world.x, world.y, world.z))
                    index += sampleStride
                }
                return (mesh.identifier, points)
            }
        }

        private nonisolated static func planeSamples(from anchors: [ARAnchor]) -> [PlaneSample] {
            anchors.compactMap { anchor in
                guard let plane = anchor as? ARPlaneAnchor, plane.alignment == .vertical else { return nil }
                // The patch is offset by `center` and its extent is turned by `rotationOnYAxis`, both in anchor space.
                let transform = plane.transform
                let extentRotation = simd_quatf(angle: plane.planeExtent.rotationOnYAxis, axis: SIMD3(0, 1, 0))
                func world(_ v: SIMD3<Float>, w: Float) -> SIMD3<Float> {
                    let p = transform * SIMD4(v.x, v.y, v.z, w)
                    return SIMD3(p.x, p.y, p.z)
                }
                return PlaneSample(
                    id: plane.identifier,
                    center: world(plane.center, w: 1),
                    xAxis: world(extentRotation.act(SIMD3(1, 0, 0)), w: 0),
                    normal: world(SIMD3(0, 1, 0), w: 0),
                    zAxis: world(extentRotation.act(SIMD3(0, 0, 1)), w: 0),
                    width: plane.planeExtent.width,
                    length: plane.planeExtent.height
                )
            }
        }
}
