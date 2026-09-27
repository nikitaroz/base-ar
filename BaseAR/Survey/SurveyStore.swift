import UIKit

/// Holds one survey and the three workstream implementations.
/// Electrical, placement, and rules can be swapped from `init` without changing the screens.
@MainActor
@Observable
final class SurveyStore {
    private(set) var session: SurveySession
    var meterImage: UIImage?
    var placementImage: UIImage?
    private(set) var exportURLs: [URL] = []
    private(set) var lastExportError: String?
    /// Shown under the meter field after a scan or a failed read. Cleared when the user edits the number.
    private(set) var meterNumberNote: String?
    private(set) var isReadingMeterNumber = false
    /// True while the meter photo is only the AR scan's crop of the locked meter. Any other photo replaces it,
    /// and a redone meter lock drops it.
    private(set) var meterPhotoIsScanCrop = false
    /// True while the meter number is what OCR read from that crop, so dropping the crop drops the number too.
    private var meterNumberFromScanCrop = false
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
        meterNumberFromScanCrop = false
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

    /// "No" stands in for the Live Survey's gas step. A gas meter already marked on the scan still wins.
    func setGasMeterAnswer(_ value: GasMeterAnswer?) {
        session.electrical.gasMeterAnswer = value
        if value == .no, !session.placement.gasMeterMarked {
            session.placement.gasMeterNotPresent = true
            placementController?.clearGasMarker()
        } else if value != .no {
            session.placement.gasMeterNotPresent = false
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

    func setPlannedBatteryCount(_ value: Int?) {
        session.electrical.plannedBatteryCount = value
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

    func exportForSharing() {
        refreshAssessment()
        do {
            session.placement.pointCloudFilename = try writePointCloud()
            let jsonURL = try exporter.write(session, to: directory)
            var urls = [jsonURL]
            if let name = session.placement.pointCloudFilename {
                urls.append(directory.appendingPathComponent(name))
            }
            for name in [
                session.electrical.meterPhotoFilename,
                session.placement.screenshotFilename
            ] {
                guard let name else { continue }
                let url = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    urls.append(url)
                }
            }
            exportURLs = urls
            lastExportError = nil
        } catch {
            exportURLs = []
            lastExportError = error.localizedDescription
        }
    }

    private func refreshAssessment() {
        let assessment = evaluator.evaluate(session)
        session.ruleResults = assessment.results
        session.missingInformation = assessment.missingInformation
        session.placementTone = assessment.placementTone
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
