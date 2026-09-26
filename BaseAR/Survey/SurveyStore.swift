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
    /// Shown when the property fix failed or location access is off. Nil while waiting or after a fix.
    private(set) var locationStatusMessage: String?
    /// Lives for the whole survey so leaving placement does not drop the AR session or its marks.
    private(set) var placementController: PlacementSceneController?

    let directory: URL
    private let measurer: any PlacementMeasuring
    private let evaluator: any SurveyEvaluating
    private let exporter: any SurveyExporting
    private let recognizer: any MeterNumberRecognizing
    private let locationProvider = PropertyLocationProvider()

    init(
        propertyIdentifier: String,
        measurer: any PlacementMeasuring = CorePlacementMeasurer(),
        evaluator: any SurveyEvaluating = BaseSurveyEvaluator(),
        exporter: any SurveyExporting = JSONSurveyExporter(),
        recognizer: any MeterNumberRecognizing = UnimplementedMeterNumberRecognizer()
    ) throws {
        let session = SurveySession.new(propertyIdentifier: propertyIdentifier)
        self.session = session
        self.measurer = measurer
        self.evaluator = evaluator
        self.exporter = exporter
        self.recognizer = recognizer
        directory = try Self.makeDirectory(id: session.id)
        locationProvider.onFix = { [weak self] fix in
            self?.locationStatusMessage = nil
            self?.session.propertyLocation = fix
            self?.refreshAssessment()
        }
        locationProvider.onStatus = { [weak self] message in
            guard let self, self.session.propertyLocation == nil else { return }
            self.locationStatusMessage = message
        }
        locationProvider.request()
        refreshAssessment()
    }

    func retryPropertyLocation() {
        locationProvider.retry()
    }

    func requirePlacementController() -> PlacementSceneController {
        if let placementController { return placementController }
        let created = PlacementSceneController()
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

    func setMeterNumber(_ value: String) {
        session.electrical.meterNumber = value
        refreshAssessment()
    }

    func setMainBreakerAmperage(_ value: Int?) {
        session.electrical.mainBreakerAmperage = value
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
        Task {
            guard let number = await recognizer.recognizeMeterNumber(in: jpeg) else { return }
            let current = session.electrical.meterNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if current.isEmpty {
                setMeterNumber(number)
            }
        }
    }

    func attachBreakerPhoto(_ image: UIImage) {
        breakerImage = image
        session.electrical.breakerPhotoFilename = write(Self.uprightJPEG(image), filename: "breaker.jpg")
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
