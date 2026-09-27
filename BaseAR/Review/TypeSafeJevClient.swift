import Foundation

/// Optional TypeSafe Jev advisory for the Review screen ("Review set v2").
///
/// Advisory only: it never changes a rule outcome, the placement tone, or the survey file.
/// With no `TYPESAFE_API_KEY` the client is unavailable and makes no network call.
/// The key comes from the environment (Xcode scheme) or the Info.plist build setting
/// `$(TYPESAFE_API_KEY)`, which `Config/Local.xcconfig` sets. Never commit a key.
///
/// v2 (26 Sep 2026): shares `JevTransport` with the Live Survey coach (one warm connection), pins `jev-1.13.0`,
/// uses the Review budget (5 s idle, 15 s total, one retry on 408 / 429 / 529 / 5xx honouring Retry-After up to
/// 3 s), decodes `model` and `usage`, sends rule statuses without the requirement sentences or raw distances, and
/// no longer asks Jev whether the survey is ready: the Review readiness card computes that from the checks.
struct TypeSafeJevClient: Sendable {
    static let endpoint = JevTransport.endpoint
    static let model = JevTransport.pinnedModel

    private let transport: JevTransport

    init(apiKey: String? = TypeSafeJevClient.configuredKey()) {
        transport = JevTransport(apiKey: apiKey)
    }

    init(transport: JevTransport) {
        self.transport = transport
    }

    var isAvailable: Bool { transport.isAvailable }

    static func configuredKey() -> String? {
        JevTransport.configuredKey()
    }

    /// Never throws. Offline, auth, HTTP, decode and timeout failures all come back as `.unavailable`.
    func advisory(for session: SurveySession) async -> JevAdvisory {
        guard isAvailable else {
            return JevAdvisory(status: .unavailable, reason: "No advisory key is set.")
        }
        let body: Data
        do {
            body = try Self.requestBody(for: session)
        } catch {
            return JevAdvisory(status: .unavailable, reason: "The advisory request could not be built.")
        }
        switch await transport.post(body, profile: .review) {
        case .success(let reply):
            return JevAdvisory(
                status: .available,
                answers: reply.answers,
                model: reply.model,
                usage: reply.usage,
                requestID: reply.requestID,
                roundTrip: reply.roundTrip
            )
        case .failure(let failure):
            return JevAdvisory(status: .unavailable, reason: Self.reason(for: failure))
        }
    }

    /// The exact request bytes, sorted keys. The state keeps its camelCase keys, as before.
    static func requestBody(for session: SurveySession) throws -> Data {
        try JevTransport.encodeBody(
            JevRequest(model: model, state: JevSurveyState(session: session), questions: JevRequest.standardQuestions),
            snakeCaseKeys: false
        )
    }

    static func reason(for failure: JevCallFailure) -> String {
        switch failure {
        case .noKey: return "No advisory key is set."
        case .cancelled: return "The request was cancelled."
        case .timedOut: return "The advisory service timed out."
        case .offline, .connectionLost: return "No internet connection."
        case .constrained: return "Low Data Mode is on."
        case .undecodable: return "The advisory reply could not be read."
        case .connection: return "The advisory service could not be reached."
        case .http(let status, _, _, _):
            switch status {
            case 401, 403: return "The advisory key was not accepted (HTTP 401/403)."
            case 422: return "The advisory request was not accepted (HTTP 422)."
            case 429: return "The advisory service is busy (HTTP 429). Try again later."
            case 529: return "The advisory service is overloaded (HTTP 529). Try again later."
            default: return "The advisory service answered HTTP \(status)."
            }
        }
    }
}

// MARK: - Request

struct JevRequest: Encodable, Sendable {
    let model: String
    let state: JevSurveyState
    let questions: [String: JevQuestion]

    /// Review set v2. `visit_ready` is gone: readiness is computed in code (the Review readiness card), and a Jev
    /// yes/no beside it could only contradict the checks.
    static let standardQuestions: [String: JevQuestion] = [
        "next_action": JevQuestion(
            type: "choice",
            instructions: "What should the homeowner do next?",
            criteria: .labeled([
                "proceed": "enough evidence to send for engineer review",
                "need_more_photos": "more photos or scanning needed",
                "conflict": "a measured conflict needs a different spot or an engineer",
                "other": "none of the above fits"
            ])
        ),
        "blocking_gap": JevQuestion(
            type: "choice",
            instructions: "Which missing or failing evidence is the highest-priority blocker?",
            criteria: .labeled([
                "footprint": "3 ft x 3 ft pad clearance unmeasured or failing",
                "transfer_switch": "transfer-switch space beside the meter unmeasured or failing",
                "ocr": "meter number or main breaker size missing or unconfirmed",
                "photos": "meter photo or scan missing",
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

// MARK: - Advisory

struct JevAdvisory: Sendable {
    enum Status: Sendable {
        case available
        case unavailable
    }

    let status: Status
    var reason: String? = nil
    var answers: [String: JevAnswer]? = nil
    /// The versioned model that answered, e.g. "jev-1.13.0".
    var model: String? = nil
    var usage: JevUsage? = nil
    var requestID: String? = nil
    var roundTrip: Duration? = nil

    var nextAction: String? { answers?["next_action"]?.choice }
    var blockingGap: String? { answers?["blocking_gap"]?.choice }
    /// 0 (not started) to 3 (visit-ready), fractional.
    var readinessScore: Double? { answers?["readiness_score"]?.score }
}

// MARK: - Survey summary sent to Jev

/// What leaves the phone: evidence flags, check statuses, and home answers.
/// No name, email, phone, address, GPS fix, meter number, photo, raw distance, or rule sentence is sent.
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
            meterDistanceMeasured: placement.distanceToMeterFeet != nil,
            wallDistanceMeasured: placement.distanceToWallFeet != nil,
            gasDistanceMeasured: placement.distanceToGasMeterFeet != nil,
            meterHeightMeasured: placement.meterHeightFeet != nil,
            meterAndPanelSameWall: placement.meterAndPanelShareWall,
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
    /// Whether each AR distance exists. The distances themselves stay on the phone; the rule statuses carry them.
    let meterDistanceMeasured: Bool
    let wallDistanceMeasured: Bool
    let gasDistanceMeasured: Bool
    let meterHeightMeasured: Bool
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
