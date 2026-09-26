import UIKit

/// Holds one survey and the three workstream implementations.
/// Electrical, placement, and rules can be swapped from `init` without changing the screens.
@MainActor
@Observable
final class SurveyStore {
    private(set) var session: SurveySession
    var meterImage: UIImage?
    var breakerImage: UIImage?
    var placementImage: UIImage?
    private(set) var exportURLs: [URL] = []
    private(set) var lastExportError: String?
    private(set) var draftSaveError: String?
    private static let activeDraftKey = "BaseSiteSurvey.activeDraft"
    static var hasSavedDraft: Bool { UserDefaults.standard.string(forKey: activeDraftKey) != nil }
    /// Shown under the meter field after a scan or a failed read. Cleared when the user edits the number.
    private(set) var meterNumberNote: String?
    /// Shown under the amperage field after a scan or a failed read. Cleared when the user edits the rating.
    private(set) var breakerAmperageNote: String?
    private(set) var isReadingMeterNumber = false
    private(set) var isReadingBreakerAmperage = false
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
    private var breakerReadGeneration = 0

    init(
        propertyIdentifier: String,
        resumeDraft: Bool = false,
        measurer: any PlacementMeasuring = CorePlacementMeasurer(),
        evaluator: any SurveyEvaluating = BaseSurveyEvaluator(),
        exporter: any SurveyExporting = JSONSurveyExporter(),
        recognizer: any MeterNumberRecognizing = VisionElectricalRecognizer()
    ) throws {
        var session = SurveySession.new(propertyIdentifier: propertyIdentifier)
        if resumeDraft, let savedID = UserDefaults.standard.string(forKey: Self.activeDraftKey),
           let id = UUID(uuidString: savedID) {
            let folder = try Self.makeDirectory(id: id)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            // Fail visibly rather than silently overwriting a damaged draft.
            session = try decoder.decode(SurveySession.self, from: Data(contentsOf: folder.appendingPathComponent("survey.json")))
        }
        session.schemaVersion = 5
        if session.guidedProgress == nil { session.guidedProgress = GuidedSurveyProgress() }
        self.session = session
        self.measurer = measurer
        self.evaluator = evaluator
        self.exporter = exporter
        self.recognizer = recognizer
        directory = try Self.makeDirectory(id: session.id)
        meterImage = session.electrical.meterPhotoFilename.flatMap { UIImage(contentsOfFile: directory.appendingPathComponent($0).path) }
        breakerImage = session.electrical.breakerPhotoFilename.flatMap { UIImage(contentsOfFile: directory.appendingPathComponent($0).path) }
        placementImage = session.placement.screenshotFilename.flatMap { UIImage(contentsOfFile: directory.appendingPathComponent($0).path) }
        // Missing files must not restore as accepted evidence.
        if meterImage == nil {
            self.session.electrical.meterPhotoFilename = nil
            self.session.guidedProgress?.meterConfirmed = false
        }
        if breakerImage == nil {
            self.session.electrical.breakerPhotoFilename = nil
            self.session.guidedProgress?.breakerConfirmed = false
        }
        if placementImage == nil { self.session.placement.screenshotFilename = nil }
        for (key, evidence) in self.session.guidedProgress?.contextPhotos ?? [:] {
            if !FileManager.default.fileExists(atPath: directory.appendingPathComponent(evidence.filename).path) {
                self.session.guidedProgress?.contextPhotos.removeValue(forKey: key)
            }
        }
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
        created.setActiveModel(BatteryCatalog.model(for: session.selectedBatteryModelId))
        placementController = created
        return created
    }

    func setSelectedBatteryModel(_ modelId: String) {
        guard modelId != session.selectedBatteryModelId else { return }
        session.selectedBatteryModelId = modelId
        placementController?.setActiveModel(BatteryCatalog.model(for: modelId))
        refreshAssessment()
    }

    /// Drops the in-memory AR session and the on-disk survey packet.
    func discardSavedSurvey() {
        placementController?.stop()
        placementController = nil
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removeObject(forKey: Self.activeDraftKey)
    }

    func setPropertyIdentifier(_ value: String) {
        if value != session.propertyIdentifier, !session.propertyIdentifier.isEmpty {
            // An address correction can change utility/rule scope. Keep photos as drafts,
            // but require reconfirmation; never carry accepted siting evidence to a new address.
            session.propertyLocation = nil
            session.guidedProgress?.programAnswered = false
            session.guidedProgress?.meterConfirmed = false
            session.guidedProgress?.breakerConfirmed = false
            for key in Array((session.guidedProgress?.contextPhotos ?? [:]).keys) {
                session.guidedProgress?.contextPhotos[key]?.accepted = false
            }
            session.placement = PlacementEvidence()
            placementImage = nil
            placementController?.stop()
            placementController = nil
        }
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
        meterReadGeneration += 1
        isReadingMeterNumber = false
        session.guidedProgress?.meterConfirmed = false
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        session.electrical.meterNumber = value
        session.electrical.meterNumberSource = trimmed.isEmpty ? nil : source
        meterNumberNote = note
        refreshAssessment()
    }

