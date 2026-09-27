import ARKit
import simd
import UIKit

/// Holds one survey and the three workstream implementations.
/// Electrical, placement, and rules can be swapped from `init` without changing the screens.
@MainActor
@Observable
final class SurveyStore {
    private(set) var session: SurveySession
    var meterImage: UIImage?
    /// The one zipped survey folder handed to the share sheet.
    private(set) var exportURLs: [URL] = []
    /// Local survey.json from the last export.
    private(set) var surveyJSONURL: URL?
    private(set) var lastExportError: String?
    /// True while an export is writing. Share waits for it.
    private(set) var isExporting = false
    private var exportTask: Task<Void, Never>?
    /// Shown under the meter field after a scan or a failed read. Cleared when the user edits the number.
    private(set) var meterNumberNote: String?
    private(set) var isReadingMeterNumber = false
    /// True while the meter photo is only the AR scan's crop of the locked meter. Any other photo replaces it,
    /// and a redone meter lock drops it.
    private(set) var meterPhotoIsScanCrop = false
    /// True while the meter number is what OCR read from that crop, so dropping the crop drops the number too.
    private var meterNumberFromScanCrop = false
    /// The Live Survey's photo of the panel, from its automatic capture.
    private(set) var panelImage: UIImage?
    /// The Live Survey's crop of the spot shown as the gas meter (gas.jpg). Nil until one is shown.
    private(set) var gasImage: UIImage?
    /// Shown under the main-breaker value after a scan read it. Cleared when the user sets the value.
    private(set) var mainBreakerNote: String?
    /// True while the main-breaker value is the scan's read, so a redone panel drops it with the photo.
    private var mainBreakerFromScan = false
    /// Shown when the property fix failed or location access is off. Nil while waiting or after a fix.
    private(set) var locationStatusMessage: String?
    /// True from the tap until a fix or a failure. The form uses this so the tap has an immediate result.
    private(set) var isRequestingPropertyLocation = false
    /// True when the homeowner answered that there is no gas meter, as opposed to an unfinished mark.
    var gasMeterNotVisible: Bool { session.placement.gasMeterNotPresent }
    /// Lives for the whole survey so leaving placement does not drop the AR session or its marks.
    private(set) var placementController: PlacementSceneController?

    let directory: URL
    /// True when this store picked up the survey an earlier launch left unfinished.
    let isResumed: Bool
    private let measurer: any PlacementMeasuring
    private let evaluator: any SurveyEvaluating
    private let exporter: any SurveyExporting
    private let recognizer: any MeterNumberRecognizing
    private let locationProvider = PropertyLocationProvider()
    private var meterReadGeneration = 0

    // Autosave: survey.json and app-state.json, about a second after the last change, written off the main actor.
    static let autosaveDelay: Duration = .seconds(1)
    @ObservationIgnored private var autosaveTimer: Task<Void, Never>?
    @ObservationIgnored private var autosaveWrite: Task<Void, Never>?
    @ObservationIgnored private var lastAutosaved: (session: SurveySession, state: SurveyResumeState)?
    @ObservationIgnored private var isDiscarded = false
    @ObservationIgnored nonisolated(unsafe) private var backgroundObserver: (any NSObjectProtocol)?
    /// Set by `markFinished` (Share done). A finished survey is not resumed on the next launch.
    @ObservationIgnored private var finishedAt: Date?
    /// Bumped on every change to the session or a photo file. Share skips a re-export when nothing changed.
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var exportedRevision: Int?
    /// Look-around milestones for the photo kit. Kept out of `session` so the Live Survey does not re-render on them.
    @ObservationIgnored private var photoKitMoments: [PhotoKitMoment] = []
    @ObservationIgnored private var lastLookAround = (movedFarther: false, lookedLeft: false, lookedRight: false)

