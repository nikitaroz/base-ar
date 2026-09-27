import UIKit

/// Holds one survey and the three workstream implementations.
/// Electrical, placement, and rules can be swapped from `init` without changing the screens.
@MainActor
@Observable
final class SurveyStore {
    private(set) var session: SurveySession
    var meterImage: UIImage?
    var placementImage: UIImage?
    /// The one zipped survey folder handed to the share sheet.
    private(set) var exportURLs: [URL] = []
    /// Local survey.json from the last export, for the review preview.
    private(set) var surveyJSONURL: URL?
    private(set) var lastExportError: String?
    /// Shown under the meter field after a scan or a failed read. Cleared when the user edits the number.
    private(set) var meterNumberNote: String?
    private(set) var isReadingMeterNumber = false
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
        created.keyframes.setDirectory(directory.appendingPathComponent("capture", isDirectory: true))
        placementController = created
        return created
    }

    /// Drops the in-memory AR session and the on-disk survey packet.
    func discardSavedSurvey() {
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
        session.email = value
        refreshAssessment()
    }

    func setPhone(_ value: String) {
        session.phone = value
        refreshAssessment()
    }

    func setHomeownership(_ value: Homeownership?) {
        session.homeownership = value
        refreshAssessment()
    }

    func setMeterNumber(_ value: String, source: MeterNumberSource = .manual, note: String? = nil) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        session.electrical.meterNumber = value
        session.electrical.meterNumberSource = trimmed.isEmpty ? nil : source
        meterNumberNote = note
        refreshAssessment()
    }

    func setMainBreakerAmperage(_ value: Int?) {
        session.electrical.mainBreakerAmperage = value
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

    func setPlannedBatteryCount(_ value: Int?) {
        session.electrical.plannedBatteryCount = value
        refreshAssessment()
    }

    func attachMeterPhoto(_ image: UIImage) {
        meterImage = image
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
            } else {
                meterNumberNote = "Couldn't read a meter number from that photo. Type it, or scan the nameplate."
            }
        }
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
        }
        refreshAssessment()
    }

    func setFootprintClearAttested(_ value: Bool) {
        session.placement.footprintClearAttested = value ? true : nil
        refreshAssessment()
    }

    func setTransferSwitchSpaceAttested(_ value: Bool) {
        session.placement.transferSwitchSpaceAttested = value ? true : nil
        refreshAssessment()
    }

    /// "Start over" on the scan: the scan's evidence goes with it, so Review and the hub cannot show marks, a meter
    /// height, or a photo the scene no longer has. The live scene is not committed until it has content again.
    /// Kept: the homeowner's no-gas answer (the scan screen decides that one) and whether the phone has LiDAR.
    func resetPlacementEvidence() {
        let gasMeterNotPresent = session.placement.gasMeterNotPresent
        let lidarMeshAvailable = session.placement.lidarMeshAvailable
        session.placement = PlacementEvidence()
        session.placement.gasMeterNotPresent = gasMeterNotPresent
        session.placement.lidarMeshAvailable = lidarMeshAvailable
        placementImage = nil
        let photo = directory.appendingPathComponent("placement.jpg")
        if FileManager.default.fileExists(atPath: photo.path) {
            try? FileManager.default.removeItem(at: photo)
        }
        refreshAssessment()
    }

    func attachPlacementScreenshot(_ image: UIImage) {
        placementImage = image
        session.placement.screenshotFilename = write(Self.uprightJPEG(image), filename: "placement.jpg")
        refreshAssessment()
    }

    /// Writes the survey files, then shares them as one zipped folder so AirDrop sends a single item.
    func exportForSharing() {
        refreshAssessment()
        do {
            session.placement.pointCloudFilename = try writePointCloud()
            let capture = try placementController?.keyframes.finalize()
            session.placement.captureManifestPath = capture == nil ? nil : "capture/frames.json"
            session.placement.capturedFrameCount = capture == nil ? nil : placementController?.keyframes.count
            surveyJSONURL = try exporter.write(session, to: directory)
            exportURLs = [try packageSurvey(including: [
                "survey.json",
                session.placement.pointCloudFilename,
                session.electrical.meterPhotoFilename,
                session.placement.screenshotFilename,
                capture == nil ? nil : "capture"
            ].compactMap { $0 })]
            lastExportError = nil
        } catch {
            exportURLs = []
            lastExportError = error.localizedDescription
        }
    }

    /// Copies the named survey files into a dated folder and zips it. Unzipping gives that one folder.
    private func packageSurvey(including names: [String]) throws -> URL {
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

    /// Latest LiDAR mesh as `scene.ply`. Removes a stale file when the scan has no mesh.
    private func writePointCloud() throws -> String? {
        let name = "scene.ply"
        let url = directory.appendingPathComponent(name)
        guard let data = placementController?.pointCloudPLYData() else {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return nil
        }
        try data.write(to: url, options: .atomic)
        return name
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
