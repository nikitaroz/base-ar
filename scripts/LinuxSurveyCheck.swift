import Foundation

/// Linux stand-in for the on-phone survey loop: fill a session, run `BaseSurveyEvaluator`,
/// and write `survey.json` with `JSONSurveyExporter`. UIKit and ARKit stay on the phone.
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError("FAIL: \(message)")
    }
}

func makeSession() -> SurveySession {
    SurveySession(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        createdAt: Date(timeIntervalSince1970: 1_758_931_200),
        propertyIdentifier: "",
        contactName: "",
        email: "",
        phone: "",
        homeownership: nil,
        propertyLocationDisclaimer: SurveySession.locationDisclaimer,
        prototypeDisclaimer: SurveySession.prototypeDisclaimer,
        propertyLocation: nil,
        electrical: ElectricalEvidence(),
        placement: PlacementEvidence(),
        ruleResults: [],
        missingInformation: [],
        placementTone: .incomplete,
        units: SurveyUnits(),
        appVersion: "linux-check",
        buildNumber: "0",
        iosVersion: "n/a",
        deviceModel: "Linux"
    )
}

func refresh(_ session: inout SurveySession) {
    let assessment = BaseSurveyEvaluator().evaluate(session)
    session.ruleResults = assessment.results
    session.missingInformation = assessment.missingInformation
    session.placementTone = assessment.placementTone
}

func result(_ session: SurveySession, id: String) -> RuleResult {
    guard let found = session.ruleResults.first(where: { $0.id == id }) else {
        fatalError("FAIL: missing rule \(id)")
    }
    return found
}

func export(_ session: SurveySession, to directory: URL, name: String) throws {
    let exporter = JSONSurveyExporter()
    let written = try exporter.write(session, to: directory)
    let destination = directory.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: written, to: destination)
}

@main
struct LinuxSurveyCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: linux-survey-check <output-directory>")
        }

        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try run(output: output)
    }
}

private func run(output: URL) throws {

var empty = makeSession()
refresh(&empty)
expect(empty.placementTone == .incomplete, "empty survey tone was \(empty.placementTone.rawValue)")
expect(result(empty, id: "austin-main-breaker").status == .unknown, "empty breaker check should stay unknown")
expect(empty.missingInformation.contains("Name"), "empty survey should still ask for a name")
expect(empty.missingInformation.contains("Confirmed main breaker amperage"), "empty survey should still ask for amperage")
try export(empty, to: output, name: "incomplete-survey.json")

var conflict = makeSession()
conflict.electrical.mainBreakerAmperage = 100
refresh(&conflict)
expect(conflict.placementTone == .conflict, "100A survey tone was \(conflict.placementTone.rawValue)")
expect(result(conflict, id: "austin-main-breaker").status == .conflict, "100A should conflict with the Austin range")
try export(conflict, to: output, name: "conflict-survey.json")

var clear = makeSession()
clear.propertyIdentifier = "100 Congress Ave, Austin"
clear.contactName = "Ada Lovelace"
clear.email = "ada@example.com"
clear.phone = "5125550100"
clear.homeownership = .own
clear.propertyLocation = GeoFix(
    latitude: 30.2672,
    longitude: -97.7431,
    timestamp: Date(timeIntervalSince1970: 1_758_931_200),
    horizontalAccuracyMeters: 8
)
clear.electrical.meterPhotoFilename = "meter.jpg"
clear.electrical.breakerPhotoFilename = "breaker.jpg"
clear.electrical.meterNumber = "12345678"
clear.electrical.meterNumberSource = .manual
clear.electrical.mainBreakerAmperage = 200
clear.electrical.hasSolar = false
clear.electrical.hasPortableGenerator = false
clear.electrical.hasStandbyGenerator = false
clear.electrical.hasExistingWholeHomeBattery = false
clear.electrical.plannedBatteryCount = 1
clear.placement.screenshotFilename = "placement.jpg"
clear.placement.batteryPlaced = true
clear.placement.meterMarked = true
clear.placement.gasMeterMarked = true
clear.placement.panelMarked = true
clear.placement.distanceToMeterFeet = 12
clear.placement.distanceToWallFeet = 0.5
clear.placement.distanceToGasMeterFeet = 8
clear.placement.footprintIsClear = true
clear.placement.transferSwitchClearanceObserved = true
clear.placement.meterHeightFeet = 5
clear.placement.frontWorkingSpaceIsClear = true
clear.placement.meterAndPanelSameWall = true
clear.placement.meterAndPanelShareWall = true
refresh(&clear)
expect(clear.placementTone == .clear, "fully measured survey tone was \(clear.placementTone.rawValue): \(clear.ruleResults.map { "\($0.id)=\($0.status.rawValue)" }.joined(separator: ", "))")
expect(clear.missingInformation.isEmpty, "fully measured survey still missing \(clear.missingInformation)")
expect(clear.ruleResults.allSatisfy { $0.status == .pass && $0.usedMeasuredEvidence }, "clear tone requires every check to pass on measured evidence")
try export(clear, to: output, name: "clear-survey.json")

var partial = clear
partial.placement.footprintIsClear = nil
partial.placement.footprintClearAttested = nil
refresh(&partial)
expect(partial.placementTone == .incomplete, "dropping the footprint measurement should stay incomplete, got \(partial.placementTone.rawValue)")

    print("linux-survey-check: incomplete=\(empty.placementTone.rawValue) conflict=\(conflict.placementTone.rawValue) clear=\(clear.placementTone.rawValue)")
    print("wrote \(output.path)")
}