    /// The first store after launch resumes the newest unfinished survey (`SurveyLibrary.prepareForLaunch`).
    /// Every later one, Start over's included, is a fresh survey in a new folder.
    init(
        propertyIdentifier: String,
        measurer: any PlacementMeasuring = CorePlacementMeasurer(),
        evaluator: any SurveyEvaluating = BaseSurveyEvaluator(),
        exporter: any SurveyExporting = JSONSurveyExporter(),
        recognizer: any MeterNumberRecognizing = VisionElectricalRecognizer()
    ) throws {
        let resumed = SurveyLibrary.takePendingResume()
        var session = resumed?.session ?? SurveySession.new(propertyIdentifier: propertyIdentifier)
        session.schemaVersion = SurveySession.currentSchemaVersion
        self.session = session
        self.measurer = measurer
        self.evaluator = evaluator
        self.exporter = exporter
        self.recognizer = recognizer
        isResumed = resumed != nil
        directory = try resumed?.directory ?? Self.makeDirectory(id: session.id)
        locationProvider.onFix = { [weak self] fix in
            guard let self else { return }
            self.isRequestingPropertyLocation = false
            self.locationStatusMessage = nil
            self.session.propertyLocation = fix
            self.refreshAssessment()
        }
        locationProvider.onStatus = { [weak self] message in
            guard let self, self.session.propertyLocation == nil else { return }
            if message != nil {
                self.isRequestingPropertyLocation = false
            }
            self.locationStatusMessage = message
        }
        if let resumed { restore(resumed.state) }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushAutosave() }
        }
        refreshAssessment()
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }

    func requestPropertyLocation() {
        isRequestingPropertyLocation = true
        locationStatusMessage = nil
        locationProvider.request()
    }

    func retryPropertyLocation() {
        locationProvider.retry()
    }

    func setGasMeterNotVisible(_ value: Bool) {
        session.placement.gasMeterNotPresent = value
        refreshAssessment()
    }

    func requirePlacementController() -> PlacementSceneController {
        if let placementController { return placementController }
        let created = PlacementSceneController()
        created.setActiveModel(BatteryCatalog.baseCore)
        // The scan captures the meter and the panel by itself; the survey keeps the photo and the value it read.
        created.onScanCapture = { [weak self] capture in self?.acceptScanCapture(capture) }
        created.onScanCaptureCleared = { [weak self] kind in self?.dropScanCapture(kind) }
        // The gas step's crop of the spot the user showed, kept as gas.jpg for Review to check.
        created.onGasShown = { [weak self] image in
            if let image { self?.attachGasPhoto(image) }
        }
        created.surveyID = session.id
        created.keyframes.setDirectory(directory.appendingPathComponent("capture", isDirectory: true))
        placementController = created
        RealityKitWarmup.release()
        return created
    }

    /// Drops the in-memory AR session and the on-disk survey packet. The folder is renamed at once and deleted off
    /// the main thread, so Start over does not wait on a large capture folder.
    func discardSavedSurvey() {
        #if DEBUG
        FrameRecorder.shared.end(summary: ["discarded": true])
        #endif
        isDiscarded = true
        autosaveTimer?.cancel()
        autosaveTimer = nil
        placementController?.stop()
        placementController = nil
        SurveyLibrary.removeInBackground(directory)
    }

    /// Share finished: the next launch starts a new survey instead of resuming this one. Integrator: call it from
    /// the share sheet's completion when the activity completed.
    func markFinished() {
        finishedAt = Date()
        autosaveNow()
    }

    /// INTEGRATOR HOOK — not wired here (PlacementARView is not this file's). Report the look-around each time it
    /// changes, with the frame on screen then, so the photo kit can prefer the frames taken at those moments:
    ///
    ///     .onChange(of: lookAround) { _, next in
    ///         store.notePhotoKitLookAround(movedFarther: next.movedFarther, lookedLeft: next.lookedLeft,
    ///                                      lookedRight: next.lookedRight,
    ///                                      frame: store.placementController?.arView.session.currentFrame)
    ///     }
    ///
    /// Without it the kit is still tagged, from camera poses alone. All three false (a redone meter or Start over)
    /// clears the moments; all three turning true at once (skipped or timed out) is recorded as `skipped`.
    func notePhotoKitLookAround(movedFarther: Bool, lookedLeft: Bool, lookedRight: Bool, frame: ARFrame?) {
        let previous = lastLookAround
        lastLookAround = (movedFarther, lookedLeft, lookedRight)
        if !movedFarther, !lookedLeft, !lookedRight {
            guard !photoKitMoments.isEmpty else { return }
            photoKitMoments = []
            revision += 1
            scheduleAutosave()
            return
        }
        guard let frame else { return }
        var kinds: [PhotoKitMoment.Kind] = []
        if movedFarther, !previous.movedFarther { kinds.append(.movedFarther) }
        if lookedLeft, !previous.lookedLeft { kinds.append(.lookedLeft) }
        if lookedRight, !previous.lookedRight { kinds.append(.lookedRight) }
        guard !kinds.isEmpty else { return }
        if kinds.count == 3 { kinds = [.skipped] }
        let position = frame.camera.transform.columns.3
        for kind in kinds {
            photoKitMoments.append(PhotoKitMoment(
                kind: kind,
                frameTimestamp: frame.timestamp,
                cameraPosition: PlacementAnchor(SIMD3(position.x, position.y, position.z))
            ))
        }
        revision += 1
        scheduleAutosave()
    }

    /// Base's nine photos in Base's order, for Review's photo list. Empty until the survey is first written
    /// (Review's own export on appear writes it).
    var photoKitShots: [PhotoKitShot] { session.photoKit?.orderedShots ?? [] }

    func setPropertyIdentifier(_ value: String) {
        session.propertyIdentifier = value
        refreshAssessment()
    }

    func setContactName(_ value: String) {
        session.contactName = value
        refreshAssessment()
    }

    func setEmail(_ value: String) {
        session.email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshAssessment()
    }

    func setPhone(_ value: String) {
        session.phone = value.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshAssessment()
    }

    func setHomeownership(_ value: Homeownership?) {
        session.homeownership = value
        refreshAssessment()
    }

    func setMeterNumber(_ value: String, source: MeterNumberSource = .manual, note: String? = nil) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        session.electrical.meterNumber = trimmed.isEmpty ? nil : trimmed
        session.electrical.meterNumberSource = trimmed.isEmpty ? nil : source
        meterNumberNote = note
        meterNumberFromScanCrop = false
        refreshAssessment()
    }

    /// `source` is `.manual` for anything the user typed or tapped. Only the scan's own read passes `.ocr`.
    /// Values outside the residential range (60–400 A) are dropped — a negative or four-digit read is either OCR noise
    /// or a typo, and shipping either downstream would break the Austin 150–200 A rule.
    func setMainBreakerAmperage(_ value: Int?, source: MeterNumberSource = .manual, note: String? = nil) {
        let bounded = value.flatMap { (60...400).contains($0) ? $0 : nil }
        // Which OCR rule read it stays only while the value is still that read (confirming it keeps the value).
        if bounded == nil || (source != .ocr && bounded != session.electrical.mainBreakerAmperage) {
            session.electrical.mainBreakerAmperageBasis = nil
        }
        session.electrical.mainBreakerAmperage = bounded
        session.electrical.mainBreakerAmperageSource = bounded == nil ? nil : source
        mainBreakerNote = note
        mainBreakerFromScan = false
        refreshAssessment()
    }

    func setPanelBusRatingAmps(_ value: Int?) {
        session.electrical.panelBusRatingAmps = value
        refreshAssessment()
    }

    func setHasSolar(_ value: Bool?) {
        session.electrical.hasSolar = value
        refreshAssessment()
    }

    /// "No" stands in for the Live Survey's gas step. A gas meter already marked on the scan still wins.
    func setGasMeterAnswer(_ value: GasMeterAnswer?) {
        session.electrical.gasMeterAnswer = value
        if value == .no, !session.placement.gasMeterMarked {
            session.placement.gasMeterNotPresent = true
            session.placement.gasStepOutcome = .answeredNo
            placementController?.clearGasMarker()
        } else if value != .no {
            session.placement.gasMeterNotPresent = false
            if session.placement.gasStepOutcome == .answeredNo { session.placement.gasStepOutcome = nil }
        }
        refreshAssessment()
    }

    func setHasPortableGenerator(_ value: Bool?) {
        session.electrical.hasPortableGenerator = value
        refreshAssessment()
    }

    func setHasStandbyGenerator(_ value: Bool?) {
        session.electrical.hasStandbyGenerator = value
        refreshAssessment()
    }

    func setHasExistingWholeHomeBattery(_ value: Bool?) {
        session.electrical.hasExistingWholeHomeBattery = value
        refreshAssessment()
    }

    /// The UI only offers 1 or 2 (see `BatteryCountChoice`). Anything outside 1...2 is dropped so the `solar-or-two-batteries`
    /// rule never sees a zero or a stray large value.
    func setPlannedBatteryCount(_ value: Int?) {
        session.electrical.plannedBatteryCount = value.flatMap { (1...2).contains($0) ? $0 : nil }
        refreshAssessment()
    }

    func attachMeterPhoto(_ image: UIImage) {
        meterImage = image
        meterPhotoIsScanCrop = false
        let jpeg = Self.uprightJPEG(image)
        session.electrical.meterPhotoFilename = write(jpeg, filename: "meter.jpg")
        refreshAssessment()
        guard let jpeg else { return }
        let currentNumber = session.electrical.meterNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard currentNumber.isEmpty else { return }
        meterReadGeneration += 1
        let generation = meterReadGeneration
        isReadingMeterNumber = true
        Task {
            let number = await recognizer.recognizeMeterNumber(in: jpeg)
            guard generation == meterReadGeneration else { return }
            isReadingMeterNumber = false
            let current = session.electrical.meterNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard current.isEmpty else { return }
            if let number {
                setMeterNumber(number, source: .ocr, note: "Read from the photo. Confirm it matches the meter.")
                meterNumberFromScanCrop = meterPhotoIsScanCrop
            } else {
                meterNumberNote = "Couldn't read a meter number from that photo. Type it, or scan the nameplate."
            }
        }
    }

    /// The scan's crop of the locked meter, as a fallback photo. Kept only when the survey has no meter photo:
    /// from where the meter locks the number is seldom legible, so the live number scan up close replaces it.
    func attachScanMeterPhotoIfMissing(_ image: UIImage) {
        guard meterImage == nil, session.electrical.meterPhotoFilename == nil else { return }
        attachMeterPhoto(image)
        meterPhotoIsScanCrop = true
    }

    /// "Not the meter", Redo meter, or Start over: a photo that was only that lock's crop goes with the lock, so the
    /// survey never keeps a picture of the wrong thing. A number OCR read from it goes too. Real photos stay.
    func dropScanMeterPhoto() {
        guard meterPhotoIsScanCrop else { return }
        meterPhotoIsScanCrop = false
        meterImage = nil
        if let name = session.electrical.meterPhotoFilename {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        session.electrical.meterPhotoFilename = nil
        // An OCR pass still reading the crop must not fill the number afterwards.
        meterReadGeneration += 1
        isReadingMeterNumber = false
        if meterNumberFromScanCrop {
            setMeterNumber("")
            return
        }
        // "Couldn't read a meter number from that photo" would point at a photo that is gone.
        if (session.electrical.meterNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meterNumberNote = nil
        }
        refreshAssessment()
    }

    /// The Live Survey's automatic capture. The photo is the sharp, well-lit crop the scan read; the value goes in
    /// as a scan read ("Read by scan — check it") the user confirms in Review. A value the user typed is never
    /// replaced, and neither is a photo the user took.
    func acceptScanCapture(_ capture: ScanCapture) {
        let jpeg = Self.uprightJPEG(capture.image)
        switch capture.kind {
        case .electricMeter:
            if meterImage == nil || meterPhotoIsScanCrop {
                // A scan photo replaces an older scan photo, so a stale OCR pass on that one must not land.
                meterReadGeneration += 1
                isReadingMeterNumber = false
                meterImage = capture.image
                meterPhotoIsScanCrop = true
                session.electrical.meterPhotoFilename = write(jpeg, filename: "meter.jpg")
            }
            if let number = capture.meterNumber, canTakeScanRead(session.electrical.meterNumberSource, hasValue: hasMeterNumber) {
                setMeterNumber(number, source: .ocr, note: Self.scanReadNote)
                // Tied to this capture even when the user's own photo was kept, so a redone meter drops it.
                meterNumberFromScanCrop = true
            }
        case .breakerPanel:
            panelImage = capture.image
            session.electrical.panelPhotoFilename = write(jpeg, filename: "panel.jpg")
            // A wider photo taken after the lock replaces the photo only.
            guard !capture.photoOnly else { break }
            let hasAmps = session.electrical.mainBreakerAmperage != nil
            if let amps = capture.mainBreakerAmps, canTakeScanRead(session.electrical.mainBreakerAmperageSource, hasValue: hasAmps) {
                setMainBreakerAmperage(amps, source: .ocr, note: Self.scanReadNote)
                session.electrical.mainBreakerAmperageBasis = capture.mainBreakerBasis
                mainBreakerFromScan = true
            } else if capture.mainBreakerAmps == nil, hasAmps, session.electrical.mainBreakerAmperageSource == .ocr {
                // This panel photo read no MAIN. An older, unconfirmed scan read (the 22:31 run kept a stab rating,
                // 125) does not stand beside it; Review asks.
                setMainBreakerAmperage(nil)
            }
        }
        refreshAssessment()
    }

    /// A redone or restarted scan lock: its photo goes, and a value only the scan read goes with it.
    func dropScanCapture(_ kind: EquipmentKind) {
        switch kind {
        case .electricMeter:
            dropScanMeterPhoto()
            // The user's own photo stays, but a number only this capture read does not.
            if meterNumberFromScanCrop, session.electrical.meterNumberSource == .ocr {
                setMeterNumber("")
            }
        case .breakerPanel:
            panelImage = nil
            if let name = session.electrical.panelPhotoFilename {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
            session.electrical.panelPhotoFilename = nil
            if mainBreakerFromScan, session.electrical.mainBreakerAmperageSource == .ocr {
                setMainBreakerAmperage(nil)
            }
            refreshAssessment()
        }
    }

    /// "Looks right" on a scan-read meter number: the user now vouches for it.
    func confirmScannedMeterNumber() {
        guard session.electrical.meterNumberSource == .ocr, let number = session.electrical.meterNumber else { return }
        setMeterNumber(number, source: .manual)
    }

    /// "Looks right" on a scan-read main breaker: the user now vouches for it, so the breaker rule can decide.
    func confirmScannedMainBreaker() {
        guard session.electrical.mainBreakerAmperageSource == .ocr, let amps = session.electrical.mainBreakerAmperage else { return }
        setMainBreakerAmperage(amps, source: .manual)
    }

    static let scanReadNote = "Read by scan — check it"

    private var hasMeterNumber: Bool {
        !(session.electrical.meterNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A scan read may fill an empty value or replace an earlier read. Never a value the user entered.
    private func canTakeScanRead(_ source: MeterNumberSource?, hasValue: Bool) -> Bool {
        !hasValue || source == .ocr
    }

    func measurements(for snapshot: PlacementSceneSnapshot) -> PlacementMeasurements {
        measurer.measure(snapshot)
    }

    func assessment(applying snapshot: PlacementSceneSnapshot) -> SurveyAssessment {
        var copy = session
        copy.placement = measurer.applying(snapshot, to: copy.placement)
        return evaluator.evaluate(copy)
    }

    func commitPlacement(_ snapshot: PlacementSceneSnapshot) {
        session.placement = measurer.applying(snapshot, to: session.placement)
        session.placement.snapshotTimestamp = Date()
        if session.placement.gasMeterMarked {
            session.placement.gasMeterNotPresent = false
            session.placement.gasStepOutcome = .shown
        }
        refreshAssessment()
    }

    /// How the Live Survey's gas step ended. A timeout never says there is no gas meter; the check stays unknown.
    func setGasStepOutcome(_ outcome: GasStepOutcome) {
        session.placement.gasStepOutcome = outcome
        refreshAssessment()
    }

    /// Review's "Not the gas meter": the shown mark and its photo go, the battery spot is chosen again without it,
    /// and the gas check goes back to unknown.
    func rejectGasMark() {
        removeGasPhoto()
        placementController?.clearGasMarker()
        if let live = placementController?.scene {
            commitPlacement(live)
        } else {
            session.placement.gasMeterMarked = false
            session.placement.gasMeterPosition = nil
            session.placement.distanceToGasMeterFeet = nil
        }
        session.placement.gasMeterMarkSource = nil
        session.placement.gasStepOutcome = .rejectedInReview
        refreshAssessment()
        // A battery placed at the finish is placed again without the mark, off the main thread: save it once it is.
        placementController?.afterBatteryFinalize { [weak self] _ in
            guard let self, let live = self.placementController?.scene else { return }
            self.commitPlacement(live)
        }
    }

    /// Saves the scan without sharing it: at the Live Survey's finish and when it is left. Writes survey.json, the
    /// capture manifest (so an unfinished run keeps `frames.json`), and scene.ply through the same guard as Share.
    /// Queued behind any export in flight and written off the main actor, like Share; nothing is zipped.
    /// Uses Nikita's point-cloud functions unchanged (`MeasurementOverlay`, `hasExportableMesh`, `finalize`); the overlay is
    /// built off the main actor (`pointCloudInputs`, then `pointCloudParts` in a detached task).
    func checkpointScan() {
        let previous = exportTask
        exportTask = Task { @MainActor in
            await previous?.value
            await runCheckpoint()
        }
    }

    /// The gas step's crop of the spot the user showed as the gas meter, kept as gas.jpg.
    func attachGasPhoto(_ image: UIImage) {
        gasImage = image
        session.electrical.gasMeterPhotoFilename = write(Self.uprightJPEG(image), filename: "gas.jpg")
        refreshAssessment()
    }

    private func removeGasPhoto() {
        gasImage = nil
        if let name = session.electrical.gasMeterPhotoFilename {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        session.electrical.gasMeterPhotoFilename = nil
    }

    func setFootprintClearAttested(_ value: Bool) {
        session.placement.footprintClearAttested = value ? true : nil
        refreshAssessment()
    }

    func setTransferSwitchSpaceAttested(_ value: Bool) {
        session.placement.transferSwitchSpaceAttested = value ? true : nil
        refreshAssessment()
    }

    /// "Start over" on the scan: the scan's evidence goes with it, so Review and the hub cannot show marks or a meter
    /// height the scene no longer has. The live scene is not committed until it has content again.
    /// Kept: whether the phone has LiDAR. The no-gas statement comes from the Home Info answer again: a gas mark that
    /// won over a "No" is gone now, so "No" must stand on its own or the gas check stays unknown with the step skipped.
    func resetPlacementEvidence() {
        let lidarMeshAvailable = session.placement.lidarMeshAvailable
        session.placement = PlacementEvidence()
        session.placement.gasMeterNotPresent = session.electrical.gasMeterAnswer == .no
        session.placement.gasStepOutcome = session.electrical.gasMeterAnswer == .no ? .answeredNo : nil
        session.placement.lidarMeshAvailable = lidarMeshAvailable
        // The kit's frames and milestones belonged to that scan.
        session.photoKit = nil
        photoKitMoments = []
        removeGasPhoto()
        refreshAssessment()
    }

    /// Writes the survey files, then shares them as one zipped folder so AirDrop sends a single item.
    /// The mesh, keyframes, and zip are written off the main actor; exports run one at a time, in call order.
    func exportForSharing() async {
        let previous = exportTask
        let task = Task { @MainActor in
            await previous?.value
            await runExport()
        }
        exportTask = task
        await task.value
    }

    private func runExport() async {
        // Review exports on every appearance. Nothing changed since the last zip (no answer, photo, commit, or
        // checkpoint): hand back the same zip instead of measuring the mesh again on the main thread.
        if exportedRevision == revision, lastExportError == nil, let archive = exportURLs.first,
           FileManager.default.fileExists(atPath: archive.path) {
            return
        }
        refreshAssessment()
        let exporting = revision
        isExporting = true
        defer { isExporting = false }
        // No mesh parts means "keep the saved scene.ply" (see `keepsSavedScene`).
        let inputs = keepsSavedScene() ? nil : placementController?.pointCloudInputs()
        let keyframes = placementController?.keyframes
        let snapshot = sessionForWriting()
        let directory = directory
        let exporter = exporter
        // The overlay's measuring runs here, off the main actor, not in `pointCloudInputs`.
        let parts = await Task.detached(priority: .userInitiated) { inputs.map(Self.pointCloudParts) }.value
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.writeExport(session: snapshot, mesh: parts, keyframes: keyframes, directory: directory, exporter: exporter)
            }.value
            applyWritten(result.session, surveyJSON: result.surveyJSON)
            exportURLs = [result.archive]
            lastExportError = nil
            exportedRevision = exporting
        } catch {
            exportURLs = []
            lastExportError = error.localizedDescription
            exportedRevision = nil
        }
    }

    /// `checkpointScan`'s write: the same files as Share, without the zip, and the share list is left alone.
    private func runCheckpoint() async {
        refreshAssessment()
        let inputs = keepsSavedScene() ? nil : placementController?.pointCloudInputs()
        let keyframes = placementController?.keyframes
        let snapshot = sessionForWriting()
        let directory = directory
        let exporter = exporter
        // The overlay's measuring runs here, off the main actor, not in `pointCloudInputs`.
        let parts = await Task.detached(priority: .userInitiated) { inputs.map(Self.pointCloudParts) }.value
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.writeSurveyFiles(session: snapshot, mesh: parts, keyframes: keyframes, directory: directory, exporter: exporter)
            }.value
            applyWritten(result.session, surveyJSON: result.surveyJSON)
            lastExportError = nil
        } catch {
            lastExportError = error.localizedDescription
        }
    }

    /// Only the export's own fields: anything the user changed meanwhile stays, and the next export writes it.
    private func applyWritten(_ written: SurveySession, surveyJSON: URL) {
        session.placement.pointCloudFilename = written.placement.pointCloudFilename
        session.placement.captureManifestPath = written.placement.captureManifestPath
        session.placement.capturedFrameCount = written.placement.capturedFrameCount
        session.photoKit = written.photoKit
        surveyJSONURL = surveyJSON
        // The export wrote survey.json from an older snapshot than a queued autosave may hold; write it once more
        // so the file on disk ends with every field, the export's included.
        scheduleAutosave()
    }

    /// `PlacementSceneController.pointCloudParts`, built off the main actor from `pointCloudInputs`: the same mesh
    /// and Nikita's `MeasurementOverlay`, unchanged. Its measuring was most of two checkpoint hangs on 27 Sep.
    private nonisolated static func pointCloudParts(
        _ inputs: (clouds: [MeshPointCloudChunk], snapshot: PlacementSceneSnapshot, measurer: CorePlacementMeasurer)
    ) -> (chunks: [MeshPointCloudChunk], comments: [String]) {
        let overlay = MeasurementOverlay.build(inputs.snapshot, measurer: inputs.measurer)
        return (inputs.clouds + [overlay.chunk], overlay.comments)
    }

    private struct ExportResult: Sendable {
        var session: SurveySession
        var surveyJSON: URL
        var archive: URL
    }

    private nonisolated static func writeExport(
        session: SurveySession,
        mesh: (chunks: [MeshPointCloudChunk], comments: [String])?,
        keyframes: KeyframeRecorder?,
        directory: URL,
        exporter: any SurveyExporting
    ) throws -> ExportResult {
        let written = try writeSurveyFiles(session: session, mesh: mesh, keyframes: keyframes, directory: directory, exporter: exporter)
        let session = written.session
        let archive = try packageSurvey(from: directory, including: [
            "survey.json",
            session.placement.pointCloudFilename,
            session.electrical.meterPhotoFilename,
            session.electrical.panelPhotoFilename,
            session.electrical.gasMeterPhotoFilename,
            session.placement.captureManifestPath == nil ? nil : "capture"
        ].compactMap { $0 })
        return ExportResult(session: session, surveyJSON: written.surveyJSON, archive: archive)
    }

    /// scene.ply, the capture manifest, and survey.json.
    private nonisolated static func writeSurveyFiles(
        session: SurveySession,
        mesh: (chunks: [MeshPointCloudChunk], comments: [String])?,
        keyframes: KeyframeRecorder?,
        directory: URL,
        exporter: any SurveyExporting
    ) throws -> (session: SurveySession, surveyJSON: URL) {
        var session = session
        let earlierManifest = session.placement.captureManifestPath
        let earlierFrameCount = session.placement.capturedFrameCount
        session.placement.pointCloudFilename = try writePointCloud(mesh, in: directory)
        let capture = try keyframes?.finalize()
        session.placement.captureManifestPath = capture == nil ? nil : "capture/frames.json"
        session.placement.capturedFrameCount = capture == nil ? nil : keyframes?.count
        if capture == nil, let earlierManifest,
           FileManager.default.fileExists(atPath: directory.appendingPathComponent(earlierManifest).path) {
            // A resumed survey before its scan runs again: this launch has no frames, and the earlier launch's
            // manifest still describes capture/.
            session.placement.captureManifestPath = earlierManifest
            session.placement.capturedFrameCount = earlierFrameCount
        }
        session.photoKit = PhotoKitTagger.tag(session, directory: directory)
        let surveyJSON = try exporter.write(session, to: directory)
        return (session, surveyJSON)
    }

    /// Copies the named survey files into a dated folder and zips it. Unzipping gives that one folder.
    private nonisolated static func packageSurvey(from directory: URL, including names: [String]) throws -> URL {
        let files = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "BaseSiteSurvey-\(formatter.string(from: Date()))"
        let staging = files.temporaryDirectory.appendingPathComponent("SurveyExport", isDirectory: true)
        try? files.removeItem(at: staging)
        let folder = staging.appendingPathComponent(name, isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in names {
            let source = directory.appendingPathComponent(item)
            guard files.fileExists(atPath: source.path) else { continue }
            // APFS clones the copy, so large capture folders cost almost nothing here.
            try files.copyItem(at: source, to: folder.appendingPathComponent(item))
        }

        let archive = staging.appendingPathComponent("\(name).zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipURL in
            do {
                try files.copyItem(at: zipURL, to: archive)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return archive
    }

    private func refreshAssessment() {
        updateGridContext()
        let assessment = evaluator.evaluate(session)
        session.ruleResults = assessment.results
        session.missingInformation = assessment.missingInformation
        session.placementTone = assessment.placementTone
        revision += 1
        scheduleAutosave()
    }

    // MARK: Autosave and resume

    /// What survey.json holds: the session plus the photo kit's inputs (milestones and the locks' wall normals).
    private func sessionForWriting() -> SurveySession {
        var copy = session
        var kit = copy.photoKit ?? PhotoKit()
        kit.moments = photoKitMoments
        if let scene = placementController?.scene {
            // A live lock brings its own normal. With none on the live scene (a relaunch, before the meter locks
            // again), the saved normal still belongs to the saved meter position.
            if scene.meterPosition != nil { kit.meterWallNormal = scene.meterWallNormal }
            if scene.panelPosition != nil { kit.panelWallNormal = scene.panelWallNormal }
        }
        copy.photoKit = kit
        return copy
    }

    private var resumeState: SurveyResumeState {
        SurveyResumeState(
            meterPhotoIsScanCrop: meterPhotoIsScanCrop,
            meterNumberFromScanCrop: meterNumberFromScanCrop,
            mainBreakerFromScan: mainBreakerFromScan,
            finishedAt: finishedAt
        )
    }

    /// Restarts the one-second wait. Every change goes through `refreshAssessment`, so this sees all of them.
    private func scheduleAutosave() {
        guard !isDiscarded else { return }
        autosaveTimer?.cancel()
        autosaveTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.autosaveNow()
        }
    }

    /// Writes survey.json and app-state.json now, off the main actor, when either changed since the last write.
    /// A survey with nothing in it is not written, so an untouched launch leaves an empty folder for cleanup.
    private func autosaveNow() {
        autosaveTimer?.cancel()
        autosaveTimer = nil
        guard !isDiscarded else { return }
        let snapshot = sessionForWriting()
        let state = resumeState
        guard snapshot.hasUserContent || state.finishedAt != nil else { return }
        if let lastAutosaved, lastAutosaved.session == snapshot, lastAutosaved.state == state { return }
        lastAutosaved = (snapshot, state)
        let previous = autosaveWrite
        let directory = directory
        let exporter = exporter
        autosaveWrite = Task.detached(priority: .utility) {
            await previous?.value
            // A folder Start over removed stays removed: the writes below fail instead of making it again.
            _ = try? exporter.write(snapshot, to: directory)
            try? SurveyLibrary.writeResumeState(state, in: directory)
        }
    }

    /// Leaving the app: a pending autosave is written now, with background time to finish it.
    private func flushAutosave() {
        guard autosaveTimer != nil else { return }
        autosaveNow()
        guard let write = autosaveWrite else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "Save survey")
        Task {
            await write.value
            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
        }
    }

    /// A resumed survey: the photos come back from its folder, and so does which values only the scan read.
    private func restore(_ state: SurveyResumeState) {
        meterPhotoIsScanCrop = state.meterPhotoIsScanCrop
        meterNumberFromScanCrop = state.meterNumberFromScanCrop
        mainBreakerFromScan = state.mainBreakerFromScan
        finishedAt = state.finishedAt
        meterImage = loadImage(session.electrical.meterPhotoFilename)
        panelImage = loadImage(session.electrical.panelPhotoFilename)
        gasImage = loadImage(session.electrical.gasMeterPhotoFilename)
        // A file that is gone is not listed as a photo.
        if meterImage == nil { session.electrical.meterPhotoFilename = nil; meterPhotoIsScanCrop = false }
        if panelImage == nil { session.electrical.panelPhotoFilename = nil }
        if gasImage == nil { session.electrical.gasMeterPhotoFilename = nil }
        if session.electrical.meterNumberSource == .ocr { meterNumberNote = Self.scanReadNote }
        if session.electrical.mainBreakerAmperageSource == .ocr { mainBreakerNote = Self.scanReadNote }
        photoKitMoments = session.photoKit?.moments ?? []
    }

    private func loadImage(_ filename: String?) -> UIImage? {
        guard let filename else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(filename).path)
    }

    /// Snapshot the ERCOT context that matches the current battery/panel/address answers.
    /// Never writes ruleResults or placementTone — those stay owned by evaluator.evaluate().
    private func updateGridContext() {
        let decision = BatteryCountDecision.make(
            plannedCount: session.electrical.plannedBatteryCount,
            hasSolar: session.electrical.hasSolar,
            panelBusRatingAmps: session.electrical.panelBusRatingAmps,
            propertyIdentifier: session.propertyIdentifier
        )
        session.gridContext = decision.capturedGridContext
    }

    /// True when an existing scene.ply must be kept, not overwritten: the live session has no mesh right now (a
    /// session that was restarted, or relaunched) or its battery is more than 5 cm from the one survey.json records.
    /// The 22:31 run's Share wrote an overlay-only scene.ply whose battery was 5 m from survey.json's.
    private func keepsSavedScene() -> Bool {
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("scene.ply").path),
              let controller = placementController else { return false }
        return !controller.hasExportableMesh
            || !Self.sameBattery(controller.scene.batteryPosition, session.placement.batteryPosition)
    }

    /// Latest LiDAR mesh as `scene.ply`. With no mesh parts (no live scan this launch, or `keepsSavedScene`) the
    /// saved file is kept as it is; parts that make no PLY (no vertices at all) remove a stale file.
    /// Nikita's point-cloud format is unchanged (`PointCloudPLY.data`).
    private nonisolated static func writePointCloud(
        _ mesh: (chunks: [MeshPointCloudChunk], comments: [String])?,
        in directory: URL
    ) throws -> String? {
        let name = "scene.ply"
        let url = directory.appendingPathComponent(name)
        let exists = FileManager.default.fileExists(atPath: url.path)
        guard let mesh else { return exists ? name : nil }
        guard let data = PointCloudPLY.data(from: mesh.chunks, comments: mesh.comments) else {
            if exists {
                try FileManager.default.removeItem(at: url)
            }
            return nil
        }
        try data.write(to: url, options: .atomic)
        return name
    }

    /// Both nil, or within 5 cm.
    private static func sameBattery(_ live: PlacementAnchor?, _ saved: PlacementAnchor?) -> Bool {
        switch (live, saved) {
        case (nil, nil): return true
        case let (live?, saved?): return simd_distance(live.simd, saved.simd) <= 0.05
        default: return false
        }
    }

    private func write(_ data: Data?, filename: String) -> String? {
        guard let data else { return nil }
        let url = directory.appendingPathComponent(filename)
        revision += 1
        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            lastExportError = error.localizedDescription
            return nil
        }
    }

    /// Camera photos carry EXIF orientation; bake it in so the saved file and OCR see the same pixels.
    private static func uprightJPEG(_ image: UIImage) -> Data? {
        upright(image).jpegData(compressionQuality: 0.8)
    }

    private static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func makeDirectory(id: UUID) throws -> URL {
        let url = try SurveyLibrary.root().appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// What a resumed survey needs beyond survey.json: which values only the scan read (so a redone lock still drops
/// them), and whether Share finished it. Written beside survey.json as app-state.json; never shared.
struct SurveyResumeState: Codable, Sendable, Equatable {
    var meterPhotoIsScanCrop = false
    var meterNumberFromScanCrop = false
    var mainBreakerFromScan = false
    var finishedAt: Date?
}

/// Documents/Surveys: which survey a launch resumes, and launch cleanup.
@MainActor
enum SurveyLibrary {
    /// Surveys kept on the phone, newest first, the resumed one included.
    nonisolated static let keepCount = 10
    nonisolated static let stateFilename = "app-state.json"
    /// A folder Start over removed, renamed so it is gone at once and deleted in the background.
    nonisolated static let discardedMarker = ".discarded-"

    struct Resumable: Sendable {
        var directory: URL
        var session: SurveySession
        var state: SurveyResumeState
    }

    private static var pending: Resumable?
    private static var prepared = false

    /// True between launch and the first survey: the Welcome screen's button continues a survey.
    static var hasPendingResume: Bool { pending != nil }

    /// Once per launch, before the first `SurveyStore`: picks the newest unfinished survey to resume, then deletes
    /// empty folders and all but the `keepCount` newest surveys off the main thread. The resumed one is never deleted.
    static func prepareForLaunch() {
        guard !prepared else { return }
        prepared = true
        guard let root = try? root() else { return }
        let plan = plan(in: root)
        pending = plan.resume
        guard !plan.delete.isEmpty else { return }
        let doomed = plan.delete
        DispatchQueue.global(qos: .utility).async {
            for url in doomed { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// The first store after launch takes it; later stores (Start over) start fresh.
    static func takePendingResume() -> Resumable? {
        defer { pending = nil }
        return pending
    }

    /// Renames the folder out of the way now and deletes it on a background queue.
    static func removeInBackground(_ directory: URL) {
        let files = FileManager.default
        let tombstone = directory.deletingLastPathComponent()
            .appendingPathComponent(directory.lastPathComponent + discardedMarker + UUID().uuidString, isDirectory: true)
        let target = (try? files.moveItem(at: directory, to: tombstone)) == nil ? directory : tombstone
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: target)
        }
    }

    nonisolated static func root() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Surveys", isDirectory: true)
    }

    nonisolated static func writeResumeState(_ state: SurveyResumeState, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent(stateFilename), options: .atomic)
    }

    nonisolated static func readResumeState(in directory: URL) -> SurveyResumeState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(stateFilename)),
              let state = try? decoder.decode(SurveyResumeState.self, from: data) else { return SurveyResumeState() }
        return state
    }

    /// survey.json as `JSONSurveyExporter` writes it (ISO 8601 dates). Nil when missing or from an unreadable schema.
    nonisolated static func readSession(in directory: URL) -> SurveySession? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("survey.json")) else { return nil }
        return try? decoder.decode(SurveySession.self, from: data)
    }

    /// Newest first by survey.json's last write. A folder with no survey.json never got an answer or a lock (autosave
    /// writes one on the first), so it is empty and goes, as do Start over's leftovers and a survey.json with nothing in it.
    nonisolated static func plan(in root: URL) -> (resume: Resumable?, delete: [URL]) {
        let files = FileManager.default
        guard let entries = try? files.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return (nil, []) }
        var delete: [URL] = []
        var surveys: [(url: URL, date: Date)] = []
        for url in entries {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if url.lastPathComponent.contains(discardedMarker) {
                delete.append(url)
                continue
            }
            let json = url.appendingPathComponent("survey.json")
            guard let date = try? json.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                delete.append(url)
                continue
            }
            surveys.append((url, date))
        }
        surveys.sort { $0.date > $1.date }

        var resume: Resumable?
        var blank: Set<URL> = []
        for survey in surveys {
            let state = readResumeState(in: survey.url)
            guard state.finishedAt == nil, let session = readSession(in: survey.url) else { continue }
            guard session.hasUserContent else {
                blank.insert(survey.url)
                continue
            }
            resume = Resumable(directory: survey.url, session: session, state: state)
            break
        }

        var slots = keepCount - (resume == nil ? 0 : 1)
        for survey in surveys where survey.url != resume?.directory {
            if blank.contains(survey.url) || slots <= 0 {
                delete.append(survey.url)
            } else {
                slots -= 1
            }
        }
        return (resume, delete)
    }
}

