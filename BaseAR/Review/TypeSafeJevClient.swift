import Foundation

/// Optional TypeSafe Jev readiness advisory for the Review screen.
///
/// Advisory only: it never changes a rule outcome, the placement tone, or the survey file.
/// With no `TYPESAFE_API_KEY` the client is unavailable and makes no network call.
/// The key comes from the environment (Xcode scheme) or the Info.plist build setting
/// `$(TYPESAFE_API_KEY)`, which `Config/Local.xcconfig` sets. Never commit a key.
struct TypeSafeJevClient: Sendable {
    static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    static let model = "jev-latest"

    private let apiKey: String?

    init(apiKey: String? = TypeSafeJevClient.configuredKey()) {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // An unexpanded "$(TYPESAFE_API_KEY)" means the build setting was never defined.
        self.apiKey = trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }

    var isAvailable: Bool { apiKey != nil }

    static func configuredKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !env.isEmpty {
            return env
        }
        return Bundle.main.object(forInfoDictionaryKey: "TYPESAFE_API_KEY") as? String
    }

    /// Never throws. Offline, auth, HTTP, decode and timeout failures all come back as `.unavailable`.
    func advisory(for session: SurveySession) async -> JevAdvisory {
        guard let apiKey else {
            return JevAdvisory(status: .unavailable, reason: "No advisory key is set.")
        }
        do {
            let answers = try await fetchAnswers(session: session, apiKey: apiKey)
            return JevAdvisory(status: .available, answers: answers)
        } catch is CancellationError {
            return JevAdvisory(status: .unavailable, reason: "The request was cancelled.")
        } catch let error as URLError where error.code == .timedOut {
            return JevAdvisory(status: .unavailable, reason: "The advisory service timed out.")
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            return JevAdvisory(status: .unavailable, reason: "No internet connection.")
        } catch let error as JevError {
            return JevAdvisory(status: .unavailable, reason: error.message)
        } catch is DecodingError {
            return JevAdvisory(status: .unavailable, reason: "The advisory reply could not be read.")
        } catch {
            return JevAdvisory(status: .unavailable, reason: "The advisory service could not be reached.")
        }
    }

    private static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private func fetchAnswers(session: SurveySession, apiKey: String) async throws -> [String: JevAnswer] {
        let body = JevRequest(
            model: Self.model,
            state: JevSurveyState(session: session),
            questions: JevRequest.standardQuestions
        )
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await Self.urlSession.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw JevError.badResponse }
        guard (200...299).contains(http.statusCode) else { throw JevError.http(http.statusCode) }
        return try JSONDecoder().decode(JevResponse.self, from: data).answers
    }
}

enum JevError: Error {
    case badResponse
    case http(Int)

    var message: String {
        switch self {
        case .badResponse: "The advisory service sent no usable reply."
        case .http(401), .http(403): "The advisory key was not accepted (HTTP 401/403)."
        case .http(429): "The advisory service is busy (HTTP 429). Try again later."
        case .http(let code): "The advisory service answered HTTP \(code)."
        }
    }
}

// MARK: - Request

struct JevRequest: Encodable, Sendable {
    let model: String
    let state: JevSurveyState
    let questions: [String: JevQuestion]

    static let standardQuestions: [String: JevQuestion] = [
        "visit_ready": JevQuestion(
            type: "noul",
            instructions: "Is this preliminary survey complete enough for a Base engineer to review? Count only measured checks as measured. Typed answers are the homeowner's statements, and scanned numbers are suggestions the homeowner confirms."
        ),
        "next_action": JevQuestion(
            type: "choice",
            instructions: "What should the homeowner do next?",
            criteria: .labeled([
                "proceed": "enough evidence to send for engineer review",
                "need_more_photos": "more photos or scanning needed",
                "conflict": "a measured conflict needs a different spot or an engineer"
            ])
        ),
        "blocking_gap": JevQuestion(
            type: "choice",
            instructions: "Which missing or failing evidence is the highest-priority blocker?",
            criteria: .labeled([
                "footprint": "3 ft x 3 ft pad clearance unmeasured or failing",
                "transfer_switch": "transfer-switch space beside the meter unmeasured or failing",
                "ocr": "meter number or main breaker size missing or unconfirmed",
                "photos": "meter photo or scan screenshot missing",
                "form": "home information incomplete",
                "distances": "AR distances incomplete",
                "none": "no blocking gap"
            ])
        ),
        "readiness_score": JevQuestion(
            type: "score",
            instructions: "How ready is this survey for engineer review?",
            criteria: .ordered([
                "not started / mostly empty",
                "partial capture, major gaps",
                "usable draft, a few gaps",
                "ready for engineer review"
            ])
        )
    ]
}

struct JevQuestion: Encodable, Sendable {
    enum Criteria: Sendable {
        case labeled([String: String])
        case ordered([String])
    }

    let type: String
    let instructions: String
    var criteria: Criteria? = nil

    enum CodingKeys: String, CodingKey {
        case type, instructions, criteria
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(instructions, forKey: .instructions)
        switch criteria {
        case .labeled(let labels): try container.encode(labels, forKey: .criteria)
        case .ordered(let levels): try container.encode(levels, forKey: .criteria)
        case nil: break
        }
    }
}

// MARK: - Response

struct JevResponse: Decodable, Sendable {
    let answers: [String: JevAnswer]
}

struct JevAnswer: Decodable, Sendable {
    let noul: String?
    let choice: String?
    let score: Int?
    let confidence: Double?
    let probabilities: [String: Double]?
    let distribution: [Int]?
}

struct JevAdvisory: Sendable {
    enum Status: Sendable {
        case available
        case unavailable
    }

