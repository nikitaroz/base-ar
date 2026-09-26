import Foundation

/// TypeSafe Jev system-one realtime advisory for Base Site Survey.
/// Only advisory — never overrides measured green/amber/red from EligibilityRule.
actor TypeSafeJevClient {
    private let apiKey: String?
    private let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    private let model = "jev-latest"
    
    init() {
        // Load from environment or Info.plist; never hardcode
        if let env = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !env.isEmpty {
            self.apiKey = env
        } else if let plist = Bundle.main.object(forInfoDictionaryKey: "TYPESAFE_API_KEY") as? String, !plist.isEmpty {
            self.apiKey = plist
        } else {
            self.apiKey = nil
        }
    }
    
    var isAvailable: Bool {
        apiKey != nil
    }
    
    /// Fetch advisory. Gracefully degrades: offline/auth/timeout → advisoryUnavailable.
    func advisory(for session: SurveySession) async -> JevAdvisory {
        guard let apiKey else {
            return JevAdvisory(status: .unavailable, reason: "TYPESAFE_API_KEY not configured")
        }
        
        let state = CompactSurveyState(session: session)
        let request = JevRequest(model: model, state: state, questions: JevRequest.standardQuestions)
        
        do {
            let encoded = try JSONEncoder().encode(request)
            var urlRequest = URLRequest(url: endpoint, timeoutInterval: 15)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = encoded
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let http = response as? HTTPURLResponse else {
                return JevAdvisory(status: .unavailable, reason: "Invalid response")
            }
            
            guard (200...299).contains(http.statusCode) else {
                let reason = "HTTP \(http.statusCode)"
                return JevAdvisory(status: .unavailable, reason: reason)
            }
            
            let decoded = try JSONDecoder().decode(JevResponse.self, from: data)
            return JevAdvisory(status: .available, answers: decoded.answers)
            
        } catch is CancellationError {
            return JevAdvisory(status: .unavailable, reason: "Request cancelled")
        } catch {
            return JevAdvisory(status: .unavailable, reason: error.localizedDescription)
        }
    }
}

// MARK: - Request

struct JevRequest: Codable {
    let model: String
    let state: CompactSurveyState
    let questions: [String: JevQuestion]
    
    static let standardQuestions: [String: JevQuestion] = [
        "visit_ready": JevQuestion(
            type: "noul",
            instructions: "Is the survey ready for a Base engineer visit given measured evidence and policy?"
        ),
        "next_action": JevQuestion(
            type: "choice",
            instructions: "What should the homeowner/operator do next?",
            criteria: [
                "proceed": "enough evidence to proceed toward engineer visit",
                "need_more_photos": "more photos or capture needed",
                "conflict": "measured conflict blocks proceeding"
            ]
        ),
        "blocking_gap": JevQuestion(
            type: "choice",
            instructions: "Which missing or failing evidence is the highest-priority blocker?",
            criteria: [
                "footprint": "3x3 footprint clearance unmeasured or failing",
                "transfer_switch": "transfer-switch space unmeasured or failing",
                "ocr": "meter/OCR or electrical numbers missing",
                "photos": "photo kit incomplete",
                "form": "home/personal form incomplete",
                "distances": "LiDAR/AR distances incomplete",
                "none": "no blocking gap"
            ]
        ),
        "readiness_score": JevQuestion(
            type: "score",
            instructions: "How ready is this survey for engineer review?",
            criteria: [
                "not started / mostly empty",
                "partial capture, major gaps",
                "usable draft, a few gaps",
                "visit-ready with measured checks"
            ]
        )
    ]
}

struct JevQuestion: Codable {
    let type: String
    let instructions: String
    let criteria: AnyCodable?
    
    init(type: String, instructions: String, criteria: [String: String]? = nil) {
        self.type = type
        self.instructions = instructions
        self.criteria = criteria.map(AnyCodable.init)
    }
}

// MARK: - Response

struct JevResponse: Codable {
    let answers: [String: JevAnswer]
}

struct JevAnswer: Codable {
    let noul: String?
    let choice: String?
    let score: Int?
    let confidence: Double?
    let probabilities: [String: Double]?
    let distribution: [Int]?
}

// MARK: - Advisory Result

struct JevAdvisory: Sendable {
    enum Status {
        case available
        case unavailable
    }
    
    let status: Status
    let reason: String?
    let answers: [String: JevAnswer]?
    
    init(status: Status, reason: String? = nil, answers: [String: JevAnswer]? = nil) {
        self.status = status
        self.reason = reason
        self.answers = answers
    }
    
    var visitReady: String? {
        answers?["visit_ready"]?.noul
    }
    
    var nextAction: String? {
        answers?["next_action"]?.choice
    }
    
    var blockingGap: String? {
        answers?["blocking_gap"]?.choice
    }
    
    var readinessScore: Int? {
        answers?["readiness_score"]?.score
    }
}