/// Picks, for each of Base's nine photos, the saved photo or scan keyframe that best matches it. Runs off the main
/// actor when survey.json is written. Uses only survey.json's fields and capture/frames.json (read, never changed).
enum PhotoKitTagger {
    /// Base asks for "at least 10 steps" back. About 2 ft a step; tune on device.
    static let stepsBackFeet = 20.0
    /// Nearer than this, a frame is the equipment close-up, not the area around it.
    static let areaMinimumFeet = 6.0
    /// The panel's surroundings: closer than the close-up is useless, farther than this is plenty.
    static let panelAreaFeet = 6.0
    static let panelAreaMinimumFeet = 3.0
    /// Where "right of the meter" and "left of the meter" are aimed: this far along the wall, facing it.
    static let sideOffsetMeters: Float = 1.5
    /// A frame within this of a look-around milestone counts as taken for it.
    static let momentWindowSeconds: TimeInterval = 2
    /// Extra score, in feet, for a frame taken at the milestone that belongs to the shot: it wins near-ties only,
    /// since farther back is what Base asks for.
    static let momentBonusFeet = 2.0
    /// Only the middle of the view counts as "in view", so the subject is not cut off at an edge.
    static let viewConeFraction: Float = 0.8
    private static let feetPerMeter = 3.28084