    func setMainBreakerAmperage(_ value: Int?, note: String? = nil) {
        breakerReadGeneration += 1
        isReadingBreakerAmperage = false
        session.guidedProgress?.breakerConfirmed = false
        session.electrical.mainBreakerAmperage = value
        breakerAmperageNote = note
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
        meterReadGeneration += 1
        isReadingMeterNumber = false
        session.guidedProgress?.meterConfirmed = false
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

    func attachBreakerPhoto(_ image: UIImage) {
        breakerReadGeneration += 1
        isReadingBreakerAmperage = false
        session.guidedProgress?.breakerConfirmed = false
        breakerImage = image
        let jpeg = Self.uprightJPEG(image)
        session.electrical.breakerPhotoFilename = write(jpeg, filename: "breaker.jpg")
        refreshAssessment()
        guard let jpeg else { return }
        guard session.electrical.mainBreakerAmperage == nil else { return }
        breakerReadGeneration += 1
        let generation = breakerReadGeneration
        isReadingBreakerAmperage = true
        Task {
            let amps = await recognizer.recognizeMainBreakerAmperage(in: jpeg)
            guard generation == breakerReadGeneration else { return }
            isReadingBreakerAmperage = false
            guard session.electrical.mainBreakerAmperage == nil else { return }
            if let amps {
                setMainBreakerAmperage(amps, note: "Read from the photo. Confirm it matches the main breaker.")
            } else {
                breakerAmperageNote = "Couldn't read a breaker rating from that photo. Type it, or scan the handle."
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

    func attachPlacementScreenshot(_ image: UIImage) {
        placementImage = image
        session.placement.screenshotFilename = write(Self.uprightJPEG(image), filename: "placement.jpg")
        refreshAssessment()
    }

    func exportForSharing() {
        refreshAssessment()
        do {
            let jsonURL = try exporter.write(session, to: directory)
            var urls = [jsonURL]
            for name in [
                session.electrical.meterPhotoFilename,
                session.electrical.breakerPhotoFilename,
                session.placement.screenshotFilename
            ] {
                guard let name else { continue }
                let url = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    urls.append(url)
                }
            }
            for evidence in (session.guidedProgress?.contextPhotos ?? [:]).sorted(by: { $0.key < $1.key }) {
                let url = directory.appendingPathComponent(evidence.value.filename)
                if FileManager.default.fileExists(atPath: url.path) { urls.append(url) }
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
        do {
            _ = try exporter.write(session, to: directory)
            UserDefaults.standard.set(session.id.uuidString, forKey: Self.activeDraftKey)
            draftSaveError = nil
        } catch {
            draftSaveError = error.localizedDescription
        }
    }

    func updateGuided(_ change: (inout GuidedSurveyProgress) -> Void) {
        var progress = session.guidedProgress ?? GuidedSurveyProgress()
        change(&progress)
        session.guidedProgress = progress
        refreshAssessment()
    }

    func setGuidedStep(_ step: SurveyStep) {
        updateGuided { $0.currentStep = step }
    }

    func deferStep(_ step: SurveyStep, reason: String?) {
        updateGuided { $0.deferred[step.rawValue] = reason?.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func confirmElectrical(_ slot: PhotoSlot, confirmed: Bool) {
        updateGuided {
            switch slot {
            case .meter:
                $0.meterConfirmed = confirmed &&
                    !(session.electrical.meterNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    session.electrical.meterPhotoFilename != nil
            case .breaker:
                $0.breakerConfirmed = confirmed && (session.electrical.mainBreakerAmperage ?? 0) > 0 &&
                    session.electrical.breakerPhotoFilename != nil
            }
        }
    }

    func attachContextPhoto(_ image: UIImage, slot: ContextPhoto) {
        guard let filename = write(Self.uprightJPEG(image), filename: "context-\(slot.rawValue).jpg") else { return }
        updateGuided { $0.contextPhotos[slot.rawValue] = ContextEvidence(filename: filename, capturedAt: Date()) }
    }

    func contextImage(_ slot: ContextPhoto) -> UIImage? {
        guard let filename = session.guidedProgress?.contextPhotos[slot.rawValue]?.filename else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(filename).path)
    }

    func acceptContextPhoto(_ slot: ContextPhoto, accepted: Bool) {
        updateGuided { $0.contextPhotos[slot.rawValue]?.accepted = accepted }
    }

    private func write(_ data: Data?, filename: String) -> String? {
        guard let data else {
            lastExportError = "The image could not be encoded. Retake it or leave this step for review."
            return nil
        }
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            lastExportError = nil
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