// MARK: - Compact State

struct CompactSurveyState: Codable {
    let photos: PhotoFlags
    let distances: Distances?
    let rules: [CompactRuleResult]
    let form: FormSummary
    let policy: PolicyCatalog
    
    init(session: SurveySession) {
        self.photos = PhotoFlags(
            meterPhoto: session.electrical.meterPhotoFilename != nil,
            breakerPhoto: session.electrical.breakerPhotoFilename != nil,
            arScreenshot: session.placement.screenshotFilename != nil
        )
        
        self.distances = Distances(
            batteryPlaced: session.placement.batteryPlaced,
            meterMarked: session.placement.meterMarked,
            gasMarked: session.placement.gasMeterMarked,
            panelMarked: session.placement.panelMarked,
            lidarAvailable: session.placement.lidarMeshAvailable,
            meterFeet: session.placement.distanceToMeterFeet,
            wallFeet: session.placement.distanceToWallFeet,
            gasFeet: session.placement.distanceToGasMeterFeet,
            meterHeightFeet: session.placement.meterHeightFeet,
            workingSpaceWidthInches: session.placement.frontWorkspaceWidthInches,
            workingSpaceDepthInches: session.placement.frontWorkspaceDepthInches,
            meterAndPanelSameWall: session.placement.meterAndPanelSameWall
        )
        
        self.rules = session.ruleResults.map { result in
            CompactRuleResult(
                id: result.id,
                title: result.title,
                status: result.status.rawValue,
                usedMeasuredEvidence: result.usedMeasuredEvidence,
                isRequired: result.isRequired
            )
        }
        
        self.form = FormSummary(
            homeownership: session.homeownership?.rawValue,
            hasSolar: session.electrical.hasSolar,
            hasStandby: session.electrical.hasStandbyGenerator,
            hasExistingBattery: session.electrical.hasExistingWholeHomeBattery,
            plannedCount: session.electrical.plannedBatteryCount,
            breakerA: session.electrical.mainBreakerAmperage,
            meterNumberPresent: !(session.electrical.meterNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        
        // Start with Austin as active; Houston is the second catalog
        self.policy = PolicyCatalog(
            active: "austin",
            catalogs: [
                "austin": PolicySpec(
                    breakerMin: 150,
                    breakerMax: 200,
                    solarTwoBatteryPanelA: 200,
                    footprintFeet: 3,
                    maxMeterDistanceFeet: 20,
                    maxWallDistanceFeet: 1,
                    minGasDistanceFeet: 3,
                    transferSwitchNote: "13 in wide, ~3 ft tall, 30 in clearance"
                ),
                "houston": PolicySpec(
                    breakerMin: 150,
                    breakerMax: 200,
                    solarTwoBatteryPanelA: 200,
                    footprintFeet: 3,
                    maxMeterDistanceFeet: 20,
                    maxWallDistanceFeet: 1,
                    minGasDistanceFeet: 3,
                    transferSwitchNote: "13 in wide, ~3 ft tall, 30 in clearance"
                )
            ]
        )
    }
}

struct PhotoFlags: Codable {
    let meterPhoto: Bool
    let breakerPhoto: Bool
    let arScreenshot: Bool
}

struct Distances: Codable {
    let batteryPlaced: Bool
    let meterMarked: Bool
    let gasMarked: Bool
    let panelMarked: Bool
    let lidarAvailable: Bool
    let meterFeet: Double?
    let wallFeet: Double?
    let gasFeet: Double?
    let meterHeightFeet: Double?
    let workingSpaceWidthInches: Double?
    let workingSpaceDepthInches: Double?
    let meterAndPanelSameWall: Bool?
}

struct CompactRuleResult: Codable {
    let id: String
    let title: String
    let status: String
    let usedMeasuredEvidence: Bool
    let isRequired: Bool
}

struct FormSummary: Codable {
    let homeownership: String?
    let hasSolar: Bool?
    let hasStandby: Bool?
    let hasExistingBattery: Bool?
    let plannedCount: Int?
    let breakerA: Int?
    let meterNumberPresent: Bool
}

struct PolicyCatalog: Codable {
    let active: String
    let catalogs: [String: PolicySpec]
}

struct PolicySpec: Codable {
    let breakerMin: Int
    let breakerMax: Int
    let solarTwoBatteryPanelA: Int
    let footprintFeet: Int
    let maxMeterDistanceFeet: Int
    let maxWallDistanceFeet: Int
    let minGasDistanceFeet: Int
    let transferSwitchNote: String
}

// MARK: - AnyCodable helper for flexible JSON

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let dict as [String: String]:
            try container.encode(dict)
        case let array as [String]:
            try container.encode(array)
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        default:
            try container.encodeNil()
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let dict = try? container.decode([String: String].self) {
            value = dict
        } else if let array = try? container.decode([String].self) {
            value = array
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }
}
