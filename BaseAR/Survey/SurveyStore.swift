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
    private let measurer: any PlacementMeasuring
    private let evaluator: any SurveyEvaluating
    private let exporter: any SurveyExporting
    private let recognizer: any MeterNumberRecognizing
    private let locationProvider = PropertyLocationProvider()
    private var meterReadGeneration = 0

    init(
        propertyIdentifier: String,
        measurer: any PlacementMeasuring = CorePlacementMeasurer(),
        evaluator: any SurveyEvaluating = BaseSurveyEvaluator(),
        exporter: any SurveyExporting = JSONSurveyExporter(),
        recognizer: any MeterNumberRecognizing = VisionElectricalRecognizer()
    ) throws {
        let session = SurveySession.new(propertyIdentifier: propertyIdentifier)
        self.session = session
        self.measurer = measurer
        self.evaluator = evaluator
        self.exporter = exporter
        self.recognizer = recognizer
        directory = try Self.makeDirectory(id: session.id)
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
        refreshAssessment()
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
        return created
    }

    /// Drops the in-memory AR session and the on-disk survey packet.
    func discardSavedSurvey() {
        #if DEBUG
        FrameRecorder.shared.end(summary: ["discarded": true])
        #endif
        placementController?.stop()
        placementController = nil
        try? FileManager.default.removeItem(at: directory)
    }

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
    /// Uses Nikita's point-cloud functions unchanged (`pointCloudParts`, `hasExportableMesh`, `finalize`).
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
        refreshAssessment()
        isExporting = true
        defer { isExporting = false }
        // No mesh parts means "keep the saved scene.ply" (see `keepsSavedScene`).
        let parts = keepsSavedScene() ? nil : placementController?.pointCloudParts()
        let keyframes = placementController?.keyframes
        let snapshot = session
        let directory = directory
        let exporter = exporter
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.writeExport(session: snapshot, mesh: parts, keyframes: keyframes, directory: directory, exporter: exporter)
            }.value
            applyWritten(result.session, surveyJSON: result.surveyJSON)
            exportURLs = [result.archive]
            lastExportError = nil
        } catch {
            exportURLs = []
            lastExportError = error.localizedDescription
        }
    }

    /// `checkpointScan`'s write: the same files as Share, without the zip, and the share list is left alone.
    private func runCheckpoint() async {
        refreshAssessment()
        let parts = keepsSavedScene() ? nil : placementController?.pointCloudParts()
        let keyframes = placementController?.keyframes
        let snapshot = session
        let directory = directory
        let exporter = exporter
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
        surveyJSONURL = surveyJSON
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
        session.placement.pointCloudFilename = try writePointCloud(mesh, in: directory)
        let capture = try keyframes?.finalize()
        session.placement.captureManifestPath = capture == nil ? nil : "capture/frames.json"
        session.placement.capturedFrameCount = capture == nil ? nil : keyframes?.count
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
        let root = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = root
            .appendingPathComponent("Surveys", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