    private struct Manifest: Decodable {
        struct Frame: Decodable {
            var index: Int
            var timestamp: TimeInterval
            var image: String
            var imageWidth: Int
            var imageHeight: Int
            var cameraToWorld: [Float]
            var intrinsics: [Float]
        }

        var frames: [Frame]
    }

    private struct Camera {
        var index: Int
        var timestamp: TimeInterval
        var image: String
        var position: SIMD3<Float>
        var forward: SIMD3<Float>
        var halfFieldOfView: Float
    }

    private struct Pick {
        var camera: Camera
        var feet: Double
        var moment: PhotoKitMoment.Kind?
    }

    static func tag(_ session: SurveySession, directory: URL) -> PhotoKit {
        var kit = session.photoKit ?? PhotoKit()
        let cameras = loadCameras(session, directory: directory)
        kit.framesConsidered = cameras.count
        let placement = session.placement
        let meter = placement.meterPosition?.simd
        let panel = placement.panelPosition?.simd
        let meterOut = meter.flatMap { outward(kit.meterWallNormal, origin: $0, cameras: cameras) }
        let moments = kit.moments

        var shots: [String: PhotoKitShot] = [:]
        func put(_ shot: PhotoKitShot) { shots[BaseShot(rawValue: shot.number)!.key] = shot }

        // 1. The meter photo, with its number.
        let electrical = session.electrical
        let hasNumber = !(electrical.meterNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let photo = electrical.meterPhotoFilename {
            put(entry(.meter, hasNumber ? .covered : .partial, image: photo, source: "photo",
                      note: hasNumber ? "meter.jpg, with the meter number read." : "meter.jpg. The meter number is not read yet, so check it is legible."))
        } else {
            put(entry(.meter, .missing, note: "No meter photo yet."))
        }

        // 2. The meter from far back.
        if let meter {
            let pick = best(cameras, seeing: meter, moments: moments, preferring: [.movedFarther]) { _ in true }
            put(distanceShot(.meterArea, pick, covered: stepsBackFeet, partial: areaMinimumFeet,
                             missingNote: "No saved frame shows the meter from \(Int(areaMinimumFeet)) ft or more back."))
        } else {
            put(entry(.meterArea, .missing, note: "The meter was not located on the scan."))
        }

        // 3 and 4. The wall stretch right and left of the meter, as someone facing the meter sees it.
        for (shot, sign) in [(BaseShot.meterRight, Float(1)), (BaseShot.meterLeft, Float(-1))] {
            guard let meter, let meterOut else {
                put(entry(shot, .missing, note: meter == nil ? "The meter was not located on the scan." : "Not enough views of the meter to tell its left from its right."))
                continue
            }
            let right = simd_cross(-meterOut, SIMD3<Float>(0, 1, 0))
            let target = meter + right * sign * sideOffsetMeters
            // Standing out from the wall, so the photo shows the ground in front of it, where a battery would go,
            // and aimed at that side: the side is nearer the middle of the view than the meter is. A wide shot
            // centered on the meter is #2, not this.
            let pick = best(cameras, seeing: target, moments: moments, preferring: []) { camera in
                simd_dot(camera.position - meter, meterOut) >= 0.5
                    && simd_dot(camera.forward, simd_normalize(target - camera.position))
                    > simd_dot(camera.forward, simd_normalize(meter - camera.position))
            }
            put(distanceShot(shot, pick, covered: stepsBackFeet, partial: areaMinimumFeet,
                             missingNote: "No saved frame shows the wall \(shot == .meterRight ? "right" : "left") of the meter from \(Int(areaMinimumFeet)) ft or more away."))
        }

        // 5. The wall next to the meter wall: a frame looking along the meter wall, out in front of it.
        if let meter, let meterOut {
            let alongWall = cameras.compactMap { camera -> (camera: Camera, score: Double, moment: PhotoKitMoment.Kind?)? in
                guard let forward = flat(camera.forward),
                      simd_dot(camera.position - meter, meterOut) >= 0.5,
                      horizontalFeet(camera.position, meter) >= 5 else { return nil }
                let parallel = 1 - abs(Double(simd_dot(forward, meterOut)))
                guard parallel >= 0.43 else { return nil } // at least 55° off facing the wall
                let moment = moment(near: camera.timestamp, in: moments, kinds: [.lookedLeft, .lookedRight])
                return (camera, parallel + (moment == nil ? 0 : 1), moment)
            }.max { $0.score < $1.score }
            if let alongWall {
                var shot = entry(.adjacentWall, .partial, camera: alongWall.camera,
                                 feet: horizontalFeet(alongWall.camera.position, meter), moment: alongWall.moment,
                                 note: "Looks along the meter wall toward a corner. The scan cannot confirm the next wall is in it: check it shows that whole wall, corner to corner.")
                shot.distanceFeet = nil
                put(shot)
            } else {
                put(entry(.adjacentWall, .missing, note: "No saved frame looks along the meter wall toward a corner. Base asks for the whole wall next to the meter wall."))
            }
        } else {
            put(entry(.adjacentWall, .missing, note: "The meter wall was not located on the scan."))
        }

        // 6. Behind the fence: the app cannot know about a fence.
        put(entry(.behindFence, .notTagged, note: "The app does not tag this. If there is a fence on that side, Base asks for the full side behind it."))

        // 7 and 8. The panel photo, and whether it shows the main disconnect's rating.
        if let photo = electrical.panelPhotoFilename {
            put(entry(.panel, .covered, image: photo, source: "photo", note: "panel.jpg"))
            switch electrical.mainBreakerAmperageBasis {
            case .mainRow?, .mainNeighbor?:
                put(entry(.mainDisconnect, .covered, image: photo, source: "photo", note: "panel.jpg, where the scan read the rating beside MAIN."))
            default:
                put(entry(.mainDisconnect, .partial, image: photo, source: "photo", note: "Check that panel.jpg shows the main disconnect's amperage. If it sits in a small box by the meter, Base asks for the lid lifted."))
            }
        } else {
            put(entry(.panel, .missing, note: "No panel photo yet."))
            put(entry(.mainDisconnect, .missing, note: "No photo of the main disconnect's amperage yet."))
        }

        // 9. The panel's surroundings.
        if let panel {
            let pick = best(cameras, seeing: panel, moments: moments, preferring: []) { _ in true }
            put(distanceShot(.panelArea, pick, covered: panelAreaFeet, partial: panelAreaMinimumFeet,
                             missingNote: "No saved frame shows the panel from \(Int(panelAreaMinimumFeet)) ft or more back."))
        } else {
            put(entry(.panelArea, .missing, note: "The panel was not located on the scan."))
        }

        kit.shots = shots
        return kit
    }

    // MARK: Frames

    private static func loadCameras(_ session: SurveySession, directory: URL) -> [Camera] {
        guard let manifestPath = session.placement.captureManifestPath,
              let data = try? Data(contentsOf: directory.appendingPathComponent(manifestPath)),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        let folder = (manifestPath as NSString).deletingLastPathComponent
        return manifest.frames.compactMap { frame in
            let m = frame.cameraToWorld
            let k = frame.intrinsics
            guard m.count == 16, k.count == 9, k[0] > 0, k[4] > 0 else { return nil }
            // Column-major camera-to-world; the camera looks down -Z.
            let forward = -SIMD3<Float>(m[8], m[9], m[10])
            let length = simd_length(forward)
            guard length > 1e-4 else { return nil }
            let halfWidth = atan(Float(frame.imageWidth) / 2 / k[0])
            let halfHeight = atan(Float(frame.imageHeight) / 2 / k[4])
            return Camera(
                index: frame.index,
                timestamp: frame.timestamp,
                image: folder.isEmpty ? frame.image : "\(folder)/\(frame.image)",
                position: SIMD3(m[12], m[13], m[14]),
                forward: forward / length,
                halfFieldOfView: min(halfWidth, halfHeight)
            )
        }
    }

    private static func sees(_ camera: Camera, _ point: SIMD3<Float>) -> Bool {
        let offset = point - camera.position
        let distance = simd_length(offset)
        guard distance > 0.3 else { return false }
        return simd_dot(camera.forward, offset / distance) >= cos(camera.halfFieldOfView * viewConeFraction)
    }

    /// The farthest frame that has the point in view; a frame taken at one of `preferring`'s milestones wins ties
    /// up to `momentBonusFeet`.
    private static func best(
        _ cameras: [Camera],
        seeing point: SIMD3<Float>,
        moments: [PhotoKitMoment],
        preferring kinds: [PhotoKitMoment.Kind],
        where accept: (Camera) -> Bool
    ) -> Pick? {
        cameras.compactMap { camera -> (pick: Pick, score: Double)? in
            guard sees(camera, point), accept(camera) else { return nil }
            let feet = horizontalFeet(camera.position, point)
            let moment = kinds.isEmpty ? nil : moment(near: camera.timestamp, in: moments, kinds: kinds)
            return (Pick(camera: camera, feet: feet, moment: moment), feet + (moment == nil ? 0 : momentBonusFeet))
        }.max { $0.score < $1.score }?.pick
    }

    private static func moment(near timestamp: TimeInterval, in moments: [PhotoKitMoment], kinds: [PhotoKitMoment.Kind]) -> PhotoKitMoment.Kind? {
        moments.first { kinds.contains($0.kind) && abs($0.frameTimestamp - timestamp) <= momentWindowSeconds }?.kind
    }

    /// The meter wall's outward direction, level. The lock's normal gives the line; the cameras that saw the meter
    /// stood in front of the wall, so they give the side. With no normal, their mean direction is the estimate.
    private static func outward(_ stored: PlacementAnchor?, origin: SIMD3<Float>, cameras: [Camera]) -> SIMD3<Float>? {
        var mean = SIMD3<Float>(repeating: 0)
        for camera in cameras where sees(camera, origin) {
            if let direction = flat(camera.position - origin) { mean += direction }
        }
        if let stored, let normal = flat(stored.simd) {
            return simd_dot(normal, mean) < 0 ? -normal : normal
        }
        return flat(mean)
    }

    private static func flat(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let level = SIMD3<Float>(vector.x, 0, vector.z)
        let length = simd_length(level)
        return length > 1e-4 ? level / length : nil
    }

    private static func horizontalFeet(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Double {
        Double(simd_length(SIMD2<Float>(a.x - b.x, a.z - b.z))) * feetPerMeter
    }

    // MARK: Entries

    private static func distanceShot(_ shot: BaseShot, _ pick: Pick?, covered: Double, partial: Double, missingNote: String) -> PhotoKitShot {
        guard let pick, pick.feet >= partial else { return entry(shot, .missing, note: missingNote) }
        let feet = Int(pick.feet.rounded())
        if pick.feet >= covered {
            return entry(shot, .covered, camera: pick.camera, feet: pick.feet, moment: pick.moment, note: "From about \(feet) ft back.")
        }
        return entry(shot, .partial, camera: pick.camera, feet: pick.feet, moment: pick.moment,
                     note: "From about \(feet) ft back. Base asks for about \(Int(covered)) ft\(covered >= stepsBackFeet ? " (10 steps)" : "").")
    }

    private static func entry(
        _ shot: BaseShot,
        _ status: PhotoKitShotStatus,
        camera: Camera,
        feet: Double,
        moment: PhotoKitMoment.Kind?,
        note: String
    ) -> PhotoKitShot {
        PhotoKitShot(
            number: shot.rawValue,
            title: shot.title,
            status: status,
            image: camera.image,
            keyframeIndex: camera.index,
            keyframeTimestamp: camera.timestamp,
            distanceFeet: (feet * 10).rounded() / 10,
            source: moment.map { "pose+lookAround.\($0.rawValue)" } ?? "pose",
            note: note
        )
    }

    private static func entry(_ shot: BaseShot, _ status: PhotoKitShotStatus, image: String? = nil, source: String? = nil, note: String) -> PhotoKitShot {
        PhotoKitShot(number: shot.rawValue, title: shot.title, status: status, image: image, source: source, note: note)
    }
}