    let status: Status
    var reason: String? = nil
    var answers: [String: JevAnswer]? = nil

    var visitReady: String? { answers?["visit_ready"]?.noul }
    var nextAction: String? { answers?["next_action"]?.choice }
    var blockingGap: String? { answers?["blocking_gap"]?.choice }
    var readinessScore: Int? { answers?["readiness_score"]?.score }
}

// MARK: - Survey summary sent to Jev

/// What leaves the phone: evidence flags, check results, and home answers.
/// No name, email, phone, address, GPS fix, meter number, or photo is sent.
/// The rules' own requirement text stands in for a policy catalog, so nothing here hardcodes Base numbers.
struct JevSurveyState: Encodable, Sendable {
    let evidenceNotes: String
    let placementTone: String
    let missingInformation: [String]
    let photos: JevPhotoFlags
    let placement: JevPlacementSummary
    let rules: [JevRuleSummary]
    let form: JevFormSummary

    init(session: SurveySession) {
        let electrical = session.electrical
        let placement = session.placement

        evidenceNotes = "Prototype preliminary survey, never installation approval. Typed answers and 'no gas meter' are the homeowner's statements, not measurements. Numbers read by scan are suggestions the homeowner confirms. The panel bus rating is never inferred from the main breaker."
        placementTone = session.placementTone.rawValue
        missingInformation = session.missingInformation

        photos = JevPhotoFlags(
            meterPhoto: electrical.meterPhotoFilename != nil,
            scanScreenshot: placement.screenshotFilename != nil,
            sceneMesh: placement.pointCloudFilename != nil
        )

        self.placement = JevPlacementSummary(
            batteryPlaced: placement.batteryPlaced,
            meterMarked: placement.meterMarked,
            panelMarked: placement.panelMarked,
            gasMarked: placement.gasMeterMarked,
            gasMeterNotPresentStated: placement.gasMeterNotPresent,
            lidarAvailable: placement.lidarMeshAvailable,
            meterLockSource: placement.meterLockSource?.rawValue,
            panelLockSource: placement.panelLockSource?.rawValue,
            meterFeet: placement.distanceToMeterFeet,
            wallFeet: placement.distanceToWallFeet,
            gasFeet: placement.distanceToGasMeterFeet,
            meterHeightFeet: placement.meterHeightFeet,
            meterAndPanelSameWall: placement.meterAndPanelSameWall,
            footprintIsClear: placement.footprintIsClear,
            clearOfWindows: placement.clearOfWindows,
            keepsEquipmentAccess: placement.keepsEquipmentAccess,
            transferSwitchSpaceMeasured: placement.transferSwitchClearanceObserved,
            frontWorkingSpaceIsClear: placement.frontWorkingSpaceIsClear,
            footprintClearAttested: placement.footprintClearAttested,
            transferSwitchSpaceAttested: placement.transferSwitchSpaceAttested
        )

        rules = session.ruleResults.map { result in
            JevRuleSummary(
                id: result.id,
                title: result.title,
                requirement: result.requirement,
                status: result.status.rawValue,
                usedMeasuredEvidence: result.usedMeasuredEvidence,
                isRequired: result.isRequired
            )
        }

        form = JevFormSummary(
            homeownership: session.homeownership?.rawValue,
            hasSolar: electrical.hasSolar,
            hasPortableGenerator: electrical.hasPortableGenerator,
            hasStandbyGenerator: electrical.hasStandbyGenerator,
            hasExistingWholeHomeBattery: electrical.hasExistingWholeHomeBattery,
            plannedBatteryCount: electrical.plannedBatteryCount,
            gasMeterAnswer: electrical.gasMeterAnswer?.rawValue,
            mainBreakerAmps: electrical.mainBreakerAmperage,
            panelBusRatingAmps: electrical.panelBusRatingAmps,
            meterNumberPresent: !(electrical.meterNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            meterNumberSource: electrical.meterNumberSource?.rawValue
        )
    }
}

struct JevPhotoFlags: Encodable, Sendable {
    let meterPhoto: Bool
    let scanScreenshot: Bool
    let sceneMesh: Bool
}

struct JevPlacementSummary: Encodable, Sendable {
    let batteryPlaced: Bool
    let meterMarked: Bool
    let panelMarked: Bool
    let gasMarked: Bool
    let gasMeterNotPresentStated: Bool
    let lidarAvailable: Bool
    let meterLockSource: String?
    let panelLockSource: String?
    let meterFeet: Double?
    let wallFeet: Double?
    let gasFeet: Double?
    let meterHeightFeet: Double?
    let meterAndPanelSameWall: Bool?
    let footprintIsClear: Bool?
    let clearOfWindows: Bool?
    let keepsEquipmentAccess: Bool?
    let transferSwitchSpaceMeasured: Bool?
    let frontWorkingSpaceIsClear: Bool?
    let footprintClearAttested: Bool?
    let transferSwitchSpaceAttested: Bool?
}

struct JevRuleSummary: Encodable, Sendable {
    let id: String
    let title: String
    let requirement: String
    let status: String
    let usedMeasuredEvidence: Bool
    let isRequired: Bool
}

struct JevFormSummary: Encodable, Sendable {
    let homeownership: String?
    let hasSolar: Bool?
    let hasPortableGenerator: Bool?
    let hasStandbyGenerator: Bool?
    let hasExistingWholeHomeBattery: Bool?
    let plannedBatteryCount: Int?
    let gasMeterAnswer: String?
    let mainBreakerAmps: Int?
    let panelBusRatingAmps: Int?
    let meterNumberPresent: Bool
    let meterNumberSource: String?
}
